# App

Purpose: starts Pasty and connects the modules: the menu bar icon and its menu, global shortcuts, what happens when an item is chosen, screenshots, the popup's lifetime and the Settings window.
Depends on: Capture, Input, Output, Popup, Settings, Storage, Support

Flow when the user picks an item: `PopupController.onSelect` → `AppDelegate.use(...)` → `Paster.write(...)` → `ClipboardMonitor.skipCurrentChange()` → `HistoryStore.touch(...)` → 0.1 s later `Paster.paste()`.

## PastyApp

Purpose: the entry point, called by the `Pasty` executable.

### run()

Purpose: starts the app as a menu bar app (no Dock icon, no main menu) with `AppDelegate` as its delegate, and runs it until it quits.
Uses:
- `AppDelegate.init()`
Side effects: none

## AppDelegate

Purpose: the app's controller. Owns the history store, the clipboard monitor, the screenshot watcher, the global shortcuts, the menu bar icon, the popup (created on demand) and the Settings window.

### init()

Purpose: creates the store on `~/Library/Application Support/Pasty`, the clipboard monitor on the general pasteboard and the screenshot watcher. Nothing starts yet.
Side effects: none
Uses:
- `HistoryStore.defaultDirectory`
- `HistoryStore.init(directory:historyLimit:)`
- `Prefs.historyLimit` — the store asks it every time it trims.
- `ClipboardMonitor.init(store:pasteboard:)`
- `ScreenshotWatcher.init()`

### applicationDidFinishLaunching(_:)

Purpose: brings everything up at launch.
Side effects:
- [window] adds the menu bar icon (a clipboard symbol; dimmed while paused). Left click opens the history, right click or ⌃-click the menu.
- [log] logs each shortcut macOS refuses to register.
- [notify-observe] subscribes to `hotKeyChanged`, `hotKeyRecordingStarted` (unregisters all shortcuts while Settings records a new one) and `screenshotSettingsChanged`.
Uses:
- `Prefs.registerDefaults()`
- `Prefs.paused` — the icon's look.
- `ClipboardMonitor.start()`
- `Prefs.hotKey(for:)`
- `HotKey.init(combo:handler:)` — registers every action that has a shortcut.
- `ScreenshotWatcher.onCapture`
- `ScreenshotWatcher.restart()` — at launch and on `screenshotSettingsChanged`.
Calls later:
- `recordScreenCapture(_:)` — for each new screenshot or recording.
- `registerHotKeys()` — on `hotKeyChanged`.
- `perform(_:)` — when a global shortcut is pressed.
Order: [window] → [log] → [notify-observe]

### applicationWillTerminate(_:)

Purpose: saves the history right away when Pasty quits, instead of waiting for the delayed save.
Uses:
- `HistoryStore.saveNow()`
Side effects: none

### use(_:plainText:paste:)

Purpose: puts the chosen item on the clipboard and, if asked, pastes it into the frontmost app.
Input: the item; `plainText` — strip formatting; `paste` — also press ⌘V.
Side effects:
- [disk-read] for images, videos and files: checks that the files still exist.
- [sound] beeps and does nothing else if a file was moved or deleted.
- [schedule] presses ⌘V 0.1 s later, so the previous app's window has regained keyboard focus.
Uses:
- `HistoryStore.contents(for:)` — if the item's data cannot be read, the item is removed:
- `HistoryStore.remove(_:)`
- `Paster.write(_:item:plainText:to:)`
- `ClipboardMonitor.skipCurrentChange()` — so the item is not recorded again as a new copy.
- `HistoryStore.touch(_:)` — moves it to the top.
- `Paster.paste()`
Order: [disk-read] → [schedule]
Invariant (not automated, AppKit-bound): choosing an item never creates a new history entry.

### recordScreenCapture(_:)

Purpose: adds a new screenshot or screen recording to the history, and optionally puts it on the clipboard right away.
Side effects:
- [disk-read] reads a screenshot's image data (up to 50 MB), so it pastes as a picture; recordings are stored as a link to the file only.
Uses:
- `Prefs.paused` — nothing happens while paused.
- `MediaFile.kind(of:)`
- `Prefs.copyScreenshotsToClipboard`
- `Paster.write(_:to:)` — the clipboard gets the file URL (and the image data for screenshots).
- `ClipboardMonitor.skipCurrentChange()`
- `ClipboardMonitor.record(contents:fileURLs:string:imageData:appBundleID:)` — source app `com.apple.screenshot.launcher`.
Errors:
- [disk-read] an unreadable image is stored as a file link only.

