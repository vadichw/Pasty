import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
enum Paster {
    /// Puts a history item back on the pasteboard, either with all original types
    /// (formatting, images, files) or as plain text only.
    static func write(_ contents: ClipContents, item: ClipItem, plainText: Bool,
                      to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()

        if plainText, item.kind == .text {
            let string = contents.lazy
                .compactMap { $0[NSPasteboard.PasteboardType.string.rawValue] }
                .compactMap { String(data: $0, encoding: .utf8) }
                .first ?? item.text
            pasteboard.setString(string, forType: .string)
            return
        }

        write(contents, to: pasteboard)
    }

    /// Writes raw contents with all their original types.
    static func write(_ contents: ClipContents, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        let objects = contents.map { dict -> NSPasteboardItem in
            let pbItem = NSPasteboardItem()
            for (type, data) in dict {
                pbItem.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return pbItem
        }
        pasteboard.writeObjects(objects)
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Simulates ⌘V in the frontmost app. Requires Accessibility permission.
    static func paste() {
        guard hasAccessibility else {
            requestAccessibility()
            return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let vKey = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
