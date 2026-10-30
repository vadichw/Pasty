import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: HistoryStore

    @AppStorage(Prefs.Key.historyLimit) private var historyLimit = 200
    @AppStorage(Prefs.Key.pasteAutomatically) private var pasteAutomatically = true
    @AppStorage(Prefs.Key.pastePlainByDefault) private var pastePlainByDefault = false
    @AppStorage(Prefs.Key.saveImages) private var saveImages = true
    @AppStorage(Prefs.Key.popupPosition) private var popupPosition = PopupPosition.cursor.rawValue
    @AppStorage(Prefs.Key.watchScreenshots) private var watchScreenshots = true
    @AppStorage(Prefs.Key.copyScreenshotsToClipboard) private var copyScreenshotsToClipboard = true

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibilityGranted = Paster.hasAccessibility
    @State private var ignoredApps = Prefs.ignoredApps
    @State private var confirmClearAll = false
    @State private var screenshotFolder = ScreenshotWatcher.folder

    private let accessibilityTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                ForEach(HotKeyAction.allCases) { action in
                    LabeledContent(action.title) { HotKeyRecorder(action: action) }
                }
            } header: {
                Text("Global Shortcuts")
            } footer: {
                Text("Work from any app. Click a shortcut and press the new keys; ⎋ cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Picker("Show popup", selection: $popupPosition) {
                    Text("At cursor").tag(PopupPosition.cursor.rawValue)
                    Text("Screen center").tag(PopupPosition.center.rawValue)
                    Text("Below menu bar icon").tag(PopupPosition.statusItem.rawValue)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }

            Section("Pasting") {
                Toggle("Paste automatically after selecting", isOn: $pasteAutomatically)
                Toggle("Always paste without formatting", isOn: $pastePlainByDefault)
                if pasteAutomatically {
                    LabeledContent("Accessibility access") {
                        if accessibilityGranted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Button("Grant…") {
                                Paster.requestAccessibility()
                                Paster.openAccessibilitySettings()
                            }
                        }
                    }
                }
            }

            Section {
                Toggle("Add new screenshots and screen recordings to history", isOn: $watchScreenshots)
                    .onChange(of: watchScreenshots) { notifyScreenshotSettings() }
                Toggle("Also copy them to the clipboard right away", isOn: $copyScreenshotsToClipboard)
                    .disabled(!watchScreenshots)
                LabeledContent("Folder") {
                    HStack {
                        Text((screenshotFolder.path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…", action: chooseScreenshotFolder)
                        if Prefs.screenshotFolder != nil {
                            Button { setScreenshotFolder(nil) } label: { Image(systemName: "arrow.counterclockwise") }
                                .buttonStyle(.borderless)
                                .help("Use the system screenshot folder")
                        }
                    }
                }
                .disabled(!watchScreenshots)
            } header: {
                Text("Screenshots & Screen Recordings")
            } footer: {
                Text("Pasty picks up new images and videos in the folder where macOS saves screenshots (⇧⌘3, ⇧⌘4) and screen recordings (⇧⌘5). Screenshots taken with ⌃ held go to the clipboard directly and are recorded too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                Picker("History size", selection: $historyLimit) {
                    ForEach([50, 100, 200, 500, 1000, 2000], id: \.self) { Text("\($0)").tag($0) }
                }
                .onChange(of: historyLimit) { store.trim() }
                Toggle("Save images", isOn: $saveImages)
                LabeledContent("Items in history: \(store.items.count)") {
                    HStack {
                        Button("Clear") { store.clear(keepPinned: true) }
                            .help("Delete everything except pinned items")
                        Button("Delete All…", role: .destructive) { confirmClearAll = true }
                    }
                }
            }

            Section {
                ForEach(ignoredApps, id: \.self) { bundleID in
                    HStack {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Button {
                            ignoredApps.removeAll { $0 == bundleID }
                            Prefs.ignoredApps = ignoredApps
                        } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                Menu("Add Application") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "?") {
                            guard let id = app.bundleIdentifier else { return }
                            ignoredApps.append(id)
                            Prefs.ignoredApps = ignoredApps
                        }
                    }
                }
            } header: {
                Text("Ignore copies from these apps")
            } footer: {
                Text("Passwords from password managers that mark data as concealed (1Password, Bitwarden, KeePassXC, etc.) are never saved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Keyboard shortcuts in the history popup") {
                ShortcutRow(keys: "↩", action: "Paste selected item")
                ShortcutRow(keys: "⇧↩", action: "Paste without formatting")
                ShortcutRow(keys: "⌥↩", action: pasteAutomatically ? "Copy only" : "Copy and paste")
                ShortcutRow(keys: "⌘1 … ⌘9", action: "Select item by number")
                ShortcutRow(keys: "⌘P", action: "Pin / unpin")
                ShortcutRow(keys: "⌥⌫", action: "Delete item")
                ShortcutRow(keys: "↑ ↓  ⌃N ⌃P", action: "Move through the list")
                ShortcutRow(keys: "⎋", action: "Clear search / close")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 720)
        .onReceive(accessibilityTimer) { _ in accessibilityGranted = Paster.hasAccessibility }
        .confirmationDialog("Delete the entire history, including pinned items?", isPresented: $confirmClearAll) {
            Button("Delete All", role: .destructive) { store.clear(keepPinned: false) }
        }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .filter { !ignoredApps.contains($0.bundleIdentifier!) && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = screenshotFolder
        panel.prompt = "Watch Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setScreenshotFolder(url)
    }

    private func setScreenshotFolder(_ url: URL?) {
        Prefs.screenshotFolder = url?.path
        screenshotFolder = ScreenshotWatcher.folder
        notifyScreenshotSettings()
    }

    private func notifyScreenshotSettings() {
        NotificationCenter.default.post(name: .screenshotSettingsChanged, object: nil)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Pasty: launch at login failed: \(error)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct ShortcutRow: View {
    let keys: String
    let action: String

    var body: some View {
        LabeledContent(action) {
            Text(keys).font(.system(.body, design: .rounded)).foregroundStyle(.secondary)
        }
    }
}

private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 6) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
        }
    }
}

