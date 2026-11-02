import AppKit
import Testing
@testable import PastyCore

@MainActor
struct StorageTests {
    @Test("INV-Storage-1: copying the same content again bumps the existing item instead of adding one")
    func duplicateBumpsExisting() {
        let store = makeStore()
        let first = addText(store, "a")
        let copiedAt = item(store, first).lastCopied
        addText(store, "b")
        let again = addText(store, "a", contents: [[plainTextType: Data("a".utf8), "public.rtf": Data("rtf".utf8)]])

        #expect(again == first)
        #expect(store.items.count == 2)
        #expect(store.items.first?.id == first)
        #expect(item(store, first).copyCount == 2)
        #expect(item(store, first).lastCopied > copiedAt)
        #expect(store.contents(for: item(store, first))?.first?["public.rtf"] == Data("rtf".utf8))
    }

    @Test("INV-Storage-2: pinned items first, then newest first")
    func ordering() {
        let store = makeStore()
        let a = addText(store, "a")
        let b = addText(store, "b")
        let c = addText(store, "c")
        store.togglePin(item(store, a))
        let d = addText(store, "d")
        #expect(store.items.map(\.id) == [a, d, c, b])

        store.touch(item(store, b))
        #expect(store.items.map(\.id) == [a, b, d, c])
    }

    @Test("INV-Storage-3: trim keeps the newest unpinned items up to the limit; pinned survive")
    func trimRespectsLimit() {
        let directory = temporaryDirectory()
        let limit = Limit(10)
        let store = makeStore(directory: directory, limit: limit)
        let oldest = addText(store, "oldest")
        store.togglePin(item(store, oldest))
        let dropped = addText(store, "dropped")
        for n in 0..<10 { addText(store, "item \(n)") }

        #expect(store.items.filter { !$0.pinned }.count == 10)
        #expect(store.items.contains { $0.id == oldest })
        #expect(!store.items.contains { $0.id == dropped })
        #expect(itemFiles(directory, dropped).isEmpty)

        limit.value = 3
        store.trim()
        #expect(store.items.filter { !$0.pinned }.map(\.text) == ["item 9", "item 8", "item 7"])
        #expect(store.items.contains { $0.id == oldest })
    }

    @Test("INV-Storage-4: clear(keepPinned: true) keeps exactly the pinned items and their files")
    func clearKeepsPinned() {
        let directory = temporaryDirectory()
        let store = makeStore(directory: directory)
        let pinned = addImage(store, "pinned")
        store.togglePin(item(store, pinned))
        let other = addText(store, "other")

        store.clear(keepPinned: true)
        #expect(store.items.map(\.id) == [pinned])
        #expect(Set(itemFiles(directory, pinned)) == ["\(pinned.uuidString).plist", "\(pinned.uuidString).png"])
        #expect(itemFiles(directory, other).isEmpty)

        store.clear(keepPinned: false)
        #expect(store.items.isEmpty)
        #expect(itemFiles(directory, pinned).isEmpty)
    }

    @Test("INV-Storage-5: remove deletes the item and both of its files")
    func removeDeletesFiles() {
        let directory = temporaryDirectory()
        let store = makeStore(directory: directory)
        let id = addImage(store, "photo")
        #expect(itemFiles(directory, id).count == 2)
        #expect(store.thumbnail(for: item(store, id)) != nil)

        let removed = item(store, id)
        store.remove(removed)
        #expect(store.items.isEmpty)
        #expect(itemFiles(directory, id).isEmpty)
        #expect(store.thumbnail(for: removed) == nil)
    }

    @Test("INV-Storage-6: what saveNow writes, a new store loads back unchanged")
    func roundTrip() {
        let directory = temporaryDirectory()
        let store = makeStore(directory: directory)
        addText(store, "one")
        let two = addImage(store, "two")
        store.togglePin(item(store, two))
        store.saveNow()

        let reloaded = makeStore(directory: directory)
        #expect(reloaded.items == store.items)
    }

