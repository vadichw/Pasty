import AppKit
import CryptoKit
import UniformTypeIdentifiers

/// Persists history metadata in `history.json` and the raw pasteboard data of each
/// item in a separate binary plist (`items/<id>.plist`), loaded only when needed.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private let fm = FileManager.default
    private let baseURL: URL
    private let itemsURL: URL
    private var indexURL: URL { baseURL.appendingPathComponent("history.json") }
    private var saveScheduled = false
    private let thumbnails: NSCache<NSUUID, NSImage> = {
        let cache = NSCache<NSUUID, NSImage>()
        cache.countLimit = 60
        return cache
    }()

    init() {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        baseURL = support.appendingPathComponent("Pasty", isDirectory: true)
        itemsURL = baseURL.appendingPathComponent("items", isDirectory: true)
        try? fm.createDirectory(at: itemsURL, withIntermediateDirectories: true)
        load()
    }

    static func hash(_ string: String) -> String { hash(Data(string.utf8)) }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Mutations

    /// Adds an item (or bumps an existing one with the same hash) and returns its id.
    @discardableResult
    func add(kind: ClipItem.Kind, text: String, hash: String, contents: ClipContents,
             appBundleID: String?, thumbnail: Data?, filePath: String? = nil) -> UUID {
        let now = Date()
        let id: UUID
        if let index = items.firstIndex(where: { $0.hash == hash }) {
            id = items[index].id
            items[index].lastCopied = now
            items[index].copyCount += 1
            items[index].appBundleID = appBundleID ?? items[index].appBundleID
            writeContents(contents, for: id)
        } else {
            let item = ClipItem(
                id: UUID(), kind: kind, text: text, hash: hash, filePath: filePath, appBundleID: appBundleID,
                firstCopied: now, lastCopied: now, copyCount: 1, pinned: false
            )
            id = item.id
            writeContents(contents, for: id)
            if let thumbnail { try? thumbnail.write(to: thumbnailURL(id)) }
            items.append(item)
        }
        sort()
        trim()
        scheduleSave()
        return id
    }

    /// Fills in details computed asynchronously (e.g. a video's thumbnail and duration).
    func updateMedia(id: UUID, thumbnail: Data?, text: String?) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if let thumbnail {
            try? thumbnail.write(to: thumbnailURL(id))
            thumbnails.removeObject(forKey: id as NSUUID)
        }
        var item = items[index]
        if let text { item.text = text }
        items[index] = item
        scheduleSave()
    }

    /// Moves an item to the top after it was pasted from history.
    func touch(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].lastCopied = Date()
        items[index].copyCount += 1
        sort()
        scheduleSave()
    }

    func togglePin(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].pinned.toggle()
        sort()
        trim()
        scheduleSave()
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        deleteFiles(item.id)
        scheduleSave()
    }

    func clear(keepPinned: Bool) {
        let removed = items.filter { !keepPinned || !$0.pinned }
        removed.forEach { deleteFiles($0.id) }
        let removedIDs = Set(removed.map(\.id))
        items.removeAll { removedIDs.contains($0.id) }
        scheduleSave()
    }

    /// Drops the oldest unpinned items beyond the configured limit.
    func trim() {
        let unpinned = items.filter { !$0.pinned }
        let limit = Prefs.historyLimit
        guard unpinned.count > limit else { return }
        let dropped = unpinned[limit...]
        dropped.forEach { deleteFiles($0.id) }
        let droppedIDs = Set(dropped.map(\.id))
        items.removeAll { droppedIDs.contains($0.id) }
        scheduleSave()
    }

    // MARK: - Reading

    func contents(for item: ClipItem) -> ClipContents? {
        guard let data = try? Data(contentsOf: contentsURL(item.id)) else { return nil }
        return try? PropertyListDecoder().decode(ClipContents.self, from: data)
    }

    /// Full-size image for the preview: the source file if it still exists,
    /// otherwise the image data stored with the item.
    func fullImage(for item: ClipItem) -> NSImage? {
        if let filePath = item.filePath, let image = NSImage(contentsOfFile: filePath) { return image }
        guard let first = contents(for: item)?.first else { return nil }
        let data = first.first { type, _ in UTType(type)?.conforms(to: .image) == true }?.value
        return data.flatMap(NSImage.init(data:))
    }

    func purgeCaches() {
        thumbnails.removeAllObjects()
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        let key = item.id as NSUUID
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: thumbnailURL(item.id)) else { return nil }
        thumbnails.setObject(image, forKey: key)
        return image
    }

    // MARK: - Persistence

    private func sort() {
        items.sort { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.lastCopied > b.lastCopied
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) {
            items = decoded.filter { fm.fileExists(atPath: contentsURL($0.id).path) }
            // Older versions kept up to 20k characters per item in memory.
            for index in items.indices where items[index].text.count > ClipItem.searchTextLimit {
                items[index].text = String(items[index].text.prefix(ClipItem.searchTextLimit))
            }
            sort()
        }
        removeOrphanFiles()
    }

    private func removeOrphanFiles() {
        let known = Set(items.map(\.id.uuidString))
        let files = (try? fm.contentsOfDirectory(at: itemsURL, includingPropertiesForKeys: nil)) ?? []
        for file in files where !known.contains(file.deletingPathExtension().lastPathComponent) {
            try? fm.removeItem(at: file)
        }
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.saveNow()
        }
    }

    func saveNow() {
        saveScheduled = false
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func contentsURL(_ id: UUID) -> URL {
        itemsURL.appendingPathComponent(id.uuidString + ".plist")
    }

    private func thumbnailURL(_ id: UUID) -> URL {
        itemsURL.appendingPathComponent(id.uuidString + ".png")
    }

    private func writeContents(_ contents: ClipContents, for id: UUID) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(contents) else { return }
        try? data.write(to: contentsURL(id), options: .atomic)
    }

    private func deleteFiles(_ id: UUID) {
        try? fm.removeItem(at: contentsURL(id))
        try? fm.removeItem(at: thumbnailURL(id))
        thumbnails.removeObject(forKey: id as NSUUID)
    }
}
