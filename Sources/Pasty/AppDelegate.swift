import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
enum PastyMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = MainActor.assumeIsolated { AppDelegate() }
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let store = HistoryStore()
    private lazy var monitor = ClipboardMonitor(store: store)
    /// Created on demand and released shortly after it closes, so the SwiftUI view tree
    /// doesn't occupy memory while the app sits idle in the menu bar.
    private var popup: PopupController?
    private var popupTeardown: DispatchWorkItem?
    private var statusItem: NSStatusItem!
    private let screenshotWatcher = ScreenshotWatcher()
    private var hotKeys: [HotKey] = []
    private var settingsWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()

        setupStatusItem()
        monitor.start()
        registerHotKeys()

        screenshotWatcher.onCapture = { [weak self] url in self?.recordScreenCapture(url) }
        screenshotWatcher.restart()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .hotKeyChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.registerHotKeys() }
        })
        observers.append(center.addObserver(forName: .hotKeyRecordingStarted, object: nil, queue: .main) { [weak self] _ in
            // Release all shortcuts so the recorder can capture any combo.
            MainActor.assumeIsolated { self?.hotKeys = [] }
        })
        observers.append(center.addObserver(forName: .screenshotSettingsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenshotWatcher.restart() }
        })

    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    // MARK: - Actions

    private func use(_ item: ClipItem, plainText: Bool, paste: Bool) {
        guard let contents = store.contents(for: item) else {
            store.remove(item)
            return
        }
        if item.kind != .text, !item.fileURLs.isEmpty,
           !item.fileURLs.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) {
            NSSound.beep() // the file was moved or deleted
            return
        }
        Paster.write(contents, item: item, plainText: plainText)
        monitor.skipCurrentChange()
        store.touch(item)
        if paste {
            // Give the previous app's window a moment to regain keyboard focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { Paster.paste() }
        }
    }

    /// Screenshots get both the image data (pastes as a picture) and the file URL
    /// (pastes as a file in Finder, Mail, chats); recordings only the file URL.
    private func recordScreenCapture(_ url: URL) {
        guard !Prefs.paused else { return }
        var item: [String: Data] = [NSPasteboard.PasteboardType.fileURL.rawValue: Data(url.absoluteString.utf8)]
        if MediaFile.kind(of: url) == .image,
           let type = UTType(filenameExtension: url.pathExtension.lowercased()),
           let data = try? Data(contentsOf: url), data.count <= 50 * 1024 * 1024 {
            item[type.identifier] = data
        }
        let contents = [item]
        if Prefs.copyScreenshotsToClipboard {
            Paster.write(contents)
            monitor.skipCurrentChange()
        }
        monitor.record(contents: contents, fileURLs: [url], string: nil, imageData: nil,
                       appBundleID: "com.apple.screenshot.launcher")
    }

    private func registerHotKeys() {
        hotKeys = []
        for action in HotKeyAction.allCases {
            guard let combo = Prefs.hotKey(for: action) else { continue }
            let hotKey = HotKey(combo: combo) { [weak self] in
                MainActor.assumeIsolated { self?.perform(action) }
            }
            if let hotKey {
                hotKeys.append(hotKey)
            } else {
                NSLog("Pasty: failed to register \(combo.displayString) for \(action.rawValue)")
            }
        }
        let open = Prefs.hotKey(for: .openHistory)
        statusItem?.button?.toolTip = open.map { "Pasty — \($0.displayString)" } ?? "Pasty"
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .openHistory:
            togglePopupFromHotKey()
        case .pasteLastPlain:
            if let item = store.items.max(by: { $0.lastCopied < $1.lastCopied }) {
                use(item, plainText: true, paste: true)
            }
        case .togglePause:
            togglePause()
        case .openSettings:
            openSettings()
        }
    }

    private func activePopup() -> PopupController {
        popupTeardown?.cancel()
        if let popup { return popup }
        let popup = PopupController(store: store)
        popup.onSelect = { [weak self] item, plain, paste in self?.use(item, plainText: plain, paste: paste) }
        popup.onOpenSettings = { [weak self] in self?.openSettings() }
        popup.onHide = { [weak self] in self?.schedulePopupTeardown() }
        self.popup = popup
        return popup
    }

    /// Keeps the popup around briefly for quick reopening, then frees it.
    private func schedulePopupTeardown() {
        popupTeardown?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let popup = self.popup, !popup.isVisible else { return }
            popup.tearDown()
            self.popup = nil
            self.store.purgeCaches()
            Memory.relieve()
        }
        popupTeardown = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: work)
    }

    private func togglePopupFromHotKey() {
        switch Prefs.popupPosition {
        case .cursor: activePopup().toggle(anchor: .cursor)
        case .center: activePopup().toggle(anchor: .center)
        case .statusItem:
            if let button = statusItem.button {
                activePopup().toggle(anchor: .statusItem(button))
            } else {
                activePopup().toggle(anchor: .cursor)
            }
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        updateStatusIcon()
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func updateStatusIcon() {
        let name = Prefs.paused ? "clipboard" : "doc.on.clipboard"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Pasty")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = Prefs.paused
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
        } else {
            activePopup().toggle(anchor: .statusItem(sender))
        }
    }

    private func showStatusMenu() {
        popup?.hide()
        let menu = NSMenu()

        menu.addItem(menuItem("Open History", #selector(openHistory), hotKey: .openHistory))
        menu.addItem(.separator())

        let pause = menuItem("Pause Recording", #selector(togglePause), hotKey: .togglePause)
        pause.state = Prefs.paused ? .on : .off
        menu.addItem(pause)
        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", #selector(openSettings), hotKey: .openSettings))
        menu.addItem(NSMenuItem(title: "About Pasty", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Pasty", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }

    /// Shows the action's global shortcut next to the menu item.
    private func menuItem(_ title: String, _ selector: Selector, hotKey action: HotKeyAction) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        if let combo = Prefs.hotKey(for: action), let key = combo.menuKeyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = combo.flags
        }
        return item
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    @objc private func openHistory() {
        guard let button = statusItem.button else { return }
        activePopup().show(anchor: .statusItem(button))
    }

    @objc private func togglePause() {
        Prefs.paused.toggle()
        updateStatusIcon()
    }

    @objc private func clearHistory() {
        store.clear(keepPinned: true)
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Clipboard manager for macOS"),
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Free the settings window (and its 1 s permission-check timer) once it's closed.
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        DispatchQueue.main.async { [weak self] in
            self?.settingsWindow = nil
            Memory.relieve()
        }
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(store: store)))
            window.title = "Pasty Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
