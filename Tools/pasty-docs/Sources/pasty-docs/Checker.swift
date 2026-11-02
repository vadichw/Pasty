import Foundation

struct Finding: CustomStringConvertible {
    enum Severity: String { case error, warning }
    let severity: Severity
    let file: String
    let line: Int
    let message: String

    var description: String { "\(file):\(line): \(severity.rawValue): \(message)" }

    /// GitHub Actions annotation, so problems show up on the PR diff.
    var annotation: String { "::\(severity.rawValue) file=\(file),line=\(line)::\(message)" }
}

/// Compares the facts extracted from code with what the READMEs claim.
/// Every rule is listed in docs/DOC_FORMAT.md.
struct Checker {
    let root: URL
    let facts: Facts
    let docs: [String: ModuleDoc]
    var findings: [Finding] = []

    init(root: URL, facts: Facts, docs: [String: ModuleDoc]) {
        self.root = root
        self.facts = facts
        self.docs = docs
    }

    mutating func run(base: String?) -> [Finding] {
        let modules = Set(facts.types.map(\.module))
        for module in modules.sorted() {
            guard let doc = docs[module] else {
                error("Sources/PastyCore/\(module)/README.md", 1, "module \(module) has no README.md")
                continue
            }
            checkModule(doc)
        }
        checkInvariants()
        if let base { checkChangedModules(base: base) }
        return findings
    }

    // MARK: - Modules and types

