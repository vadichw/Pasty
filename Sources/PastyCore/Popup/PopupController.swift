import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless panel that can take keyboard focus without activating the app, so the
/// app the user was typing in stays frontmost and receives the simulated ⌘V.
final class PopupPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        minSize = NSSize(width: 380, height: 300)
        setFrameAutosaveName("PastyPopup")

        let radius: CGFloat = 12
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.state = .active
        effect.blendingMode = .behindWindow
        let mask = NSImage(size: NSSize(width: radius * 2 + 1, height: radius * 2 + 1), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        effect.maskImage = mask
        contentView = effect
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

enum PopupAnchor {
    case cursor
    case center
    case statusItem(NSStatusBarButton)
}

@MainActor
final class PopupController: NSObject, NSWindowDelegate {
    let model: PopupModel
    private let panel = PopupPanel()
    private let preview = MediaPreview()
    private var keyMonitor: Any?
    private var lastHidden = Date.distantPast

    var onSelect: ((ClipItem, _ plainText: Bool, _ paste: Bool) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onHide: (() -> Void)?

    init(store: HistoryStore) {
        model = PopupModel(store: store)
        super.init()

        let host = NSHostingView(rootView: HistoryView(model: model))
        host.frame = panel.contentView!.bounds
        host.autoresizingMask = [.width, .height]
        panel.contentView!.addSubview(host)
        panel.delegate = self

        model.onSelect = { [weak self] item, modifiers in self?.choose(item, modifiers: modifiers) }
        model.onOpenSettings = { [weak self] in
            self?.hide()
            self?.onOpenSettings?()
        }
        model.onPreview = { [weak self] item in self?.showPreview(item) }
        preview.onClick = { [weak self] in self?.model.closePreview() }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle(anchor: PopupAnchor) {
        if panel.isVisible {
            hide()
        } else if Date().timeIntervalSince(lastHidden) > 0.25 {
            // Clicking the status item while the popup is open first resigns key
            // (hiding it) and then fires the click — don't reopen in that case.
            show(anchor: anchor)
        }
    }

    func show(anchor: PopupAnchor) {
        model.reset()
        position(anchor: anchor)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        installKeyMonitor()
    }

    func hide() {
        guard panel.isVisible else { return }
        model.closePreview()
        panel.orderOut(nil)
        lastHidden = Date()
        removeKeyMonitor()
        onHide?()
    }

    /// Releases the panel and its SwiftUI view tree.
    func tearDown() {
        removeKeyMonitor()
        preview.tearDown()
        panel.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
        model.onSelect = nil
        model.onOpenSettings = nil
        model.onPreview = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func choose(_ item: ClipItem, modifiers: NSEvent.ModifierFlags) {
        hide()
        let plain = Prefs.pastePlainByDefault != modifiers.contains(.shift)
        let paste = Prefs.pasteAutomatically != modifiers.contains(.option)
        onSelect?(item, plain, paste)
    }

    private func showPreview(_ item: ClipItem?) {
        guard let item else { return preview.hide() }
        if item.kind == .video {
            // Recordings are kept as a link to the file, so there is nothing to show once it's gone.
            guard let path = item.filePath, FileManager.default.fileExists(atPath: path) else {
                NSSound.beep()
                return model.closePreview()
            }
            return preview.showVideo(URL(fileURLWithPath: path), beside: panel.frame)
        }
        guard let image = model.store.fullImage(for: item) else {
            NSSound.beep() // the source file and stored data are both unreadable
            return model.closePreview()
        }
        preview.show(image, beside: panel.frame)
    }

    // MARK: - Positioning

    private func position(anchor: PopupAnchor) {
        let size = panel.frame.size
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        var origin: NSPoint
        switch anchor {
        case .cursor:
            origin = NSPoint(x: mouse.x, y: mouse.y - size.height)
        case .center:
            origin = NSPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2 + visibleFrame.height / 8)
        case .statusItem(let button):
            if let window = button.window {
                let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
                origin = NSPoint(x: frame.minX, y: frame.minY - size.height - 4)
            } else {
                origin = NSPoint(x: mouse.x, y: mouse.y - size.height)
            }
        }
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - size.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        panel.setFrameOrigin(origin)
    }

    // MARK: - Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private static let digitKeys = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    /// Uses key codes rather than characters so shortcuts work in any keyboard layout.
    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)

        switch keyCode {
        case kVK_Escape:
            if model.previewID != nil {
                model.closePreview()
            } else if model.query.isEmpty {
                hide()
            } else {
                model.query = ""
            }
            return true
        case kVK_UpArrow:
            modifiers.contains(.command) ? model.moveToEdge(top: true) : model.move(-1)
            return true
        case kVK_DownArrow:
            modifiers.contains(.command) ? model.moveToEdge(top: false) : model.move(1)
            return true
        case kVK_PageUp:
            model.move(-8)
            return true
        case kVK_PageDown:
            model.move(8)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.select(modifiers: modifiers)
            return true
        case kVK_Delete where modifiers.contains(.option):
            model.remove()
            return true
        default:
            break
        }

        if modifiers.contains(.control) {
            switch keyCode {
            case kVK_ANSI_N, kVK_ANSI_J: model.move(1); return true
            case kVK_ANSI_P, kVK_ANSI_K: model.move(-1); return true
            default: break
            }
        }

        guard modifiers.contains(.command) else { return false }
        if let index = Self.digitKeys.firstIndex(of: keyCode) {
            model.select(at: index, modifiers: modifiers)
            return true
        }
        switch keyCode {
        case kVK_ANSI_P:
            model.togglePin()
            return true
        case kVK_ANSI_Y:
            model.togglePreview()
            return true
        case kVK_ANSI_Comma:
            model.onOpenSettings?()
            return true
        case kVK_ANSI_W:
            hide()
            return true
        case kVK_ANSI_Q:
            NSApp.terminate(nil)
            return true
        default:
            return false
        }
    }
}
