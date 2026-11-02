import Foundation

/// Raw pasteboard contents: one dictionary (UTI -> data) per pasteboard item.
typealias ClipContents = [[String: Data]]

struct ClipItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case text, image, video, files
    }

    /// Only this much text is kept in memory for search and display; the full
    /// content stays on disk and is used when pasting.
    static let searchTextLimit = 2_000

    let id: UUID
    var kind: Kind
    /// Searchable text: the copied string, file paths, or an image description.
    var text: String
    /// Hash of the primary content, used to deduplicate repeated copies.
    var hash: String
    /// Source file for screenshots, screen recordings and copied media files.
    var filePath: String?
    var appBundleID: String?
    var firstCopied: Date
    var lastCopied: Date
    var copyCount: Int
    var pinned: Bool
    /// Size of the copied data — every type of every pasteboard item — in bytes.
    /// Missing in history saved by older versions; filled in from the data file on load.
    var byteCount: Int?

    /// Single-line representation for the list.
    var title: String {
        let collapsed = text
            .prefix(400)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsed.isEmpty ? "(whitespace)" : collapsed
    }

    /// Files this item refers to, for "Show in Finder" and missing-file checks.
    var fileURLs: [URL] {
        if let filePath { return [URL(fileURLWithPath: filePath)] }
        guard kind == .files else { return [] }
        return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }
}
