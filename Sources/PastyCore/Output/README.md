# Output

Purpose: puts a history item back on the clipboard and pastes it into the frontmost app by simulating ⌘V.
Depends on: none

## Paster

Purpose: everything that writes to the clipboard or types into other apps.

### write(_:item:plainText:to:)

Purpose: puts a history item on the pasteboard, either with all its original types (formatting, images, files) or as plain text only.
Input: `contents` — the item's raw data; `item` — its metadata; `plainText` — strip formatting; `pasteboard` — `.general` in the app.
Side effects:
- [pasteboard-write] replaces the clipboard. With `plainText` and a `text` item: only the plain string (the stored UTF-8 string, or the item's search text if there is none). Otherwise: every type of every original pasteboard item.
Invariants:
- INV-Output-1: pasting a text item as plain text leaves only the plain string on the clipboard — no RTF, HTML or other formatting types. (macOS lists the string under two names: `public.utf8-plain-text` and its legacy alias `NSStringPboardType`.)
Images, videos and files ignore `plainText` — they are always written with all types.

### write(_:to:)

Purpose: writes raw contents with all their original types — used for screenshots and by the method above.
Side effects:
- [pasteboard-write] replaces the clipboard with one pasteboard item per dictionary in `contents`.
Invariants:
- INV-Output-2: every type of every item is restored byte for byte.

### hasAccessibility: Bool

Purpose: whether Pasty may simulate key presses (System Settings → Privacy & Security → Accessibility).
Side effects:
- [accessibility] asks macOS (no prompt).

### requestAccessibility()

Purpose: asks macOS to show its "Pasty would like to control this computer" prompt.
Side effects:
- [accessibility] requests the permission; macOS shows the prompt only if the user has not answered yet.

### openAccessibilitySettings()

Purpose: opens System Settings at Privacy & Security → Accessibility.
Side effects:
- [open-external] opens System Settings.

### paste()

Purpose: pastes into the frontmost app by sending ⌘V.
Side effects:
- [accessibility] checks the permission; without it, requests it and sends nothing.
- [keystroke] posts ⌘V key-down and key-up to the session. Local keyboard events are suppressed meanwhile, so keys the user is holding don't mix in.
Order: [accessibility] → [keystroke]
