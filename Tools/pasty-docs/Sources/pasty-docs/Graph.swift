import Foundation

/// The module graph in docs/ARCHITECTURE.md is generated from code, never edited by hand.
enum Graph {
    static let begin = "<!-- BEGIN GENERATED: module-graph (pasty-docs graph --write) -->"
    static let end = "<!-- END GENERATED: module-graph -->"

    static func markdown(_ facts: Facts) -> String {
        let graph = facts.moduleGraph
        var lines = [begin, "", "```mermaid", "graph LR"]
        for module in graph.keys.sorted() {
            let targets = graph[module] ?? [:]
            if targets.isEmpty { lines.append("    \(module)") }
            for target in targets.keys.sorted() { lines.append("    \(module) --> \(target)") }
        }
        lines += ["```", "", "| From | To | What it uses |", "|---|---|---|"]
        for module in graph.keys.sorted() {
            for (target, uses) in (graph[module] ?? [:]).sorted(by: { $0.key < $1.key }) {
                let list = uses.sorted().map { "`\($0)`" }.joined(separator: ", ")
                lines.append("| \(module) | \(target) | \(list) |")
            }
        }
        lines += ["", end]
        return lines.joined(separator: "\n")
    }

    static func write(_ block: String, to url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard let range = generatedRange(in: text) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "no generated block markers in \(url.lastPathComponent)"])
        }
        try text.replacingCharacters(in: range, with: block).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Nil if the file has the up-to-date block.
    static func check(_ block: String, at url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "docs/ARCHITECTURE.md is missing" }
        guard let range = generatedRange(in: text) else { return "docs/ARCHITECTURE.md has no generated module-graph block" }
        return text[range] == block ? nil : "module graph is out of date — run scripts/check_docs.sh --fix"
    }

    private static func generatedRange(in text: String) -> Range<String.Index>? {
        guard let start = text.range(of: begin), let finish = text.range(of: end, range: start.upperBound..<text.endIndex) else { return nil }
        return start.lowerBound..<finish.upperBound
    }
}
