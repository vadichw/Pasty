import AppKit
import Carbon.HIToolbox
import Testing
@testable import PastyCore

extension UsesPrefs {
    @MainActor
    struct SettingsTests {
        init() { useScratchDefaults() }

        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: NSEvent.ModifierFlags([.command, .option]).rawValue)

        @Test("INV-Settings-1: assigning a combo takes it away from the action that had it")
        func comboIsUnique() {
            Prefs.setHotKey(combo, for: .togglePause)
            Prefs.setHotKey(combo, for: .openSettings)
            #expect(Prefs.hotKey(for: .openSettings) == combo)
            #expect(Prefs.hotKey(for: .togglePause) == nil)

            Prefs.setHotKey(.default, for: .pasteLastPlain)
            #expect(Prefs.hotKey(for: .openHistory) == nil)
        }

        @Test("INV-Settings-2: nothing stored means the default; removed means none")
        func defaultsAndRemoval() {
            #expect(Prefs.hotKey(for: .openHistory) == .default)
            #expect(Prefs.hotKey(for: .togglePause) == nil)
            Prefs.setHotKey(nil, for: .openHistory)
            #expect(Prefs.hotKey(for: .openHistory) == nil)
        }

        @Test("INV-Settings-3: reset restores the default and takes it from any other action")
        func reset() {
            Prefs.setHotKey(.default, for: .togglePause)
            #expect(Prefs.hotKey(for: .openHistory) == nil)
            Prefs.resetHotKey(for: .openHistory)
            #expect(Prefs.hotKey(for: .openHistory) == .default)
            #expect(Prefs.hotKey(for: .togglePause) == nil)
        }

        @Test("INV-Settings-5: automatic pasting is off by default")
        func autoPasteOffByDefault() {
            #expect(Prefs.pasteAutomatically == false)
        }

        @Test("INV-Settings-4: the history limit is never below 10", arguments: [(0, 10), (3, 10), (10, 10), (500, 500)])
        func historyLimitFloor(stored: Int, expected: Int) {
            Prefs.defaults.set(stored, forKey: Prefs.Key.historyLimit)
            #expect(Prefs.historyLimit == expected)
        }
    }
}
