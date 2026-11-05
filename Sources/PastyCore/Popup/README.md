# Popup

Purpose: the history popup — a floating panel with a search field and the list of items — and the preview window next to it, which shows an image full size or plays a video. It lets the user find an item and choose it; what happens next (paste or copy) is up to the App module.
Depends on: Capture, Settings, Storage, Support

Flow: `PopupController` owns the panel and the keyboard; `PopupModel` holds search, selection and preview state; `HistoryView` draws the model; `MediaPreview` shows a full-size image. Choosing an item calls `PopupController.onSelect(item, plainText, paste)`, set by the App module.

The panel takes keyboard input **without activating Pasty**: the app the user was typing in stays frontmost, so the simulated ⌘V lands there.

## PopupAnchor

Purpose: where to open the popup: at the mouse cursor, centered on the screen (a bit above the middle), or below the menu bar icon.

## PopupPanel

Purpose: the borderless, resizable, rounded, translucent panel. It floats above other windows (menu level), appears on every Space and over full-screen apps, can become key (take typing) but never main, and does not hide when Pasty is inactive.

### init()

Purpose: creates the panel, 420×480 by default, at least 380×300.
Side effects:
- [defaults-write] AppKit remembers the panel's size and position in Pasty's settings (`PastyPopup` frame autosave).

### canBecomeKey, canBecomeMain

Purpose: lets the panel receive key presses (`true`) without becoming the main window (`false`).
Side effects: none

## PopupController

Purpose: shows, positions and hides the popup, routes key presses to the model, and turns a chosen item into "paste or copy, formatted or plain".

### init(store:)

Purpose: builds the panel with the SwiftUI list inside and wires the model and the preview to it.
Side effects: none
Uses:
- `PopupModel.init(store:)`
- `PopupPanel.init()`
- `MediaPreview.init()`
- `PopupModel.onSelect`
- `PopupModel.onOpenSettings`
- `PopupModel.onPreview`
- `MediaPreview.onClick` — clicking the preview closes it:
- `PopupModel.closePreview()`
Calls later:
- `choose(_:modifiers:)` — when the model reports a chosen item.
- `hide()` — before opening Settings from the popup.
- `showPreview(_:)` — when the model opens, switches or closes the preview.

### isVisible: Bool

Purpose: whether the popup is on screen.
Side effects: none

### toggle(anchor:)

Purpose: opens the popup at `anchor`, or hides it if it is open.
Side effects:
- [window] hides the panel, or shows it (see `show(anchor:)`).
- [event-monitor] removes or installs the key monitor.
Uses:
- `PopupModel.reset()`
- `PopupModel.closePreview()`
Calls later:
- `handleKey(_:)`
Invariants:
- INV-Popup-8: the popup does not reopen within 0.25 s after it hid — clicking the menu bar icon while the popup is open closes it instead of closing and reopening it.

### show(anchor:)

Purpose: opens the popup with an empty search and the newest item selected.
Side effects:
- [window] positions the panel at the anchor, kept fully inside the visible area of the screen under the mouse, and makes it key.
- [event-monitor] starts intercepting key presses in the panel.
Uses:
- `PopupModel.reset()`
Calls later:
- `handleKey(_:)` — for every key press in the panel.
Order: [window] → [event-monitor]

### hide()

Purpose: closes the popup (and its preview). Does nothing if it is already hidden.
Side effects:
- [window] hides the panel.
- [event-monitor] stops intercepting key presses.
Uses:
- `PopupModel.closePreview()`
Order: [window] → [event-monitor]
Then calls `onHide`, which the App module uses to free the popup 20 s later.

### tearDown()

Purpose: releases the panel, its SwiftUI view tree and the preview window, to save memory while Pasty is idle.
Side effects:
- [event-monitor] removes the key monitor.
- [window] hides and releases the preview window and the panel.
Uses:
- `MediaPreview.tearDown()`
- `PopupModel.onSelect`
- `PopupModel.onOpenSettings`
- `PopupModel.onPreview`

### windowDidResignKey(_:)

Purpose: the popup closes as soon as it loses keyboard focus — the user clicked elsewhere or switched apps.
Side effects:
- [window] hides the panel.
- [event-monitor] stops intercepting key presses.
Uses:
- `PopupModel.closePreview()`

