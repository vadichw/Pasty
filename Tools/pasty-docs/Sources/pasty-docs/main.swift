import Foundation

/// pasty-docs facts [--root DIR]                 JSON facts extracted from Sources/PastyCore
/// pasty-docs check [--root DIR] [--base REF]    compare the facts with the module READMEs
/// pasty-docs graph [--root DIR] [--write]       module graph for docs/ARCHITECTURE.md

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? "check"

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

// Resolved, so paths from the file enumerator (which follows /tmp -> /private/tmp) share its prefix.
let root = URL(fileURLWithPath: option("--root") ?? FileManager.default.currentDirectoryPath)
    .standardizedFileURL.resolvingSymlinksInPath()
let sources = root.appendingPathComponent("Sources/PastyCore")
let architectureURL = root.appendingPathComponent("docs/ARCHITECTURE.md")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func loadDocs(modules: Set<String>) -> [String: ModuleDoc] {
    var docs: [String: ModuleDoc] = [:]
    for module in modules {
        let path = "Sources/PastyCore/\(module)/README.md"
        guard let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8) else { continue }
        docs[module] = DocParser.parse(module: module, path: path, text: text)
    }
    return docs
}

let facts: Facts
do {
    facts = try Extractor(sourcesRoot: sources).extract()
} catch {
    fail("pasty-docs: cannot read \(sources.path): \(error)")
}

switch command {
case "facts":
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(facts), as: UTF8.self))

case "graph":
    let block = Graph.markdown(facts)
    if arguments.contains("--write") {
        do {
            try Graph.write(block, to: architectureURL)
            print("Updated docs/ARCHITECTURE.md")
        } catch {
            fail("pasty-docs: \(error)")
        }
    } else {
        print(block)
    }

case "check":
    let docs = loadDocs(modules: Set(facts.types.map(\.module)))
    var checker = Checker(root: root, facts: facts, docs: docs)
    var findings = checker.run(base: option("--base"))
    if let problem = Graph.check(Graph.markdown(facts), at: architectureURL) {
        findings.append(Finding(severity: .error, file: "docs/ARCHITECTURE.md", line: 1, message: problem))
    }
    let inCI = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
    for finding in findings { print(inCI ? finding.annotation : finding.description) }
    let errors = findings.filter { $0.severity == .error }.count
    let warnings = findings.count - errors
    print(errors == 0
          ? "Docs match the code (\(warnings) warning\(warnings == 1 ? "" : "s"))."
          : "\(errors) error\(errors == 1 ? "" : "s"), \(warnings) warning\(warnings == 1 ? "" : "s").")
    exit(errors == 0 ? 0 : 1)

default:
    fail("usage: pasty-docs facts|check|graph [--root DIR] [--base REF] [--write]")
}
