import AppKit
import Testing
@testable import PastyCore

@MainActor
struct PopupModelTests {
    let store = makeStore()
    let model: PopupModel
    /// Every value passed to `onPreview`, in order.
    var previews: [UUID?] { previewLog.values }
    private let previewLog = Log()

    final class Log { var values: [UUID?] = [] }

    init() {
        model = PopupModel(store: store)
        model.onPreview = { [previewLog] in previewLog.values.append($0?.id) }
    }

    @Test("INV-Popup-1: every query word must match, in any order, ignoring case")
    func search() {
        addText(store, "Hello World")
        addText(store, "world peace")
        addText(store, "foo")
        model.query = "WORLD hello"
        #expect(model.visible.map(\.text) == ["Hello World"])
        model.query = "world"
        #expect(Set(model.visible.map(\.text)) == ["Hello World", "world peace"])
        model.query = ""
        #expect(model.visible.count == 3)
    }

    @Test("INV-Popup-2: the selection is always a visible item, or nothing when the list is empty")
    func selectionStaysVisible() {
        let a = addText(store, "apple")
        let b = addText(store, "banana")
        model.selectedID = a
        model.query = "banana"
        #expect(model.selectedID == b)
        model.query = "cherry"
        #expect(model.selectedID == nil)
        model.query = ""
        model.selectedID = b
        store.remove(item(store, b)) // deleted elsewhere, e.g. from Settings
        #expect(model.selectedID == a)
    }

    @Test("INV-Popup-3: deleting the selected item selects the next one, or the previous if it was last")
    func deleteMovesSelection() {
        let a = addText(store, "a")
        let b = addText(store, "b")
        let c = addText(store, "c") // visible: c, b, a
        model.selectedID = b
        model.remove()
        #expect(model.selectedID == a)
        model.remove()
        #expect(model.selectedID == c)
    }

    @Test("INV-Popup-4: the selection stops at the first and last rows")
    func moveClamps() {
        let a = addText(store, "a")
        addText(store, "b")
        let c = addText(store, "c")
        model.reset()
        model.move(-5)
        #expect(model.selectedID == c)
        model.move(100)
        #expect(model.selectedID == a)
        model.moveToEdge(top: true)
        #expect(model.selectedID == c)
    }

    @Test("INV-Popup-5: an open preview follows the selection to images and videos, and closes on other items")
    func previewFollowsSelection() {
        addText(store, "text")
        let video = addVideo(store, "recording")
        let second = addImage(store, "second")
        let first = addImage(store, "first") // visible: first, second, recording, text
        model.reset()
        model.togglePreview()
        #expect(model.previewID == first)
        model.move(1)
        #expect(model.previewID == second)
        model.move(1)
        #expect(model.previewID == video)
        model.move(1)
        #expect(model.previewID == nil)
        #expect(previews == [first, second, video, nil])
    }

    @Test("INV-Popup-6: deleting the previewed item closes the preview")
    func deletePreviewed() {
        let image = addImage(store, "image")
        model.reset()
        model.togglePreview()
        model.remove(item(store, image))
        #expect(model.previewID == nil)
        #expect(previews == [image, nil])
    }

    @Test("INV-Popup-7: only images and videos can be previewed; ⌘Y toggles; the eye button switches or toggles")
    func previewToggling() {
        let video = addVideo(store, "clip")
        let other = addImage(store, "other")
        let image = addImage(store, "image")
        let text = addText(store, "text") // visible: text, image, other
        model.reset()
        #expect(model.selectedID == text)
        model.togglePreview()
        #expect(model.previewID == nil)

        model.selectedID = image
        model.togglePreview()
        #expect(model.previewID == image)
        model.togglePreview(item(store, other))
        #expect(model.previewID == other)
        model.togglePreview(item(store, other))
        #expect(model.previewID == nil)
        model.togglePreview()
        model.togglePreview()
        #expect(model.previewID == nil)
        model.togglePreview(item(store, video))
        #expect(model.previewID == video)
        #expect(previews == [image, other, nil, image, nil, video])
    }
}

struct ByteSizeTests {
    @Test("INV-Popup-13: under 1000 bytes in B, from 1000 in KB/MB like Finder")
    func format() {
        #expect(ByteSize.format(0) == "0 B")
        #expect(ByteSize.format(368) == "368 B")
        #expect(ByteSize.format(999) == "999 B")
        #expect(ByteSize.format(1000) == ByteCountFormatter.string(fromByteCount: 1000, countStyle: .file))
        #expect(ByteSize.format(2_100_000).hasSuffix("MB"))
    }
}