### choose(_:modifiers:)

Purpose: hides the popup and reports the chosen item to the App module, deciding plain text and paste from the settings and the modifier keys.
Side effects:
- [window] hides the panel.
- [event-monitor] stops intercepting key presses.
Uses:
- `PopupModel.closePreview()`
- `Prefs.pastePlainByDefault` — ⇧ inverts it.
- `Prefs.pasteAutomatically` — ⌥ inverts it.
Invariants:
- INV-Popup-9: ⇧ flips "paste as plain text" and ⌥ flips "paste automatically" relative to the settings: e.g. with automatic pasting on, ⌥↩ only copies; with it off, ⌥↩ pastes.

### showPreview(_:)

Purpose: opens the preview of an item next to the popup, or closes it (nil). Images are shown full size; videos are played from their file.
Side effects:
- [disk-read] for a video: checks that its file still exists (recordings are kept only as a link to the file).
- [sound] beeps when there is nothing to show — the video file is gone, or neither the image's source file nor its stored data can be read; the preview is then closed.
Uses:
- `PopupModel.store`
- `HistoryStore.fullImage(for:)`
- `MediaPreview.show(_:beside:)`
- `MediaPreview.showVideo(_:beside:)`
- `MediaPreview.hide()`
- `PopupModel.closePreview()`

### handleKey(_:)

Purpose: the popup's keyboard shortcuts. Uses key codes, not characters, so they work in every keyboard layout. Keys it doesn't handle go to the search field.
Keys: ⎋ closes the preview, else clears the search, else hides · ↑ ↓ (⌘ for top/bottom), PgUp PgDn (8 items), ⌃N ⌃J / ⌃P ⌃K move the selection · ↩ / keypad Enter choose (with ⇧ / ⌥ as in `choose`) · ⌥⌫ deletes · ⌘1…⌘9 choose by number · ⌘P pin · ⌘Y preview · ⌘, settings · ⌘W hide · ⌘Q quit · ⌘V ⌘C ⌘X ⌘A ⌘Z ⇧⌘Z edit the search text as in any text field (Pasty has no Edit menu, which is what normally delivers these to text fields).
Side effects:
- [pasteboard-read] ⌘V pastes the clipboard's text into the search field.
- [pasteboard-write] ⌘C / ⌘X copy or cut the selected search text — which then lands in the history like any other copy.
- [window] ⎋ (with nothing else to clear) and ⌘W hide the popup.
- [event-monitor] hiding stops intercepting key presses.
- [terminate] ⌘Q quits Pasty.
Uses:
- `PopupModel.previewID`
- `PopupModel.query`
- `PopupModel.closePreview()`
- `PopupModel.move(_:)`
- `PopupModel.moveToEdge(top:)`
- `PopupModel.select(_:modifiers:)`
- `PopupModel.select(at:modifiers:)`
- `PopupModel.remove(_:)`
- `PopupModel.togglePin(_:)`
- `PopupModel.togglePreview(_:)`
- `PopupModel.onOpenSettings`

## PopupModel

Purpose: the popup's state: search query, the filtered list (`visible`), the selected item, and which image or video is previewed. Published so the list redraws on every change. It never pastes or opens windows itself — it reports through `onSelect`, `onOpenSettings` and `onPreview`.

### init(store:)

Purpose: creates the model and keeps `visible` in sync with the history.
Uses:
- `HistoryStore.items`
Calls later:
- `refilter(_:)` — whenever the history changes.
Side effects: none

### selected: ClipItem?

Purpose: the selected item, if it is in the filtered list.
Side effects: none

### reset()

Purpose: prepares the popup for opening: clears the search, selects the first item, scrolls to it and focuses the search field.
Side effects: none

### refilter(_:)

Purpose: recomputes `visible` from the history (or the given items) and the query.
Uses:
- `HistoryStore.items`
Side effects: none
Invariants:
- INV-Popup-1: an item is visible when its text contains every word of the query, in any order, ignoring case; an empty query shows everything.
- INV-Popup-2: the selection is always a visible item: when the selected item is filtered out or deleted, the first visible item is selected (nothing when the list is empty).