    @Test("INV-Storage-7: load drops items without data and deletes files that belong to no item")
    func loadCleansUp() throws {
        let directory = temporaryDirectory()
        let store = makeStore(directory: directory)
        let lost = addText(store, "lost")
        let kept = addText(store, "kept")
        store.saveNow()
        let itemsDirectory = directory.appendingPathComponent("items")
        try FileManager.default.removeItem(at: itemsDirectory.appendingPathComponent("\(lost.uuidString).plist"))
        let orphan = itemsDirectory.appendingPathComponent("\(UUID().uuidString).plist")
        try Data("junk".utf8).write(to: orphan)

        let reloaded = makeStore(directory: directory)
        #expect(reloaded.items.map(\.id) == [kept])
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test("INV-Storage-8: contents(for:) returns exactly what the latest add stored")
    func contentsRoundTrip() {
        let store = makeStore()
        let contents: ClipContents = [
            [plainTextType: Data("hello".utf8), "public.html": Data("<b>hello</b>".utf8)],
            ["com.example.custom": Data([0, 1, 2, 255])],
        ]
        let id = addText(store, "hello", contents: contents)
        #expect(store.contents(for: item(store, id)) == contents)

        let newer: ClipContents = [[plainTextType: Data("hello".utf8)]]
        addText(store, "hello", contents: newer)
        #expect(store.contents(for: item(store, id)) == newer)
    }

    @Test("INV-Storage-9: titles are one line; whitespace-only text shows as (whitespace)")
    func titles() {
        func clip(_ text: String) -> ClipItem {
            ClipItem(id: UUID(), kind: .text, text: text, hash: "", filePath: nil, appBundleID: nil,
                     firstCopied: Date(), lastCopied: Date(), copyCount: 1, pinned: false)
        }
        #expect(clip("first\n\n  second\tthird").title == "first second third")
        #expect(clip(" \n\t ").title == "(whitespace)")
    }

    @Test("INV-Storage-11: usage counts unpinned items against the current limit")
    func usage() {
        let limit = Limit(50)
        let store = makeStore(limit: limit)
        let pinned = addText(store, "pinned")
        store.togglePin(item(store, pinned))
        addText(store, "a")
        addText(store, "b")
        #expect(store.usage == (used: 2, limit: 50))
        limit.value = 20
        #expect(store.usage.limit == 20)
    }

    @Test("INV-Storage-15: totalBytes is the sum of the items' sizes")
    func totalBytes() {
        let store = makeStore()
        #expect(store.totalBytes == 0)
        let a = addText(store, "a", contents: [[plainTextType: Data(count: 100)]])
        addText(store, "b", contents: [[plainTextType: Data(count: 250)], ["x": Data(count: 50)]])
        #expect(store.totalBytes == 400)
        store.remove(item(store, a))
        #expect(store.totalBytes == 300)
    }

    @Test("INV-Storage-13: byteCount is the size of every format of the latest copy")
    func itemSize() {
        let store = makeStore()
        let id = addText(store, "hi", contents: [[plainTextType: Data(count: 10), "public.html": Data(count: 30)], ["x": Data(count: 5)]])
        #expect(item(store, id).byteCount == 45)
        addText(store, "hi", contents: [[plainTextType: Data(count: 7)]])
        #expect(item(store, id).byteCount == 7)
    }

    @Test("INV-Storage-14: items saved without a size get it on load: exact for small files, file size for big ones")
    func sizeBackfill() throws {
        let directory = temporaryDirectory()
        let store = makeStore(directory: directory)
        let small = addText(store, "old", contents: [[plainTextType: Data(count: 1000)]])
        let big = addText(store, "big", contents: [["public.png": Data(count: 2 * 1024 * 1024)]])
        store.saveNow()
        // Rewrite history.json the way older versions saved it: without byteCount.
        let index = directory.appendingPathComponent("history.json")
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: index)) as! [[String: Any]]
        for i in json.indices { json[i]["byteCount"] = nil }
        try JSONSerialization.data(withJSONObject: json).write(to: index)

        let reloaded = makeStore(directory: directory)
        #expect(item(reloaded, small).byteCount == 1000)
        let plist = directory.appendingPathComponent("items/\(big.uuidString).plist")
        let fileSize = try FileManager.default.attributesOfItem(atPath: plist.path)[.size] as? Int
        #expect(item(reloaded, big).byteCount == fileSize)
    }

    @Test("INV-Storage-10: fullImage prefers the source file and falls back to the stored data")
    func fullImageSources() throws {
        let store = makeStore()
        let file = temporaryDirectory().appendingPathComponent("shot.png")
        try pngData(width: 30, height: 20).write(to: file)
        let id = store.add(kind: .image, text: "shot.png", hash: "file:" + file.path,
                           contents: [[NSPasteboard.PasteboardType.png.rawValue: pngData(width: 6, height: 5)]],
                           appBundleID: nil, thumbnail: nil, filePath: file.path)

        #expect(store.fullImage(for: item(store, id))?.representations.first?.pixelsWide == 30)
        try FileManager.default.removeItem(at: file)
        #expect(store.fullImage(for: item(store, id))?.representations.first?.pixelsWide == 6)
    }
}
