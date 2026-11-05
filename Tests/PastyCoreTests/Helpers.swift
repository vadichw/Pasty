import AppKit
import Testing
@testable import PastyCore

/// Tests that read or write `Prefs` share one global `UserDefaults`, so they run one at a time.
/// Each test gets a fresh scratch suite instead of the user's real settings.
@Suite(.serialized) @MainActor enum UsesPrefs {}

@MainActor
func useScratchDefaults() {
    Prefs.defaults = UserDefaults(suiteName: "PastyTests-\(UUID().uuidString)")!
    Prefs.registerDefaults()
}

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("PastyTests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A private pasteboard, so tests never touch the user's clipboard.
func scratchPasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("PastyTests-\(UUID().uuidString)"))
}

/// A box the store's `historyLimit` closure reads, so tests can change the limit.
final class Limit { var value: Int; init(_ value: Int) { self.value = value } }

@MainActor
func makeStore(directory: URL = temporaryDirectory(), limit: Limit = Limit(100)) -> HistoryStore {
    HistoryStore(directory: directory, historyLimit: { limit.value })
}

let plainTextType = NSPasteboard.PasteboardType.string.rawValue

@MainActor @discardableResult
func addText(_ store: HistoryStore, _ text: String, contents: ClipContents? = nil) -> UUID {
    usleep(1000) // distinct `lastCopied` timestamps, so the expected order is unambiguous
    return store.add(kind: .text, text: text, hash: HistoryStore.hash("text:" + text),
                     contents: contents ?? [[plainTextType: Data(text.utf8)]], appBundleID: nil, thumbnail: nil)
}

@MainActor @discardableResult
func addImage(_ store: HistoryStore, _ name: String, width: Int = 4, height: Int = 4) -> UUID {
    usleep(1000)
    let png = pngData(width: width, height: height)
    return store.add(kind: .image, text: name, hash: HistoryStore.hash("image:" + name),
                     contents: [[NSPasteboard.PasteboardType.png.rawValue: png]], appBundleID: nil, thumbnail: png)
}

@MainActor @discardableResult
func addVideo(_ store: HistoryStore, _ name: String) -> UUID {
    usleep(1000)
    let path = temporaryDirectory().appendingPathComponent("\(name).mov").path
    FileManager.default.createFile(atPath: path, contents: Data())
    return store.add(kind: .video, text: name, hash: HistoryStore.hash("file:" + path),
                     contents: [[NSPasteboard.PasteboardType.fileURL.rawValue: Data("file://\(path)".utf8)]],
                     appBundleID: nil, thumbnail: nil, filePath: path)
}

func pngData(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    return rep.representation(using: .png, properties: [:])!
}

@MainActor
func item(_ store: HistoryStore, _ id: UUID) -> ClipItem {
    store.items.first { $0.id == id }!
}

/// Files of an item in `<directory>/items/`.
func itemFiles(_ directory: URL, _ id: UUID) -> [String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("items").path)) ?? []
    return names.filter { $0.hasPrefix(id.uuidString) }
}
