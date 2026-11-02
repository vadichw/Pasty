import Foundation

/// How code touches the world outside its own memory. Every category used in a README
/// `Side effects:` bullet must be one of these; docs/DOC_FORMAT.md explains each one.
enum Effect: String, CaseIterable, Codable, Comparable {
    case pasteboardRead = "pasteboard-read"
    case pasteboardWrite = "pasteboard-write"
    case diskRead = "disk-read"
    case diskWrite = "disk-write"
    case defaultsRead = "defaults-read"
    case defaultsWrite = "defaults-write"
    case keystroke
    case hotkey
    case folderWatch = "folder-watch"
    case loginItem = "login-item"
    case accessibility
    case appsRead = "apps-read"
    case openExternal = "open-external"
    case inputSource = "input-source"
    case schedule
    case notifyPost = "notify-post"
    case notifyObserve = "notify-observe"
    case eventMonitor = "event-monitor"
    case window
    case terminate
    case sound
    case mediaPlayback = "media-playback"
    case memory
    case log

    static func < (a: Effect, b: Effect) -> Bool { a.rawValue < b.rawValue }
}

/// One syntactic pattern that counts as a side effect.
struct EffectRule {
    enum Kind {
        /// `receiver.name` — a call or a property access.
        case member
        /// `name(...)` — a free function.
        case function
        /// `Name(...)` — an initializer.
        case initializer
        /// `@Name` on a declaration.
        case attribute
    }

    let kind: Kind
    let name: String
    /// Label of the first argument, when the name alone is ambiguous (`write(to:)`).
    var firstLabel: String? = nil
    /// Regex the receiver expression must match (`defaults.set`, not `cache.set`).
    var receiver: String? = nil
    let effects: [Effect]

    init(_ kind: Kind, _ name: String, firstLabel: String? = nil, receiver: String? = nil, _ effects: Effect...) {
        self.kind = kind
        self.name = name
        self.firstLabel = firstLabel
        self.receiver = receiver
        self.effects = effects
    }

    func matches(kind: Kind, name: String, labels: [String]?, receiver: String?) -> Bool {
        guard kind == self.kind, name == self.name else { return false }
        if let firstLabel {
            guard let labels, labels.first == firstLabel else { return false }
        }
        if let pattern = self.receiver {
            guard let receiver, receiver.range(of: pattern, options: .regularExpression) != nil else { return false }
        }
        return true
    }
}

enum EffectRules {
    static let defaultsReceiver = #"(^|\.)defaults$|UserDefaults"#

