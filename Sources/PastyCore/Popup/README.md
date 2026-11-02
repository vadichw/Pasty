# Popup

Purpose: the history popup — a floating panel with a search field and the list of items — and the image preview window next to it. It lets the user find an item and choose it; what happens next (paste or copy) is up to the App module.
Depends on: Settings, Storage, Support

Flow: `PopupController` owns the panel and the keyboard; `PopupModel` holds search, selection and preview state; `HistoryView` draws the model; `ImagePreview` shows a full-size image. Choosing an item calls `PopupController.onSelect(item, plainText, paste)`, set by the App module.

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
- `ImagePreview.init()`
- `PopupModel.onSelect`
- `PopupModel.onOpenSettings`
- `PopupModel.onPreview`
- `ImagePreview.onClick` — clicking the preview closes it:
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
- `ImagePreview.tearDown()`
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

Purpose: opens the preview of an item next to the popup, or closes it (nil).
Side effects:
- [sound] beeps when neither the source file nor the stored data can be read; the preview is then closed.
Uses:
- `PopupModel.store`
- `HistoryStore.fullImage(for:)`
- `ImagePreview.show(_:beside:)`
- `ImagePreview.hide()`
- `PopupModel.closePreview()`

### handleKey(_:)

Purpose: the popup's keyboard shortcuts. Uses key codes, not characters, so they work in every keyboard layout. Keys it doesn't handle go to the search field.
Keys: ⎋ closes the preview, else clears the search, else hides · ↑ ↓ (⌘ for top/bottom), PgUp PgDn (8 items), ⌃N ⌃J / ⌃P ⌃K move the selection · ↩ / keypad Enter choose (with ⇧ / ⌥ as in `choose`) · ⌥⌫ deletes · ⌘1…⌘9 choose by number · ⌘P pin · ⌘Y preview · ⌘, settings · ⌘W hide · ⌘Q quit.
Side effects:
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

Purpose: the popup's state: search query, the filtered list (`visible`), the selected item, and which image is previewed. Published so the list redraws on every change. It never pastes or opens windows itself — it reports through `onSelect`, `onOpenSettings` and `onPreview`.

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

Purpose: moves the selection by a number of rows, or to the first/last row, and scrolls to it. If the preview is open, it follows: it switches to the new item if it is an image, and closes otherwise.
Side effects: none
Invariants:
- INV-Popup-4: the selection never moves past the first or last row.
- INV-Popup-5: with the preview open, moving onto an image previews that image; moving onto anything else closes the preview.

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

Purpose: without an item (⌘Y): closes the open preview, or opens the selected item's. With an item (the eye button): toggles that item's preview, or switches to it. Only images can be previewed; for other items it does nothing.
Side effects: none
Invariants:
- INV-Popup-7: only image items can be previewed; ⌘Y closes an open preview, otherwise opens the selected image's.

### closePreview()

Purpose: closes the preview, if open, and tells the controller through `onPreview(nil)`.
Side effects: none

### appIcon(for:) -> NSImage?

Purpose: the icon of the app the item was copied from, scaled down to 18 pt and cached per app (full app icons are large).
Side effects:
- [apps-read] looks up the app by bundle ID and reads its icon (first time per app).
Output: nil when the item has no source app or the app is not installed.

## ImagePreview

Purpose: a window that shows an image at full size next to the popup. It can never become key, so the popup keeps focus and stays open while the preview is shown. Clicking the image calls `onClick`.

### show(_:beside:)

Purpose: shows `image` next to the popup frame `beside`.
Side effects:
- [window] creates the window on first use, sizes and positions it (see `frame(size:beside:in:)`) and brings it to front without focusing it.
Natural size is pixels / screen scale, so a Retina screenshot shows 1:1.

### hide()

Purpose: hides the preview and frees the image.
Side effects:
- [window] hides the window.
Uses:
- `Memory.relieve()` — returns the decoded image's memory to the system.

### tearDown()

Purpose: hides and releases the window.
Side effects:
- [window] hides the window.
Uses:
- `Memory.relieve()`

### frame(size:beside:in:) -> NSRect

Purpose: where the preview goes: the image size shrunk (never enlarged) to fit on the side of the popup with more room, 8 pt from the popup and the screen edges, top-aligned with the popup; centered on the screen when neither side is at least 240 pt wide.
Side effects: none
Invariants:
- INV-Popup-10: the preview always fits inside the visible screen area, keeps the image's aspect ratio, is never larger than the image, and does not overlap the popup when a side has at least 240 pt.

## HistoryView

Purpose: the popup's content: the search field, the list (app icon, thumbnail or one-line text, pin mark, ⌘1…⌘9 hint, eye button for images, trash button), an empty state, and a footer with the item count, Clear, Settings and Quit. Each row has a context menu: Paste, Paste as Plain Text (text), Copy Only, Preview (images), Show in Finder (files), Pin/Unpin, Delete.
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
- `PopupModel.appIcon(for:)`
- `PopupModel.hover(_:)`
- `PopupModel.select(_:modifiers:)` — click a row to choose it (modifier keys as in `PopupController.choose`).
- `PopupModel.togglePin(_:)`
- `PopupModel.togglePreview(_:)`
- `PopupModel.remove(_:)`
- `PopupModel.clear()`
- `PopupModel.onOpenSettings`

## ClipRow

Purpose: one row of the list. Selected rows are highlighted with the accent color; the tooltip shows up to 1500 characters of the item's text.
Side effects: none