struct HotKeyRecorder: View {
    let action: HotKeyAction

    @State private var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    init(action: HotKeyAction) {
        self.action = action
        _combo = State(initialValue: Prefs.hotKey(for: action))
    }

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19,
    ]

    var body: some View {
        HStack(spacing: 6) {
            Button(recording ? "Press shortcut…" : (combo?.displayString ?? "Record Shortcut")) {
                recording ? stopRecording() : startRecording()
            }
            .frame(minWidth: 150)
            if combo != nil && !recording {
                Button { save(nil) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove shortcut")
            }
            if let defaultCombo = action.defaultCombo, combo != defaultCombo, !recording {
                Button {
                    Prefs.resetHotKey(for: action)
                    combo = Prefs.hotKey(for: action)
                    NotificationCenter.default.post(name: .hotKeyChanged, object: nil)
                } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless)
                    .help("Reset to \(defaultCombo.displayString)")
            }
        }
        .onDisappear { stopRecording() }
        // Another recorder may have taken this combo away.
        .onReceive(NotificationCenter.default.publisher(for: .hotKeyChanged)) { _ in
            if !recording { combo = Prefs.hotKey(for: action) }
        }
    }

    private func startRecording() {
        recording = true
        NotificationCenter.default.post(name: .hotKeyRecordingStarted, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode)
            if keyCode == kVK_Escape {
                stopRecording()
                return nil
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !modifiers.intersection([.command, .option, .control]).isEmpty
                    || Self.functionKeys.contains(keyCode) else {
                NSSound.beep() // require ⌘, ⌥ or ⌃ unless it's a function key
                return nil
            }
            save(KeyCombo(keyCode: UInt32(keyCode), modifiers: modifiers.rawValue))
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.post(name: .hotKeyChanged, object: nil)
    }

    private func save(_ newCombo: KeyCombo?) {
        combo = newCombo
        Prefs.setHotKey(newCombo, for: action)
        NotificationCenter.default.post(name: .hotKeyChanged, object: nil)
    }
}