    private mutating func checkModule(_ doc: ModuleDoc) {
        if doc.title != doc.module { error(doc.path, 1, "the title must be `# \(doc.module)`") }
        if doc.fields.text("Purpose").isEmpty { error(doc.path, 1, "module has no `Purpose:`") }

        let expected = Set((facts.moduleGraph[doc.module] ?? [:]).keys)
        if !doc.fields.has("Depends on") {
            error(doc.path, 1, "module has no `Depends on:` line (code depends on: \(list(expected)))")
        } else {
            let claimed = Set(doc.fields.text("Depends on").split(separator: ",")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " .`")) }
                .filter { !$0.isEmpty && $0 != "none" && $0 != "—" })
            if claimed != expected {
                error(doc.path, doc.fields.lines["Depends on"] ?? 1,
                      "`Depends on:` says \(list(claimed)), code depends on \(list(expected))")
            }
        }

        let types = facts.types.filter { $0.module == doc.module }
        for type in types where type.isDocumented {
            guard let typeDoc = doc.types.first(where: { $0.name == type.name }) else {
                error(doc.path, 1, "\(type.file):\(type.line) `\(type.name)` is not documented (add `## \(type.name)`)")
                continue
            }
            checkType(type, typeDoc, path: doc.path)
        }
        for typeDoc in doc.types where !types.contains(where: { $0.name == typeDoc.name && !$0.isPrivate }) {
            error(doc.path, typeDoc.line, "`## \(typeDoc.name)` documents a type that does not exist in module \(doc.module)")
        }
    }

    private mutating func checkType(_ type: TypeFacts, _ doc: TypeDoc, path: String) {
        if doc.fields.text("Purpose").isEmpty { error(path, doc.line, "`\(type.name)` has no `Purpose:`") }

        if type.role == .view {
            let effects = Set(type.viewEffects.map(\.effect))
            checkEffects(claimed: doc.fields, actual: effects, what: "`\(type.name)`", path: path, line: doc.line)
            checkUses(claimed: doc.fields, actual: type.viewUses, what: "`\(type.name)`", path: path, line: doc.line)
            let handled = Set(type.viewEffects.filter { $0.errorHandling == .ignored || $0.errorHandling == .caught }.map(\.effect))
            checkErrors(doc.fields, handled: handled, what: "`\(type.name)`", path: path, line: doc.line)
            return
        }

        let documented = type.documentedMembers
        var covered: Set<String> = []
        for memberDoc in doc.members {
            let members = memberDoc.keys.compactMap { key in type.members.first { $0.key == key } }
            for key in memberDoc.keys where !type.members.contains(where: { $0.key == key && $0.isDocumented }) {
                let hint = type.members.first { $0.name == key.split(separator: "(").first.map(String.init) }?.key
                error(path, memberDoc.line, "`\(type.name).\(key)` does not exist" + (hint.map { " (did you mean `\($0)`?)" } ?? ""))
            }
            guard !members.isEmpty else { continue }
            covered.formUnion(members.map(\.key))
            checkMember(type: type, members: members, doc: memberDoc, path: path)
        }
        for member in documented where !covered.contains(member.key) {
            error(path, doc.line, "\(type.file):\(member.line) `\(type.name).\(member.key)` is not documented (add `### \(member.key)`)")
        }
    }

    private mutating func checkMember(type: TypeFacts, members: [Member], doc: MemberDoc, path: String) {
        let what = "`\(type.name).\(doc.keys.joined(separator: ", "))`"
        if doc.fields.text("Purpose").isEmpty { error(path, doc.line, "\(what) has no `Purpose:`") }
        if !doc.fields.has("Side effects") { error(path, doc.line, "\(what) has no `Side effects:` (write `Side effects: none` if it has none)") }

        let effects = Set(members.flatMap(\.effects))
        checkEffects(claimed: doc.fields, actual: effects, what: what, path: path, line: doc.line)
        checkUses(claimed: doc.fields, actual: Set(members.flatMap(\.allUses)), what: what, path: path, line: doc.line)
        checkErrors(doc.fields, handled: Set(members.flatMap(\.handledErrors)), what: what, path: path, line: doc.line)
        checkCallsLater(doc.fields, actual: Set(members.flatMap(\.allHandlers)), what: what, path: path, line: doc.line)

        // Order: each listed effect must first happen no later than the next one.
        let order = doc.fields.items("Order").flatMap(\.allTags)
        if members.count == 1, order.count > 1 {
            let first = members[0].firstOffset
            for (a, b) in zip(order, order.dropFirst()) {
                guard let ea = Effect(rawValue: a), let eb = Effect(rawValue: b),
                      let oa = first[ea], let ob = first[eb] else { continue }
                if oa > ob {
                    error(path, doc.fields.lines["Order"] ?? doc.line,
                          "\(what): `Order:` puts [\(a)] before [\(b)], but in the code [\(b)] comes first")
                }
            }
        }
    }

    private mutating func checkEffects(claimed fields: Fields, actual: Set<Effect>, what: String, path: String, line: Int) {
        var claimed: Set<Effect> = []
        for item in fields.items("Side effects") {
            let tags = item.tags
            if tags.isEmpty { error(path, item.line, "\(what): side effect bullet must start with a [category]: \(item.text)") }
            for tag in tags {
                guard let effect = Effect(rawValue: tag) else {
                    error(path, item.line, "\(what): unknown side effect category [\(tag)]")
                    continue
                }
                claimed.insert(effect)
            }
        }
        for tag in fields.items("Order").flatMap(\.allTags) where Effect(rawValue: tag).map({ !claimed.contains($0) }) ?? true {
            error(path, fields.lines["Order"] ?? line, "\(what): `Order:` mentions [\(tag)], which is not under `Side effects:`")
        }
        for effect in actual.subtracting(claimed).sorted() {
            error(path, fields.lines["Side effects"] ?? line, "\(what): code has side effect [\(effect.rawValue)] that the README does not mention")
        }
        for effect in claimed.subtracting(actual).sorted() {
            error(path, fields.lines["Side effects"] ?? line, "\(what): README claims side effect [\(effect.rawValue)] that the code does not have")
        }
    }

    private mutating func checkUses(claimed fields: Fields, actual: Set<String>, what: String, path: String, line: Int) {
        var claimed: Set<String> = []
        for item in fields.items("Uses") {
            guard let code = item.code else {
                error(path, item.line, "\(what): `Uses:` bullet must start with `Type.member`: \(item.text)")
                continue
            }
            claimed.insert(code)
        }
        for use in actual.subtracting(claimed).sorted() {
            error(path, fields.lines["Uses"] ?? line, "\(what): code uses `\(use)`, which is not under `Uses:`")
        }
        for use in claimed.subtracting(actual).sorted() {
            error(path, fields.lines["Uses"] ?? line, "\(what): README says it uses `\(use)`, but the code does not")
        }
    }

    /// Callbacks it stores (timers, observers, closures) — documented as their own entry points.
    private mutating func checkCallsLater(_ fields: Fields, actual: Set<String>, what: String, path: String, line: Int) {
        let claimed = Set(fields.items("Calls later").compactMap(\.code))
        for key in actual.subtracting(claimed).sorted() {
            error(path, fields.lines["Calls later"] ?? line, "\(what): code stores a callback to `\(key)`, which is not under `Calls later:`")
        }
        for key in claimed.subtracting(actual).sorted() {
            error(path, fields.lines["Calls later"] ?? line, "\(what): README says it calls `\(key)` later, but the code does not")
        }
    }

    private mutating func checkErrors(_ fields: Fields, handled: Set<Effect>, what: String, path: String, line: Int) {
        let explained = Set(fields.items("Errors").flatMap(\.tags).compactMap(Effect.init(rawValue:)))
        for effect in handled.subtracting(explained).sorted() {
            error(path, fields.lines["Errors"] ?? line,
                  "\(what): failures of [\(effect.rawValue)] are swallowed or caught in code; explain them under `Errors:` with a [\(effect.rawValue)] bullet")
        }
    }

    // MARK: - Invariants ↔ tests

    private mutating func checkInvariants() {
        var defined: [String: (String, Int)] = [:]
        for doc in docs.values {
            let all = [doc.fields] + doc.types.flatMap { [$0.fields] + $0.members.map(\.fields) }
            for fields in all {
                for item in fields.items("Invariants") {
                    guard let id = Self.invariantID(in: item.text), item.text.hasPrefix(id) else {
                        error(doc.path, item.line, "invariant must start with an ID like `INV-\(doc.module)-1:`")
                        continue
                    }
                    if let existing = defined[id] {
                        error(doc.path, item.line, "\(id) is already defined at \(existing.0):\(existing.1)")
                    }
                    defined[id] = (doc.path, item.line)
                }
            }
        }

        var tested: [String: (String, Int)] = [:]
        let testsRoot = root.appendingPathComponent("Tests")
        let enumerator = FileManager.default.enumerator(at: testsRoot, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift", let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let path = url.resolvingSymlinksInPath().path.replacingOccurrences(of: root.path + "/", with: "")
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                for id in Self.invariantIDs(in: line) {
                    tested[id] = tested[id] ?? (path, index + 1)
                    if defined[id] == nil { error(path, index + 1, "test refers to \(id), which no README defines") }
                }
            }
        }
        for (id, place) in defined.sorted(by: { $0.key < $1.key }) where tested[id] == nil {
            error(place.0, place.1, "\(id) has no test (mention `\(id)` in the test that proves it)")
        }
    }

    static func invariantIDs(in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: #"INV-[A-Za-z]+-\d+"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    static func invariantID(in text: String) -> String? { invariantIDs(in: text).first }

    // MARK: - Code changed, README not

    private mutating func checkChangedModules(base: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path, "diff", "--name-only", "\(base)...HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do { try process.run() } catch {
            warning("README.md", 1, "could not run git diff against \(base): \(error)")
            return
        }
        process.waitUntilExit()
        let changed = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .split(separator: "\n").map(String.init)
        let prefix = "Sources/PastyCore/"
        let modulesWithCode = Set(changed.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".swift") }
            .compactMap { $0.dropFirst(prefix.count).split(separator: "/").first.map(String.init) })
        for module in modulesWithCode.sorted() where !changed.contains("\(prefix)\(module)/README.md") {
            warning("\(prefix)\(module)/README.md", 1,
                    "code in \(module) changed since \(base) but its README.md did not — check that the README still describes it")
        }
    }

    // MARK: - Helpers

    private func list(_ set: Set<String>) -> String { set.isEmpty ? "none" : set.sorted().joined(separator: ", ") }

    private mutating func error(_ file: String, _ line: Int, _ message: String) {
        findings.append(Finding(severity: .error, file: file, line: line, message: message))
    }

    private mutating func warning(_ file: String, _ line: Int, _ message: String) {
        findings.append(Finding(severity: .warning, file: file, line: line, message: message))
    }
}
