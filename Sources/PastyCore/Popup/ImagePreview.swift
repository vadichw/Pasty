import AppKit

/// Panel that never becomes key, so the popup keeps keyboard focus (and stays open)
/// while the preview is shown.
private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ClickableImageView: NSImageView {
    var onClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}

/// Shows a history image at full size next to the popup. Click it to close.
@MainActor
final class ImagePreview {
    var onClick: (() -> Void)?

    private var panel: PreviewPanel?
    private var imageView: ClickableImageView?

    private static let gap: CGFloat = 8
    /// Below this width a side of the screen is too narrow; the preview goes on top of the popup.
    private static let minSideWidth: CGFloat = 240

    func show(_ image: NSImage, beside anchor: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        guard let screen else { return }
        let (panel, imageView) = makePanelIfNeeded()
        imageView.image = image
        panel.setFrame(Self.frame(for: image, beside: anchor, on: screen), display: true)
        panel.orderFront(nil)
        panel.invalidateShadow()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        imageView?.image = nil
        Memory.relieve()
    }

    func tearDown() {
        hide()
        panel = nil
        imageView = nil
    }

    /// Natural size in points: pixels / screen scale, so a Retina screenshot shows 1:1.
    private static func frame(for image: NSImage, beside anchor: NSRect, on screen: NSScreen) -> NSRect {
        var size = image.size
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            size = NSSize(width: CGFloat(rep.pixelsWide) / screen.backingScaleFactor,
                          height: CGFloat(rep.pixelsHigh) / screen.backingScaleFactor)
        }
        return frame(size: size, beside: anchor, in: screen.visibleFrame)
    }

    /// Shrinks `size` to fit beside the popup, on whichever side has more room;
    /// centered on the screen when neither side is wide enough.
    static func frame(size: NSSize, beside anchor: NSRect, in visibleFrame: NSRect) -> NSRect {
        var size = size
        let visible = visibleFrame.insetBy(dx: gap, dy: gap)
        let rightWidth = visible.maxX - anchor.maxX - gap
        let leftWidth = anchor.minX - gap - visible.minX
        let sideWidth = max(rightWidth, leftWidth)
        let area = sideWidth >= minSideWidth
            ? NSSize(width: sideWidth, height: visible.height)
            : visible.size

        let factor = min(1, area.width / max(size.width, 1), area.height / max(size.height, 1))
        size = NSSize(width: (size.width * factor).rounded(), height: (size.height * factor).rounded())

        guard sideWidth >= minSideWidth else {
            return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                          width: size.width, height: size.height)
        }
        let x = rightWidth >= leftWidth ? anchor.maxX + gap : anchor.minX - gap - size.width
        let y = max(min(anchor.maxY, visible.maxY) - size.height, visible.minY)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func makePanelIfNeeded() -> (PreviewPanel, ClickableImageView) {
        if let panel, let imageView { return (panel, imageView) }
        let panel = PreviewPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        let imageView = ClickableImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.toolTip = "Click to close"
        imageView.onClick = { [weak self] in self?.onClick?() }
        container.addSubview(imageView)
        panel.contentView = container
        imageView.frame = container.bounds

        self.panel = panel
        self.imageView = imageView
        return (panel, imageView)
    }
}
