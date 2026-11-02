import Foundation

/// Watches the screenshot folder and reports new images (⇧⌘3, ⇧⌘4) and screen
/// recordings (⇧⌘5) once they have been fully written.
@MainActor
final class ScreenshotWatcher {
    var onCapture: ((URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var folder: URL?
    private var known: Set<String> = []
    /// New files waiting for their size to settle: path -> last seen size.
    private var pending: [String: Int] = [:]
    private var pendingTimer: Timer?

    /// Where macOS saves screenshots: `defaults read com.apple.screencapture location`, or the Desktop.
    static var systemFolder: URL {
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"),
           !location.isEmpty {
            let path = (location as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    static var folder: URL {
        Prefs.screenshotFolder.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? systemFolder
    }

    func restart() {
        stop()
        guard Prefs.watchScreenshots else { return }

        let folder = Self.folder
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("Pasty: cannot watch \(folder.path)")
            return
        }
        // Only files that appear from now on count as new.
        known = Set(mediaFiles(in: folder))
        self.folder = folder

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .link], queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        pendingTimer?.invalidate()
        pendingTimer = nil
        pending = [:]
    }

    private func mediaFiles(in folder: URL) -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { MediaFile.kind(of: $0) != nil }.map(\.path)
    }

    /// Queues media files that appeared since the last scan. Runs on every folder change event.
    func scan() {
        guard let folder else { return }
        for path in mediaFiles(in: folder) where !known.contains(path) {
            known.insert(path)
            pending[path] = -1
        }
        guard !pending.isEmpty, pendingTimer == nil else { return }
        pendingTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPending() }
        }
    }

    /// Reports queued files whose size stopped changing. Runs every 0.7 s while files are queued.
    func checkPending() {
        for (path, lastSize) in pending {
            guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int else {
                pending[path] = nil // removed or renamed before it settled
                continue
            }
            if size > 0 && size == lastSize {
                pending[path] = nil
                onCapture?(URL(fileURLWithPath: path))
            } else {
                pending[path] = size
            }
        }
        if pending.isEmpty {
            pendingTimer?.invalidate()
            pendingTimer = nil
        }
    }
}