### registerHotKeys()

Purpose: (re)registers the global shortcuts from the settings and updates the menu bar icon's tooltip ("Pasty — ⇧⌘C").
Side effects:
- [log] logs each shortcut macOS refuses (e.g. owned by another app).
Uses:
- `Prefs.hotKey(for:)`
- `HotKey.init(combo:handler:)`
Calls later:
- `perform(_:)`

### perform(_:)

Purpose: runs a global shortcut's action.
Side effects:
- [window] "open history" toggles the popup (at the cursor, screen center or below the icon, per settings); "open settings" opens Settings.
- [disk-read] [sound] [schedule] "paste last item as plain text" pastes the most recently copied item (see `use`).
Uses:
- `Prefs.popupPosition`
- `Prefs.paused`
- `PopupController.init(store:)`
- `PopupController.onSelect`
- `PopupController.onOpenSettings`
- `PopupController.onHide`
- `PopupController.toggle(anchor:)`
- `HistoryStore.items`
- `HistoryStore.contents(for:)`
- `HistoryStore.remove(_:)`
- `HistoryStore.touch(_:)`
- `ClipboardMonitor.skipCurrentChange()`
- `Paster.write(_:item:plainText:to:)`
- `Paster.paste()`
Calls later:
- `use(_:plainText:paste:)` — when an item is chosen in the popup.
- `openSettings()` — from the popup's gear button or ⌘,.
- `schedulePopupTeardown()` — when the popup hides.
"Paste last" picks the item with the latest `lastCopied`, ignoring pins. "Pause" toggles `Prefs.paused` and the icon.

### schedulePopupTeardown()

Purpose: frees the popup 20 s after it was hidden, so its view tree doesn't use memory while Pasty sits idle; reopening within 20 s reuses it.
Side effects:
- [schedule] runs the teardown 20 s later (cancelled if the popup is reopened).
Uses:
- `PopupController.isVisible`
- `PopupController.tearDown()`
- `HistoryStore.purgeCaches()` — drops cached thumbnails.
- `Memory.relieve()`

### statusItemClicked(_:)

Purpose: the menu bar icon: left click toggles the popup below the icon; right click or ⌃-click shows the menu: Open History, Pause Recording (checked when paused), Clear History, Settings…, About Pasty, Quit Pasty — with their global shortcuts shown.
Side effects:
- [window] shows the menu.
Uses:
- `PopupController.hide()` — an open popup closes before the menu appears.
- `Prefs.paused`
- `Prefs.hotKey(for:)`
- `PopupController.init(store:)`
- `PopupController.onSelect`
- `PopupController.onOpenSettings`
- `PopupController.onHide`
- `PopupController.toggle(anchor:)`
Calls later:
- `use(_:plainText:paste:)`
- `openSettings()`
- `schedulePopupTeardown()`

### menuDidClose(_:)

Purpose: detaches the menu from the icon after it closes, so the next left click opens the popup again.
Side effects: none

### openHistory()

Purpose: menu item "Open History": opens the popup below the icon.
Side effects: none
Uses:
- `PopupController.init(store:)`
- `PopupController.onSelect`
- `PopupController.onOpenSettings`
- `PopupController.onHide`
- `PopupController.show(anchor:)`
Calls later:
- `use(_:plainText:paste:)`
- `openSettings()`
- `schedulePopupTeardown()`

### togglePause()

Purpose: menu item "Pause Recording": pauses or resumes recording copies and screenshots; the icon dims while paused.
Uses:
- `Prefs.paused`
Side effects: none

### clearHistory()

Purpose: menu item "Clear History": deletes every unpinned item, without confirmation.
Uses:
- `HistoryStore.clear(keepPinned:)`
Side effects: none

### showAbout()

Purpose: menu item "About Pasty": brings Pasty forward and shows the standard About panel.
Side effects:
- [window] activates Pasty and shows the panel.

### quit()

Purpose: menu item "Quit Pasty".
Side effects:
- [terminate] quits (the history is saved in `applicationWillTerminate`).

### windowWillClose(_:)

Purpose: frees the Settings window (and its once-a-second permission check) after it closes.
Side effects:
- [schedule] releases it on the next run loop pass, after AppKit is done closing it.
Uses:
- `Memory.relieve()`

### openSettings()

Purpose: opens the Settings window (creating it if needed), brings Pasty forward and focuses it.
Side effects:
- [window] activates Pasty and shows the window.
