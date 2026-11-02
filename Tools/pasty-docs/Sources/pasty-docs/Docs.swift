import Foundation

/// A bullet or inline value under a field, with the `[tags]` it starts with.
struct DocLine {
    let text: String
    let line: Int
    var tags: [String] {
        var rest = Substring(text)
        var tags: [String] = []
        while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            tags.append(String(rest[rest.index(after: rest.startIndex)..<close]))
            rest = rest[rest.index(after: close)...].drop { $0 == " " }
        }
        return tags
    }
    /// Every `[tag]` anywhere in the text, e.g. both in `[disk-write] → [schedule]`.
    var allTags: [String] {
        let regex = try! NSRegularExpression(pattern: #"\[([a-z-]+)\]"#)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } }
    }

    /// First `code span`, e.g. the `Type.member` of a `Uses:` bullet.
    var code: String? {
        guard let open = text.firstIndex(of: "`") else { return nil }
        let after = text.index(after: open)
        guard let close = text[after...].firstIndex(of: "`") else { return nil }
        return String(text[after..<close])
    }
}

/// The fields of a module, type or member section.
struct Fields {
    static let names = ["Purpose", "Input", "Output", "Side effects", "Uses", "Calls later", "Order", "Invariants", "Errors", "Depends on"]

    var values: [String: [DocLine]] = [:]
    /// Field name -> line where it starts.
    var lines: [String: Int] = [:]

    func has(_ name: String) -> Bool { lines[name] != nil }

    /// Bullets plus any inline text, ignoring a literal "none".
    func items(_ name: String) -> [DocLine] {
        (values[name] ?? []).filter { !["none", "none.", "—", "-"].contains($0.text.lowercased()) }
    }

    func text(_ name: String) -> String {
        (values[name] ?? []).map(\.text).joined(separator: " ")
    }
}

struct MemberDoc {
    let heading: String
    let keys: [String]
    let line: Int
    var fields = Fields()
}

struct TypeDoc {
    let name: String
    let line: Int
    var fields = Fields()
    var members: [MemberDoc] = []
}

struct ModuleDoc {
    let module: String
    let path: String
    var title: String?
    var fields = Fields()
    var types: [TypeDoc] = []
}

enum DocParser {
    static func parse(module: String, path: String, text: String) -> ModuleDoc {
        var doc = ModuleDoc(module: module, path: path)
        var field: String?
        var inFence = false

        func setField(_ name: String, inline: String, line: Int) {
            field = name
            func apply(_ fields: inout Fields) {
                fields.lines[name] = line
                fields.values[name] = inline.isEmpty ? [] : [DocLine(text: inline, line: line)]
            }
            if var type = doc.types.popLast() {
                if var member = type.members.popLast() {
                    apply(&member.fields)
                    type.members.append(member)
                } else {
                    apply(&type.fields)
                }
                doc.types.append(type)
            } else {
                apply(&doc.fields)
            }
        }

        func append(_ value: DocLine) {
            guard let field else { return }
            if var type = doc.types.popLast() {
                if var member = type.members.popLast() {
                    member.fields.values[field, default: []].append(value)
                    type.members.append(member)
                } else {
                    type.fields.values[field, default: []].append(value)
                }
                doc.types.append(type)
            } else {
                doc.fields.values[field, default: []].append(value)
            }
        }

        for (index, raw) in text.components(separatedBy: "\n").enumerated() {
            let line = index + 1
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); continue }
            if inFence { continue }

            if trimmed.hasPrefix("### ") {
                let heading = String(trimmed.dropFirst(4))
                guard var type = doc.types.popLast() else { continue }
                type.members.append(MemberDoc(heading: heading, keys: memberKeys(heading), line: line))
                doc.types.append(type)
                field = nil
            } else if trimmed.hasPrefix("## ") {
                let name = String(trimmed.dropFirst(3)).trimmingCharacters(in: CharacterSet(charactersIn: "` "))
                doc.types.append(TypeDoc(name: name, line: line))
                field = nil
            } else if trimmed.hasPrefix("# ") {
                doc.title = String(trimmed.dropFirst(2))
                field = nil
            } else if let (name, inline) = fieldStart(trimmed) {
                setField(name, inline: inline, line: line)
            } else if trimmed.hasPrefix("- ") {
                append(DocLine(text: String(trimmed.dropFirst(2)), line: line))
            } else if !trimmed.isEmpty, raw.hasPrefix("  "), field != nil {
                // Continuation of the previous bullet: part of the text, not a new item.
                continue
            } else if trimmed.isEmpty {
                continue
            }
        }
        return doc
    }

    private static func fieldStart(_ line: String) -> (String, String)? {
        for name in Fields.names where line.hasPrefix(name + ":") {
            return (name, String(line.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    /// `add(kind:text:) -> UUID` -> ["add(kind:text:)"];
    /// `historyLimit, saveImages: Bool` -> ["historyLimit", "saveImages"].
    static func memberKeys(_ heading: String) -> [String] {
        var keys: [String] = []
        var current = ""
        var depth = 0
        var done = false // past the key of the current entry (in a type annotation or return type)
        for char in heading.replacingOccurrences(of: "`", with: "") {
            switch char {
            case "(":
                depth += 1
                if !done { current.append(char) }
            case ")":
                depth -= 1
                if !done { current.append(char) }
                if depth == 0 && !done { done = true }
            case "," where depth == 0:
                if !current.isEmpty { keys.append(current) }
                current = ""
                done = false
            case ":" where depth == 0, " " where depth == 0 && !current.isEmpty:
                done = true
            default:
                if !done && char != " " { current.append(char) }
            }
        }
        if !current.isEmpty { keys.append(current) }
        return keys
    }
}
