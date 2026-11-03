import Foundation

extension Notification.Name {
    static let hotKeyChanged = Notification.Name("Pasty.hotKeyChanged")
    static let hotKeyRecordingStarted = Notification.Name("Pasty.hotKeyRecordingStarted")
    static let screenshotSettingsChanged = Notification.Name("Pasty.screenshotSettingsChanged")
}

enum PopupPosition: String, CaseIterable {
    case cursor, center, statusItem
}

/// Actions that can be bound to a global keyboard shortcut.
enum HotKeyAction: String, CaseIterable, Identifiable {
    case openHistory, pasteLastPlain, togglePause, openSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openHistory: "Open history"
        case .pasteLastPlain: "Paste last item as plain text"
        case .togglePause: "Pause / resume recording"
        case .openSettings: "Open settings"
        }
    }

    var defaultCombo: KeyCombo? {
        self == .openHistory ? .default : nil
    }

    /// `openHistory` keeps the original key so existing settings carry over.
    fileprivate var defaultsKey: String {
        self == .openHistory ? "hotKey" : "hotKey.\(rawValue)"
    }
}

enum Prefs {
    enum Key {
        static let historyLimit = "historyLimit"
        static let pasteAutomatically = "pasteAutomatically"
        static let pastePlainByDefault = "pastePlainByDefault"
        static let saveImages = "saveImages"
        static let popupPosition = "popupPosition"
        static let paused = "paused"
        static let ignoredApps = "ignoredApps"
        static let watchScreenshots = "watchScreenshots"
        static let copyScreenshotsToClipboard = "copyScreenshotsToClipboard"
        static let screenshotFolder = "screenshotFolder"
    }

    /// Replaced with a scratch suite in tests.
    static var defaults = UserDefaults.standard

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.historyLimit: 200,
            Key.pasteAutomatically: false,
            Key.pastePlainByDefault: false,
            Key.saveImages: true,
            Key.popupPosition: PopupPosition.cursor.rawValue,
            Key.paused: false,
            Key.ignoredApps: [String](),
            Key.watchScreenshots: true,
            Key.copyScreenshotsToClipboard: true,
            Key.screenshotFolder: "",
        ])
    }

    static var historyLimit: Int { max(10, defaults.integer(forKey: Key.historyLimit)) }
    static var pasteAutomatically: Bool { defaults.bool(forKey: Key.pasteAutomatically) }
    static var pastePlainByDefault: Bool { defaults.bool(forKey: Key.pastePlainByDefault) }
    static var saveImages: Bool { defaults.bool(forKey: Key.saveImages) }
    static var watchScreenshots: Bool { defaults.bool(forKey: Key.watchScreenshots) }
    static var copyScreenshotsToClipboard: Bool { defaults.bool(forKey: Key.copyScreenshotsToClipboard) }

    /// Custom folder to watch for screenshots; `nil` means the system screenshot location.
    static var screenshotFolder: String? {
        get { defaults.string(forKey: Key.screenshotFolder).flatMap { $0.isEmpty ? nil : $0 } }
        set { defaults.set(newValue ?? "", forKey: Key.screenshotFolder) }
    }

    static var popupPosition: PopupPosition {
        PopupPosition(rawValue: defaults.string(forKey: Key.popupPosition) ?? "") ?? .cursor
    }

    static var paused: Bool {
        get { defaults.bool(forKey: Key.paused) }
        set { defaults.set(newValue, forKey: Key.paused) }
    }

    static var ignoredApps: [String] {
        get { defaults.stringArray(forKey: Key.ignoredApps) ?? [] }
        set { defaults.set(newValue, forKey: Key.ignoredApps) }
    }

    /// Returns the shortcut for an action, or `nil` if it has none.
    /// A missing value means "use the default"; empty data means "explicitly removed".
    static func hotKey(for action: HotKeyAction) -> KeyCombo? {
        guard let data = defaults.data(forKey: action.defaultsKey) else { return action.defaultCombo }
        return try? JSONDecoder().decode(KeyCombo.self, from: data)
    }

    /// Assigns a shortcut, removing it from any other action that used the same combo.
    static func setHotKey(_ combo: KeyCombo?, for action: HotKeyAction) {
        if let combo {
            for other in HotKeyAction.allCases where other != action && hotKey(for: other) == combo {
                defaults.set(Data(), forKey: other.defaultsKey)
            }
        }
        let data = combo.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        defaults.set(data, forKey: action.defaultsKey)
    }

    static func resetHotKey(for action: HotKeyAction) {
        if let combo = action.defaultCombo {
            setHotKey(combo, for: action)
        }
        defaults.removeObject(forKey: action.defaultsKey)
    }
}
