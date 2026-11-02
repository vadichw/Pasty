# Pasty

A menu bar clipboard manager for macOS.
Swift + AppKit + SwiftUI, no external dependencies, macOS 14+.

## Features

- Keeps a history of everything you copy: text (with formatting), images, videos, files.
- **Screenshots & screen recordings** (⇧⌘3, ⇧⌘4, ⇧⌘5) land in the history automatically, with thumbnails —
  and are copied to the clipboard right away, so you can ⌘V them immediately (both optional).
- Open the history with **⇧⌘C** — at the cursor, screen center, or below the menu bar icon.
- **Configurable global shortcuts** (Settings → Global Shortcuts): open history, paste last item as plain text,
  pause/resume recording, open settings. Any shortcut can be changed or removed.
- Instant search: type several words in any order.
- The selected item is pasted straight into the active app (simulated ⌘V).
- Preview copied images and screenshots at full size: the eye button next to the item, or ⌘Y.
- Delete any item with the trash button next to it, ⌥⌫, or the context menu.
- Pin items (⌘P) — pinned items stay on top and survive clearing.
- Copying the same thing again moves it to the top instead of creating a duplicate.
- Passwords from password managers (marked with `org.nspasteboard.ConcealedType`) are never saved;
  you can also ignore specific apps.
- Pause recording, history size limit, launch at login.

## Build & install

```bash
./build.sh            # builds build/Pasty.app
./build.sh --install  # also copies it to /Applications and launches it
```

On first launch macOS asks for **Accessibility** access — it is only needed for automatic
pasting (⌘V). Without it, selecting an item just copies it to the clipboard.

To pick up screenshots it also asks for access to the screenshot folder (the Desktop by default).
Screen recordings are stored as links to the file — if you delete the video, it can no longer be pasted.

> **Keep permissions across rebuilds:** run `scripts/make_cert.sh` once. It creates a local
> self-signed certificate that `build.sh` then signs with. Without it the app is signed ad-hoc,
> macOS treats every rebuild as a new app, and you have to remove the old Pasty entry in
> System Settings → Privacy & Security → Accessibility and enable it again.

## Shortcuts

| Keys | Action |
|---|---|
| ⇧⌘C | Open / close history (configurable) |
| ↑ ↓, ⌃N ⌃P, ⌃J ⌃K | Move selection |
| ⌘↑ ⌘↓, PgUp PgDn | Jump to top/bottom, page |
| ↩ | Paste |
| ⇧↩ | Paste without formatting |
| ⌥↩ | Copy only (no paste) |
| ⌘1 … ⌘9 | Select item by number |
| ⌘P | Pin / unpin |
| ⌘Y | Preview image (also the eye button) |
| ⌥⌫ | Delete item |
| ⎋ | Close preview, clear search, then close |
| ⌘, | Settings |

Click the menu bar icon for the history, right-click for the menu (pause, clear, settings, quit).

## Layout

| File | Purpose |
|---|---|
| `ClipboardMonitor.swift` | Polls `NSPasteboard.changeCount` every 0.5 s and stores all data types |
| `HistoryStore.swift` | `history.json` + raw data of each item in `items/<id>.plist` (~/Library/Application Support/Pasty) |
| `HotKey.swift`, `KeyCombo.swift` | Global hotkey via Carbon (no permissions required) |
| `ScreenshotWatcher.swift` | Watches the screenshot folder for new images/videos |
| `MediaFile.swift` | Image/video detection, thumbnails, video duration |
| `PopupController.swift` | Non-activating panel: takes keyboard input without stealing focus from the current app |
| `PopupModel.swift`, `HistoryView.swift` | Search, selection and the SwiftUI list |
| `ImagePreview.swift` | Full-size image preview window next to the popup |
| `Paster.swift` | Writes to the clipboard and simulates ⌘V |
| `SettingsView.swift` | Settings window |
