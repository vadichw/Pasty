import AppKit
import Combine

@MainActor
final class PopupModel: ObservableObject {
    let store: HistoryStore

    @Published var query = "" {
        didSet {
            selectedID = nil
            refilter()
        }
    }
    @Published var selectedID: UUID?
    @Published private(set) var visible: [ClipItem] = []
    /// Set only by keyboard navigation, so hovering doesn't make the list jump.
    @Published private(set) var scrollTarget: UUID?
    /// Bumped every time the popup opens to re-focus the search field.
    @Published private(set) var focusToken = 0

    var onSelect: ((ClipItem, NSEvent.ModifierFlags) -> Void)?
    var onOpenSettings: (() -> Void)?

    private var lastKeyboardNavigation = Date.distantPast
    private var cancellable: AnyCancellable?
    private var appIcons: [String: NSImage] = [:]

    init(store: HistoryStore) {
        self.store = store
        cancellable = store.$items.sink { [weak self] items in
            MainActor.assumeIsolated { self?.refilter(items) }
        }
    }

    var selected: ClipItem? { visible.first { $0.id == selectedID } }

    func reset() {
        query = ""
        selectedID = visible.first?.id
        scrollTarget = selectedID
        focusToken += 1
    }

    func refilter(_ items: [ClipItem]? = nil) {
        let all = items ?? store.items
        let tokens = query.split(whereSeparator: \.isWhitespace)
        visible = tokens.isEmpty ? all : all.filter { item in
            tokens.allSatisfy { item.text.localizedCaseInsensitiveContains($0) }
        }
        if selectedID == nil || !visible.contains(where: { $0.id == selectedID }) {
            selectedID = visible.first?.id
        }
    }

    func move(_ delta: Int) {
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(current + delta, 0), visible.count - 1)
        selectedID = visible[next].id
        scrollTarget = selectedID
        lastKeyboardNavigation = Date()
    }

    func moveToEdge(top: Bool) {
        move(top ? -visible.count : visible.count)
    }

    func hover(_ item: ClipItem) {
        guard Date().timeIntervalSince(lastKeyboardNavigation) > 0.4 else { return }
        selectedID = item.id
    }

    func select(_ item: ClipItem? = nil, modifiers: NSEvent.ModifierFlags = []) {
        guard let item = item ?? selected else { return }
        onSelect?(item, modifiers)
    }

    func select(at index: Int, modifiers: NSEvent.ModifierFlags) {
        guard visible.indices.contains(index) else { return }
        select(visible[index], modifiers: modifiers)
    }

    func togglePin(_ item: ClipItem? = nil) {
        guard let item = item ?? selected else { return }
        store.togglePin(item)
        selectedID = item.id
        scrollTarget = item.id
    }

    func remove(_ item: ClipItem? = nil) {
        guard let item = item ?? selected,
              let index = visible.firstIndex(where: { $0.id == item.id }) else { return }
        let neighbour = visible.indices.contains(index + 1) ? visible[index + 1]
            : (index > 0 ? visible[index - 1] : nil)
        let wasSelected = item.id == selectedID
        store.remove(item)
        if wasSelected { selectedID = neighbour?.id }
    }

    func clear() {
        store.clear(keepPinned: true)
    }

    /// App icons come with every resolution up to 1024 px; keep only a 36 px bitmap
    /// (18 pt @2x), which is all the list ever draws.
    private static func smallIcon(_ icon: NSImage) -> NSImage {
        let pixels = 36
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { return icon }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        rep.size = NSSize(width: 18, height: 18) // 2x density
        let small = NSImage(size: rep.size)
        small.addRepresentation(rep)
        return small
    }

    func appIcon(for item: ClipItem) -> NSImage? {
        guard let bundleID = item.appBundleID else { return nil }
        if let icon = appIcons[bundleID] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = Self.smallIcon(NSWorkspace.shared.icon(forFile: url.path))
        appIcons[bundleID] = icon
        return icon
    }
}
