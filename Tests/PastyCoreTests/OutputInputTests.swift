import AppKit
import Carbon.HIToolbox
import Testing
@testable import PastyCore

@MainActor
struct OutputTests {
    let pasteboard = scratchPasteboard()

    @Test("INV-Output-1: plain-text paste leaves only the plain string on the clipboard")
    func plainText() {
        let contents: ClipContents = [[plainTextType: Data("hello".utf8), "public.rtf": Data("{\\rtf1 hello}".utf8)]]
        let item = ClipItem(id: UUID(), kind: .text, text: "hello", hash: "", filePath: nil, appBundleID: nil,
                            firstCopied: Date(), lastCopied: Date(), copyCount: 1, pinned: false)
        Paster.write(contents, item: item, plainText: true, to: pasteboard)

        #expect(pasteboard.pasteboardItems?.count == 1)
        // macOS adds the legacy alias of the plain-text type by itself; nothing else may be there.
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        #expect(types.isSubset(of: [plainTextType, "NSStringPboardType"]))
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("public.rtf")) == nil)
        #expect(pasteboard.string(forType: .string) == "hello")
    }

    @Test("INV-Output-2: every type of every item is restored byte for byte")
    func allTypes() {
        let contents: ClipContents = [
            ["com.example.a": Data([1, 2, 3]), plainTextType: Data("first".utf8)],
            ["com.example.b": Data([255, 0])],
        ]
        Paster.write(contents, to: pasteboard)

        let items = pasteboard.pasteboardItems ?? []
        #expect(items.count == 2)
        for (original, restored) in zip(contents, items) {
            for (type, data) in original {
                #expect(restored.data(forType: NSPasteboard.PasteboardType(type)) == data)
            }
        }
    }
}

struct InputTests {
    let all = NSEvent.ModifierFlags([.command, .shift, .option, .control])

    @Test("INV-Input-1: only ⌘⇧⌥⌃ are kept, mapped to the matching Carbon bits")
    func modifiers() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_C),
                             modifiers: all.union([.capsLock, .function, .numericPad]).rawValue)
        #expect(combo.flags == all)
        #expect(combo.carbonModifiers == UInt32(cmdKey | shiftKey | optionKey | controlKey))

        let commandOnly = KeyCombo(keyCode: UInt32(kVK_ANSI_C), modifiers: NSEvent.ModifierFlags.command.rawValue)
        #expect(commandOnly.carbonModifiers == UInt32(cmdKey))
    }

    @Test("INV-Input-2: modifiers are shown as ⌃⌥⇧⌘ before the key")
    func displayOrder() {
        #expect(KeyCombo(keyCode: UInt32(kVK_Return), modifiers: all.rawValue).displayString == "⌃⌥⇧⌘↩")
        let shiftCommand = NSEvent.ModifierFlags([.shift, .command]).rawValue
        #expect(KeyCombo(keyCode: UInt32(kVK_F5), modifiers: shiftCommand).displayString == "⇧⌘F5")
    }

    @Test("INV-Input-3: special keys have no menu key equivalent",
          arguments: [kVK_Return, kVK_Space, kVK_UpArrow, kVK_Escape, kVK_F5, kVK_Delete])
    func specialKeys(keyCode: Int) {
        #expect(KeyCombo(keyCode: UInt32(keyCode), modifiers: 0).menuKeyEquivalent == nil)
    }
}
