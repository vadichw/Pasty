# Settings

Purpose: the user's preferences — stored in `UserDefaults`, read by every other module — and the Settings window that edits them.
Depends on: Capture, Output, Storage

Settings changes reach the rest of the app in two ways: modules read `Prefs` at the moment they need a value, and three in-app notifications announce changes that need action — `hotKeyChanged` (re-register shortcuts), `hotKeyRecordingStarted` (release all shortcuts so the recorder can capture any combo) and `screenshotSettingsChanged` (restart the screenshot watcher).

## HotKeyAction

Purpose: the actions that can have a global shortcut: open history, paste last item as plain text, pause/resume recording, open settings.

### id, title, defaultCombo

Purpose: identity for SwiftUI lists, the label shown in Settings, and the default shortcut (⇧⌘C for "open history", none for the others).
Side effects: none

## Prefs

Purpose: typed access to every setting. Defaults: history size 200, paste automatically off (choosing an item only copies it; ⌥↩ pastes), plain text by default off, save images on, popup at the cursor, not paused, no ignored apps, watch screenshots on, copy screenshots to the clipboard on, system screenshot folder.

### registerDefaults()

Purpose: registers the default values above, so unset settings read as defaults. Called once at launch.
Side effects:
- [defaults-write] registers defaults (in memory; nothing is written to disk).

### historyLimit, pasteAutomatically, pastePlainByDefault, saveImages, watchScreenshots, copyScreenshotsToClipboard, popupPosition

Purpose: read-only settings (they are changed by the Settings window through `@AppStorage`).
Side effects:
- [defaults-read] reads the value.
Invariants:
- INV-Settings-4: `historyLimit` is never below 10, whatever is stored.
- INV-Settings-5: automatic pasting is off unless the user turns it on: by default choosing an item only copies it.
`popupPosition` falls back to "at cursor" for unknown stored values.

### screenshotFolder, paused, ignoredApps

Purpose: settings that code changes directly: the custom screenshot folder (nil = system folder), whether recording is paused, and the bundle IDs of apps whose copies are ignored.
Side effects:
- [defaults-read] reads the value.
- [defaults-write] writes it when set.
`screenshotFolder` is stored as an empty string when nil.

### hotKey(for:) -> KeyCombo?

Purpose: the shortcut of an action, or nil if it has none.
Side effects:
- [defaults-read] reads the action's stored combo.
Invariants:
- INV-Settings-2: an action with nothing stored has its default shortcut; one whose shortcut was removed (stored as empty data) has none, even if it has a default.
Unreadable stored data counts as "no shortcut".

### setHotKey(_:for:)

Purpose: assigns (or with nil removes) an action's shortcut.
Side effects:
- [defaults-read] reads the other actions' shortcuts.
- [defaults-write] stores the new combo (empty data for "removed"), and stores "removed" for any other action that had the same combo.
Invariants:
- INV-Settings-1: one combo belongs to at most one action: assigning it takes it away from the action that had it.

### resetHotKey(for:)

Purpose: restores an action's default shortcut.
Side effects:
- [defaults-read] reads the other actions' shortcuts.
- [defaults-write] takes the default combo away from any other action that had it, then deletes the stored value so the default applies.
Invariants:
- INV-Settings-3: after a reset the action has its default shortcut again, and no other action has that combo.

## SettingsView

Purpose: the Settings window: global shortcuts, popup position, launch at login, pasting options and the Accessibility status, screenshot options and folder, history size, clearing the history, ignored apps, and a reference of the popup's keys.
Side effects:
- [defaults-read] shows the current settings (`@AppStorage`).
- [defaults-write] every toggle and picker writes its setting immediately.
- [login-item] shows and changes "Launch at login" (registers / unregisters Pasty as a login item).
- [schedule] re-checks the Accessibility permission every second while the window is open, so the status updates as soon as it is granted.
- [notify-post] posts `screenshotSettingsChanged` when screenshot watching or the folder changes.
- [window] "Change…" opens a folder picker.
- [apps-read] lists running regular apps for "Add Application", and shows icons and names of ignored apps.
- [log] logs when changing the login item fails.
Uses:
- `HistoryStore.items` — "Items in history: N".
- `HistoryStore.trim()` — applies a lower history size right away.
- `HistoryStore.clear(keepPinned:)` — "Clear" keeps pinned items; "Delete All…" (after a confirmation) deletes everything.
- `Paster.hasAccessibility`
- `Paster.requestAccessibility()`
- `Paster.openAccessibilitySettings()` — "Grant…" asks for the permission and opens System Settings.
- `Prefs.ignoredApps`
- `Prefs.screenshotFolder`
- `ScreenshotWatcher.folder` — the folder shown, and where the picker starts.
Errors:
- [login-item] if macOS refuses the change, the error is logged and the toggle snaps back to the real state.

## HotKeyRecorder

Purpose: one shortcut field in Settings. Click it, press the new combo; ⎋ cancels. A combo needs ⌘, ⌥ or ⌃ unless it is a function key. Also offers "remove" and "reset to default".
Side effects:
- [notify-post] posts `hotKeyRecordingStarted` when recording starts and `hotKeyChanged` when it ends or the shortcut changes.
- [event-monitor] while recording, intercepts key presses in the app to capture the combo.
- [sound] beeps for a combo without ⌘, ⌥ or ⌃.
- [notify-observe] refreshes when another recorder takes this action's combo away.
Uses:
- `Prefs.hotKey(for:)`
- `Prefs.setHotKey(_:for:)`
- `Prefs.resetHotKey(for:)`