    static let all: [EffectRule] = [
        // Pasteboard
        .init(.member, "changeCount", .pasteboardRead),
        .init(.member, "pasteboardItems", .pasteboardRead),
        .init(.member, "readObjects", .pasteboardRead),
        .init(.member, "data", firstLabel: "forType", .pasteboardRead),
        .init(.member, "string", firstLabel: "forType", .pasteboardRead),
        .init(.member, "clearContents", .pasteboardWrite),
        .init(.member, "writeObjects", .pasteboardWrite),
        .init(.member, "setString", .pasteboardWrite),

        // Files
        .init(.initializer, "Data", firstLabel: "contentsOf", .diskRead),
        .init(.initializer, "NSImage", firstLabel: "contentsOf", .diskRead),
        .init(.initializer, "NSImage", firstLabel: "contentsOfFile", .diskRead),
        .init(.initializer, "AVURLAsset", .diskRead),
        .init(.initializer, "AVPlayer", firstLabel: "url", .diskRead),
        .init(.function, "CGImageSourceCreateWithURL", .diskRead),
        .init(.member, "fileExists", .diskRead),
        .init(.member, "contentsOfDirectory", .diskRead),
        .init(.member, "attributesOfItem", .diskRead),
        .init(.member, "resourceValues", firstLabel: "forKeys", .diskRead),
        .init(.member, "write", firstLabel: "to", .diskWrite),
        .init(.member, "createDirectory", .diskWrite),
        .init(.member, "moveItem", .diskWrite),
        .init(.member, "removeItem", .diskWrite),

        // UserDefaults
        .init(.member, "bool", receiver: defaultsReceiver, .defaultsRead),
        .init(.member, "integer", receiver: defaultsReceiver, .defaultsRead),
        .init(.member, "string", firstLabel: "forKey", receiver: defaultsReceiver, .defaultsRead),
        .init(.member, "data", firstLabel: "forKey", receiver: defaultsReceiver, .defaultsRead),
        .init(.member, "stringArray", receiver: defaultsReceiver, .defaultsRead),
        .init(.member, "object", firstLabel: "forKey", receiver: defaultsReceiver, .defaultsRead),
        .init(.initializer, "UserDefaults", firstLabel: "suiteName", .defaultsRead),
        .init(.member, "set", receiver: defaultsReceiver, .defaultsWrite),
        .init(.member, "removeObject", firstLabel: "forKey", receiver: defaultsReceiver, .defaultsWrite),
        .init(.member, "register", firstLabel: "defaults", receiver: defaultsReceiver, .defaultsWrite),
        .init(.attribute, "AppStorage", .defaultsRead, .defaultsWrite),
        .init(.member, "setFrameAutosaveName", .defaultsWrite), // AppKit keeps the frame in UserDefaults

        // System
        .init(.member, "post", firstLabel: "tap", .keystroke),
        .init(.function, "RegisterEventHotKey", .hotkey),
        .init(.function, "UnregisterEventHotKey", .hotkey),
        .init(.function, "InstallEventHandler", .hotkey),
        .init(.member, "makeFileSystemObjectSource", .folderWatch),
        .init(.member, "cancel", receiver: "(?i)source", .folderWatch),
        .init(.member, "register", receiver: "SMAppService", .loginItem),
        .init(.member, "unregister", receiver: "SMAppService", .loginItem),
        .init(.member, "status", receiver: "SMAppService", .loginItem),
        .init(.function, "AXIsProcessTrusted", .accessibility),
        .init(.function, "AXIsProcessTrustedWithOptions", .accessibility),
        .init(.member, "frontmostApplication", .appsRead),
        .init(.member, "runningApplications", .appsRead),
        .init(.member, "urlForApplication", .appsRead),
        .init(.member, "icon", firstLabel: "forFile", .appsRead),
        .init(.member, "open", receiver: "NSWorkspace", .openExternal),
        .init(.member, "activateFileViewerSelecting", .openExternal),
        .init(.function, "TISCopyCurrentASCIICapableKeyboardLayoutInputSource", .inputSource),

        // Deferred work
        .init(.initializer, "Timer", .schedule),
        .init(.member, "scheduledTimer", .schedule),
        .init(.member, "publish", receiver: "Timer", .schedule),
        .init(.member, "asyncAfter", .schedule),
        .init(.member, "async", receiver: "DispatchQueue", .schedule),
        .init(.initializer, "Task", .schedule),

        // Notifications and events
        .init(.member, "post", firstLabel: "name", .notifyPost),
        .init(.member, "addObserver", firstLabel: "forName", .notifyObserve),
        .init(.member, "publisher", firstLabel: "for", .notifyObserve),
        .init(.member, "addLocalMonitorForEvents", .eventMonitor),
        .init(.member, "removeMonitor", .eventMonitor),

        // UI and process
        .init(.member, "makeKeyAndOrderFront", .window),
        .init(.member, "orderFront", .window),
        .init(.member, "orderOut", .window),
        .init(.member, "statusItem", firstLabel: "withLength", .window),
        .init(.member, "orderFrontStandardAboutPanel", .window),
        .init(.member, "runModal", .window),
        .init(.member, "performClick", .window), // opens a status item's menu
        .init(.member, "activate", receiver: "NSApp", .window),
        .init(.member, "terminate", receiver: "NSApp", .terminate),
        .init(.member, "beep", .sound),
        .init(.member, "play", receiver: "(?i)player", .mediaPlayback),
        .init(.member, "pause", receiver: "(?i)player", .mediaPlayback),
        .init(.function, "malloc_zone_pressure_relief", .memory),
        .init(.function, "NSLog", .log),
    ]

    static func effects(kind: EffectRule.Kind, name: String, labels: [String]?, receiver: String?) -> [Effect] {
        all.filter { $0.matches(kind: kind, name: name, labels: labels, receiver: receiver) }
            .flatMap(\.effects)
    }
}
