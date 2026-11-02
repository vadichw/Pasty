# Input

Purpose: global keyboard shortcuts that work in any app, and the key combination type used to store them.
Depends on: none

## HotKey

Purpose: one registered global shortcut. Uses Carbon `RegisterEventHotKey`, which needs no Accessibility permission. The shortcut stays registered while the object is alive.

### init(combo:handler:)

Purpose: registers `combo` system-wide and calls `handler` on the main thread whenever it is pressed.
Input: `combo` — keys and modifiers; `handler` — what to do.
Output: nil if macOS refuses the combo (e.g. another app already owns it).
Side effects:
- [hotkey] installs Pasty's hotkey event handler once per launch; registers the combo.
- [schedule] each press is delivered to `handler` asynchronously on the main queue.

### deinit

Purpose: releasing the object unregisters the shortcut.
Side effects:
- [hotkey] unregisters the combo.

## KeyCombo

Purpose: a key plus modifiers (⌘ ⇧ ⌥ ⌃), stored in settings as JSON. The default is ⇧⌘C.

### flags, carbonModifiers

Purpose: the modifiers as AppKit flags (only ⌘ ⇧ ⌥ ⌃ are kept; Caps Lock, Fn etc. are dropped) and as the Carbon bit mask `RegisterEventHotKey` expects.
Side effects: none
Invariants:
- INV-Input-1: `flags` keeps only ⌘ ⇧ ⌥ ⌃, and `carbonModifiers` has exactly the matching Carbon bits.

### displayString: String

Purpose: the combo as shown to the user, modifiers in the standard macOS order: `⌃⌥⇧⌘` followed by the key, e.g. `⇧⌘C`.
Side effects:
- [input-source] reads the ASCII-capable keyboard layout to name the key.
Invariants:
- INV-Input-2: modifiers are always shown in the order ⌃⌥⇧⌘, before the key name.

### menuKeyEquivalent: String?

Purpose: the key as an NSMenu key equivalent (lowercase character) so menus can show the shortcut; nil for special keys (arrows, F-keys, Space, Return…) that menus cannot display this way.
Side effects:
- [input-source] reads the keyboard layout.
Invariants:
- INV-Input-3: special keys (Return, Space, arrows, F1–F12…) have no menu key equivalent.

### keyName(for:) -> String

Purpose: the name of a key code: a symbol for special keys (`↩`, `⎋`, `F5`, `Space`…), otherwise the character it types in the ASCII-capable layout, uppercased — so names stay Latin even when e.g. the Russian layout is active. `#<code>` if it cannot be translated.
Side effects:
- [input-source] reads the ASCII-capable keyboard layout.