### move(_:), moveToEdge(top:)

Purpose: moves the selection by a number of rows, or to the first/last row, and scrolls to it. If the preview is open, it follows: it switches to the new item if it can be previewed (see `canPreview`), and closes otherwise.
Side effects: none
Invariants:
- INV-Popup-4: the selection never moves past the first or last row.
- INV-Popup-5: with the preview open, moving onto an image or video previews it; moving onto anything else closes the preview.

### hover(_:)

Purpose: selects the item under the mouse — but not within 0.4 s after keyboard navigation, so a list scrolling under a still mouse doesn't steal the selection.
Side effects: none

### select(_:modifiers:), select(at:modifiers:)

Purpose: chooses an item — the given one, the selected one, or the one at a row (⌘1…⌘9) — by calling `onSelect` with the modifier keys.
Side effects: none

### togglePin(_:)

Purpose: pins or unpins the given or selected item and keeps it selected and scrolled into view.
Uses:
- `HistoryStore.togglePin(_:)`
Side effects: none

### remove(_:)

Purpose: deletes the given or selected item.
Uses:
- `HistoryStore.remove(_:)`
Side effects: none
Invariants:
- INV-Popup-3: deleting the selected item selects the next one, or the previous one if it was last.
- INV-Popup-6: deleting the previewed item closes the preview.

### clear()

Purpose: closes the preview and deletes every unpinned item.
Uses:
- `HistoryStore.clear(keepPinned:)`
Side effects: none

### togglePreview(_:)

Purpose: without an item (⌘Y): closes the open preview, or opens the selected item's. With an item (the eye button): toggles that item's preview, or switches to it. Only images and videos can be previewed; for other items it does nothing.
Side effects: none
Invariants:
- INV-Popup-7: only images and videos can be previewed; ⌘Y closes an open preview, otherwise opens the selected item's.

### canPreview(_:) -> Bool

Purpose: whether an item has a preview: images (shown full size) and videos (played).
Side effects: none

### closePreview()

Purpose: closes the preview, if open, and tells the controller through `onPreview(nil)`.
Side effects: none

### appIcon(for:) -> NSImage?

Purpose: the icon of the app the item was copied from, scaled down to 18 pt and cached per app (full app icons are large).
Side effects:
- [apps-read] looks up the app by bundle ID and reads its icon (first time per app).
Output: nil when the item has no source app or the app is not installed.

## UsageLevel

Purpose: how close the history is to its size limit — `low`, `medium` or `high` — which the footer shows as green, orange and red.

### of(used:limit:) -> UsageLevel

Purpose: the level for `used` of `limit` items: below 70 % `low`, below 90 % `medium`, from 90 % (or with a limit of 0) `high`.
Side effects: none
Invariants:
- INV-Popup-11: below 70 % of the limit is `low`, 70 % up to 90 % is `medium`, 90 % and above is `high`.

## ByteSize

Purpose: formats sizes for the popup.

### format(_:) -> String

Purpose: `368 B` below one kilobyte, otherwise the system's file-size style (`17 KB`, `2.1 MB`; 1 KB = 1000 bytes, like Finder).
Side effects: none
Invariants:
- INV-Popup-13: sizes below 1000 bytes are shown as `<n> B`; from 1000 bytes in KB, MB… like Finder.

## MediaPreview

Purpose: a window next to the popup that shows an image at full size or plays a video. It can never become key, so the popup keeps the keyboard and stays open while the preview is shown. Clicking an image calls `onClick` (the controller closes the preview); a video has the standard player controls (play/pause, scrubbing, volume), which react to the first click. Natural size is pixels / screen scale, so Retina screenshots and recordings show 1:1.

### show(_:beside:)

Purpose: shows `image` next to the popup frame `beside`, stopping a video that was playing.
Side effects:
- [media-playback] stops the video, if one was playing.
- [window] creates the window on first use, sizes and positions it (see `frame(size:beside:in:)`) and brings it to front without focusing it.

### showVideo(_:beside:)