struct UsageLevelTests {
    @Test("INV-Popup-11: under 70 % low, 70–90 % medium, from 90 % high", arguments: [
        (0, 2000, UsageLevel.low), (1399, 2000, .low), (1400, 2000, .medium),
        (1799, 2000, .medium), (1800, 2000, .high), (2000, 2000, .high), (0, 0, .high),
    ])
    func thresholds(used: Int, limit: Int, expected: UsageLevel) {
        #expect(UsageLevel.of(used: used, limit: limit) == expected)
    }
}

@MainActor
struct MediaPreviewTests {
    let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    private func check(_ frame: NSRect, image: NSSize, popup: NSRect, overlapAllowed: Bool) {
        #expect(screen.insetBy(dx: 8, dy: 8).contains(frame))
        #expect(frame.width <= image.width && frame.height <= image.height)
        #expect(abs(frame.width / frame.height - image.width / image.height) < 0.02)
        if !overlapAllowed { #expect(!frame.intersects(popup)) }
    }

    @Test("INV-Popup-10: the preview fits the screen, keeps the aspect ratio, never grows, and sits beside the popup")
    func placement() {
        let big = NSSize(width: 2604, height: 1320)
        let leftPopup = NSRect(x: 100, y: 300, width: 420, height: 480)
        let right = MediaPreview.frame(size: big, beside: leftPopup, in: screen)
        check(right, image: big, popup: leftPopup, overlapAllowed: false)
        #expect(right.minX > leftPopup.maxX)

        let rightPopup = NSRect(x: 1000, y: 300, width: 420, height: 480)
        let left = MediaPreview.frame(size: big, beside: rightPopup, in: screen)
        check(left, image: big, popup: rightPopup, overlapAllowed: false)
        #expect(left.maxX < rightPopup.minX)

        let small = NSSize(width: 120, height: 80)
        #expect(MediaPreview.frame(size: small, beside: leftPopup, in: screen).size == small)

        let narrowScreen = NSRect(x: 0, y: 0, width: 900, height: 900)
        let middlePopup = NSRect(x: 250, y: 300, width: 420, height: 480) // < 240 pt on both sides
        let centered = MediaPreview.frame(size: big, beside: middlePopup, in: narrowScreen)
        #expect(narrowScreen.insetBy(dx: 8, dy: 8).contains(centered))
        #expect(abs(centered.midX - narrowScreen.midX) < 1)
    }
}

extension UsesPrefs {
    @MainActor
    struct PopupControllerTests {
        let store = makeStore()
        let controller: PopupController

        init() {
            useScratchDefaults()
            _ = NSApplication.shared
            controller = PopupController(store: store)
        }

        @Test("INV-Popup-8: the popup does not reopen within 0.25 s after hiding")
        func noImmediateReopen() async throws {
            defer { controller.tearDown() }
            controller.toggle(anchor: .center)
            #expect(controller.isVisible)
            controller.toggle(anchor: .center)
            #expect(!controller.isVisible)
            controller.toggle(anchor: .center)
            #expect(!controller.isVisible)
            try await Task.sleep(for: .milliseconds(300))
            controller.toggle(anchor: .center)
            #expect(controller.isVisible)
            controller.hide()
        }

        @Test("INV-Popup-9: ⇧ flips plain text and ⌥ flips automatic pasting, relative to the settings")
        func modifierKeys() {
            defer { controller.tearDown() }
            let id = addText(store, "x")
            var chosen: [(plain: Bool, paste: Bool)] = []
            controller.onSelect = { _, plain, paste in chosen.append((plain, paste)) }

            controller.model.select(item(store, id), modifiers: [])
            controller.model.select(item(store, id), modifiers: .shift)
            controller.model.select(item(store, id), modifiers: .option)
            Prefs.defaults.set(false, forKey: Prefs.Key.pasteAutomatically)
            Prefs.defaults.set(true, forKey: Prefs.Key.pastePlainByDefault)
            controller.model.select(item(store, id), modifiers: .option)
            controller.model.select(item(store, id), modifiers: .shift)

            #expect(chosen.map(\.plain) == [false, true, false, true, false])
            #expect(chosen.map(\.paste) == [true, true, false, true, false])
        }
    }
}
