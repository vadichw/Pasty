import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: PopupModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if model.visible.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .frame(minWidth: 380, minHeight: 300)
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { searchFocused = true }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 28))
            Text(model.query.isEmpty ? "History is empty.\nCopy something." : "No matches")
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(model.visible) { item in
                        ClipRow(
                            item: item,
                            isSelected: item.id == model.selectedID,
                            appIcon: model.appIcon(for: item),
                            thumbnail: item.kind == .image || item.kind == .video ? model.store.thumbnail(for: item) : nil,
                            isPreviewed: item.id == model.previewID,
                            onPreview: PopupModel.canPreview(item) ? { model.togglePreview(item) } : nil,
                            onTogglePin: { model.togglePin(item) },
                            onDelete: { model.remove(item) }
                        )
                        .id(item.id)
                        .onHover { if $0 { model.hover(item) } }
                        .onTapGesture { model.select(item, modifiers: NSEvent.modifierFlags) }
                        .contextMenu { contextMenu(for: item) }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                proxy.scrollTo(target)
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        Button("Paste") { model.select(item) }
        if item.kind == .text {
            Button("Paste as Plain Text") { model.select(item, modifiers: .shift) }
        }
        Button("Copy Only") { model.select(item, modifiers: .option) }
        Divider()
        if PopupModel.canPreview(item) {
            Button(item.id == model.previewID ? "Close Preview" : "Preview") { model.togglePreview(item) }
        }
        if !item.fileURLs.isEmpty {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(item.fileURLs) }
        }
        Button(item.pinned ? "Unpin" : "Pin") { model.togglePin(item) }
        Button("Delete", role: .destructive) { model.remove(item) }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            let usage = model.store.usage
            UsageIndicator(used: usage.used, limit: usage.limit)
            if !model.store.items.isEmpty {
                Text(ByteSize.format(Int64(model.store.totalBytes)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .help("Total size of all copied items")
            }
            if !model.query.isEmpty {
                Text("\(model.visible.count) found")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.clear() } label: { Image(systemName: "trash") }
                .help("Delete all unpinned items")
            Button { model.onOpenSettings?() } label: { Image(systemName: "gearshape") }
                .help("Settings (⌘,)")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit Pasty")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

}

/// "20/2000" with a bar that turns orange and then red as the history fills up.
private struct UsageIndicator: View {
    let used: Int
    let limit: Int

    @Environment(\.colorScheme) private var colorScheme

    private var level: UsageLevel { UsageLevel.of(used: used, limit: limit) }

    /// The bright system colors are too pale on the light translucent panel.
    private var color: Color {
        switch (level, colorScheme == .light) {
        case (.low, false): .green
        case (.medium, false): .orange
        case (.high, false): .red
        case (.low, true): Color(red: 21 / 255, green: 101 / 255, blue: 52 / 255)
        case (.medium, true): Color(red: 146 / 255, green: 64 / 255, blue: 14 / 255)
        case (.high, true): Color(red: 153 / 255, green: 27 / 255, blue: 27 / 255)
        }
    }

    var body: some View {
        let fraction = limit > 0 ? min(1, Double(used) / Double(limit)) : 1
        HStack(spacing: 6) {
            Capsule()
                .fill(.primary.opacity(0.2))
                .frame(width: 44, height: 5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: max(5, 44 * fraction), height: 5)
                }
            Text("\(used)/\(limit)")
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .help("\(used) of \(limit) items; when full, the oldest unpinned items are deleted. Pinned items don't count. Change the limit in Settings.")
    }
}

struct ClipRow: View {
    let item: ClipItem
    let isSelected: Bool
    let appIcon: NSImage?
    let thumbnail: NSImage?
    let isPreviewed: Bool
    /// Set for images only; shows the eye button.
    let onPreview: (() -> Void)?
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 18, height: 18)

            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 120, maxHeight: 48, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay {
                        if item.kind == .video {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white, .black.opacity(0.45))
                        }
                    }
                Text(item.text)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .opacity(0.7)
            } else {
                Text(item.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            if let byteCount = item.byteCount {
                Text(ByteSize.format(Int64(byteCount)))
                    .font(.system(size: 11).monospacedDigit())
                    .opacity(0.55)
                    .help("Size of the copied data, all formats included")
            }
            if let onPreview {
                Button(action: onPreview) {
                    Image(systemName: isPreviewed ? "eye.fill" : "eye")
                        .font(.system(size: 11))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isSelected || isPreviewed ? 0.9 : 0.4)
                .help("Preview (⌘Y)")
            }
            Button(action: onTogglePin) {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .foregroundStyle(item.pinned && !isSelected ? AnyShapeStyle(.orange) : AnyShapeStyle(.foreground))
            }
            .buttonStyle(.plain)
            .opacity(isSelected || item.pinned ? 0.9 : 0.4)
            .help(item.pinned ? "Unpin (⌘P)" : "Pin (⌘P)")
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isSelected ? 0.9 : 0.4)
            .help("Delete (⌥⌫)")
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
        .help(String(item.text.prefix(1500)))
    }

    @ViewBuilder
    private var icon: some View {
        if let appIcon {
            Image(nsImage: appIcon).resizable()
        } else {
            Image(systemName: symbolName)
                .opacity(0.7)
        }
    }

    private var symbolName: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .image: "photo"
        case .video: "film"
        case .files: "doc"
        }
    }
}