Purpose: plays the video file at `url` next to the popup frame `beside`, with sound, from the start. Does not loop.
Side effects:
- [schedule] reads the video's frame size in the background (1280×720 if it can't be read), then plays it.
Uses:
- `MediaFile.videoSize(url:)`
Calls later:
- `play(_:pixelSize:beside:generation:)` — once the size is known.

### play(_:pixelSize:beside:generation:)

Purpose: shows the player sized for the video and starts playback — unless the preview was closed or switched to another item while the size was being read.
Side effects:
- [media-playback] stops the previous video, starts this one.
- [disk-read] opens the video file for playback.
- [window] sizes, positions and brings the window to front, like `show`.
Order: [media-playback] → [disk-read] → [window]

### hide()

Purpose: hides the preview, stops the video and frees the image.
Side effects:
- [window] hides the window.
- [media-playback] stops the video.
Uses:
- `Memory.relieve()` — returns the decoded image's memory to the system.

### tearDown()

Purpose: hides and releases the window.
Side effects:
- [window] hides the window.
- [media-playback] stops the video.
Uses:
- `Memory.relieve()`

### frame(size:beside:in:) -> NSRect

Purpose: where the preview goes: the image or video size shrunk (never enlarged) to fit on the side of the popup with more room, 8 pt from the popup and the screen edges, top-aligned with the popup; centered on the screen when neither side is at least 240 pt wide.
Side effects: none
Invariants:
- INV-Popup-10: the preview always fits inside the visible screen area, keeps the aspect ratio, is never larger than the media, and does not overlap the popup when a side has at least 240 pt.

## HistoryView

Purpose: the popup's content: the search field, the list (app icon, thumbnail or one-line text, size, eye button for images and videos, pin button, trash button), an empty state, and a footer with the fill indicator and three icon buttons: trash (delete all unpinned items), Settings and Quit. The fill indicator shows "used/limit" (e.g. `20/2000`) with a small bar, both green, orange or red by `UsageLevel` (in the light appearance, darker shades of these colors, so both stay readable on the light translucent panel); its tooltip explains that the oldest unpinned items are deleted when it is full. Next to it, in grey, the total size of all items (`381 KB` — the sum of the sizes shown in the rows; see `HistoryStore.totalBytes`, formatted by `ByteSize`); hidden while the history is empty. While searching, the footer also shows "N found". Each row has a context menu: Paste, Paste as Plain Text (text), Copy Only, Preview (images and videos), Show in Finder (files), Pin/Unpin, Delete.
Side effects:
- [open-external] "Show in Finder" reveals the item's files.
- [terminate] the power button quits Pasty.
Uses:
- `PopupModel.query`
- `PopupModel.visible`
- `PopupModel.selectedID`
- `PopupModel.previewID`
- `PopupModel.scrollTarget` — keyboard navigation scrolls the list; hovering does not.
- `PopupModel.focusToken` — re-focuses the search field each time the popup opens.
- `PopupModel.store`
- `HistoryStore.thumbnail(for:)`
- `HistoryStore.usage` — the fill indicator.
- `HistoryStore.items` — the total size is hidden while it is empty.
- `HistoryStore.totalBytes` — the total size next to it.
- `ByteSize.format(_:)`
- `PopupModel.appIcon(for:)`
- `PopupModel.hover(_:)`
- `PopupModel.select(_:modifiers:)` — click a row to choose it (modifier keys as in `PopupController.choose`).
- `PopupModel.togglePin(_:)`
- `PopupModel.togglePreview(_:)`
- `PopupModel.canPreview(_:)`
- `PopupModel.remove(_:)`
- `PopupModel.clear()`
- `PopupModel.onOpenSettings`

## ClipRow

Purpose: one row of the list. Besides the content it shows the item's size in grey (`byteCount`, e.g. `368 B` or `1.2 MB`; tooltip "Size of the copied data, all formats included") before the eye, pin and trash buttons. The pin button pins or unpins the item: an outline when unpinned, a filled orange pin when pinned (white on a selected row). Rows are not numbered; ⌘1…⌘9 still choose the first nine rows. Selected rows are highlighted with the accent color; the tooltip shows up to 1500 characters of the item's text.
Side effects: none
Uses:
- `ByteSize.format(_:)`
