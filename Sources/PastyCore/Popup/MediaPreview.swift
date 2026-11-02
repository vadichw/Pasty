import AppKit
import AVKit

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

/// Player controls must react to the first click: the preview window is never key.
private final class FirstClickPlayerView: AVPlayerView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Shows a history image or video at full size next to the popup. Click an image to close it;
/// a video plays right away, with sound and the usual controls.
@MainActor
final class MediaPreview {
    var onClick: (() -> Void)?

    private var panel: PreviewPanel?
    private var imageView: ClickableImageView?
    private var playerView: FirstClickPlayerView?
    /// Bumped on every show/hide, so a video whose size arrives late doesn't reopen a closed preview.
    private var generation = 0

    private static let gap: CGFloat = 8
    /// Below this width a side of the screen is too narrow; the preview goes on top of the popup.
    private static let minSideWidth: CGFloat = 240
    /// Used when a video's size can't be read.
    private static let fallbackVideoSize = NSSize(width: 1280, height: 720)

    func show(_ image: NSImage, beside anchor: NSRect) {
        generation += 1
        guard let screen = Self.screen(for: anchor) else { return }
        stopVideo()
        let (panel, imageView, _) = makePanelIfNeeded()
        imageView.image = image
        imageView.isHidden = false
        var size = image.size
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        present(panel, pixelSize: size, beside: anchor, on: screen)
    }

    /// Reads the video's size in the background (the window is sized to fit it), then plays it.
    func showVideo(_ url: URL, beside anchor: NSRect) {
        generation += 1
        let current = generation
        Task { [weak self] in
            let size = await MediaFile.videoSize(url: url)
            self?.play(url, pixelSize: size ?? Self.fallbackVideoSize, beside: anchor, generation: current)
        }
    }

    /// Shows the player and starts the video — unless the preview was closed or switched meanwhile.
    private func play(_ url: URL, pixelSize: NSSize, beside anchor: NSRect, generation current: Int) {
        guard current == generation, let screen = Self.screen(for: anchor) else { return }
        let (panel, imageView, playerView) = makePanelIfNeeded()
        imageView.image = nil
        imageView.isHidden = true
        playerView.player?.pause()
        playerView.player = AVPlayer(url: url)
        playerView.isHidden = false
        present(panel, pixelSize: pixelSize, beside: anchor, on: screen)
        playerView.player?.play()
    }

    func hide() {
        generation += 1
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        imageView?.image = nil
        stopVideo()
        Memory.relieve()
    }

    func tearDown() {
        hide()
        panel = nil
        imageView = nil
        playerView = nil
    }

    private func stopVideo() {
        playerView?.player?.pause()
        playerView?.player = nil
        playerView?.isHidden = true
    }

    private static func screen(for anchor: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
    }

    /// Natural size in points: pixels / screen scale, so a Retina screenshot or recording shows 1:1.
    private func present(_ panel: PreviewPanel, pixelSize: NSSize, beside anchor: NSRect, on screen: NSScreen) {
        let size = NSSize(width: pixelSize.width / screen.backingScaleFactor,
                          height: pixelSize.height / screen.backingScaleFactor)
        panel.setFrame(Self.frame(size: size, beside: anchor, in: screen.visibleFrame), display: true)
        panel.orderFront(nil)
        panel.invalidateShadow()
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

    private func makePanelIfNeeded() -> (PreviewPanel, ClickableImageView, FirstClickPlayerView) {
        if let panel, let imageView, let playerView { return (panel, imageView, playerView) }
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

        let playerView = FirstClickPlayerView()
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = false
        playerView.autoresizingMask = [.width, .height]
        playerView.isHidden = true

        container.addSubview(imageView)
        container.addSubview(playerView)
        panel.contentView = container
        imageView.frame = container.bounds
        playerView.frame = container.bounds

        self.panel = panel
        self.imageView = imageView
        self.playerView = playerView
        return (panel, imageView, playerView)
    }
}
