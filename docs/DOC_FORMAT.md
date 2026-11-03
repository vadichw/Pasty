# Module README format

Pasty's code is described in plain text next to the code: one `README.md` per module in
`Sources/PastyCore/<Module>/`. The goal is that a reviewer can **read what the program does
instead of reading the code** — and trust it, because `pasty-docs check` proves that the text
and the code agree on everything that can be checked mechanically.

The README describes **observable behaviour**, not implementation: what goes in, what comes
out, what it touches outside its own memory, in which order, what is guaranteed, and what
happens when something fails.

## Layout

```md
# Storage

Purpose: one sentence — why the module exists.
Depends on: Settings, Capture        ← modules whose code this module calls (or `none`)

## HistoryStore                       ← every non-private type with behaviour

Purpose: what the type is for.

### add(kind:text:hash:contents:appBundleID:thumbnail:filePath:) -> UUID

Purpose: what the member is for.
Input: the arguments and what they mean.
Output: what it returns.
Side effects:
- [disk-write] `items/<id>.plist` — the raw pasteboard data (binary plist, atomic).
- [schedule] saves `history.json` 0.5 s later (see `Calls later`).
Uses:
- `Prefs.historyLimit` — how many unpinned items to keep.
Calls later:
- `saveNow()` — 0.5 s after the last change.
Order: [disk-write] → [schedule]
Invariants:
- INV-Storage-1: copying the same content again moves the existing item to the top; no duplicate.
Errors:
- [disk-write] a failed write is ignored: the item stays in memory, pasting it later beeps.
```

### Headings

- `# <Module>` — must equal the folder name.
- `## <Type>` — nested types are written `## MediaFile.ImageInfo`.
- `### <member>` — the member's **key**: `name(label1:label2:)` for functions and initializers
  (`_` for unlabeled parameters, `name()` with none), `name` for computed properties.
  Anything after the key (return type, property type) is for the reader and ignored.
  Several members that behave the same can share a heading: `### paused, ignoredApps`.

### Fields

A field is a line starting with `Name:`. Its value is the inline text and/or the `- ` bullets
below it. `none` means empty.

| Field | Required | Checked against the code |
|---|---|---|
| `Purpose:` | module, type, member | must be non-empty |
| `Depends on:` | module | equals the set of modules whose components (classes, namespaces) the code calls or reads; shared data types such as `ClipItem` don't count |
| `Input:` / `Output:` | when there are any | — (read by humans) |
| `Side effects:` | every member, views | the set of `[categories]` equals what the code does |
| `Uses:` | when non-empty | the set of `` `Type.member` `` equals what the code calls/reads in other components |
| `Calls later:` | when non-empty | the set of `` `member` `` equals the callbacks the code stores |
| `Order:` | optional | each listed effect first appears in the code no later than the next one |
| `Invariants:` | optional | every `INV-<Module>-<n>` is unique and mentioned by at least one test |
| `Errors:` | when effects can fail | every effect whose failure the code swallows (`try?`) or catches has a `[category]` bullet |

**Members that must be documented:** every non-private function, initializer and computed
property of a non-private type; plus private ones the system calls (`@objc`, `override`) or
that are stored as a callback (timers, observers, closures) — those are entry points too.
Effects of other private helpers are folded into the member that calls them.

**Views** (SwiftUI `View` structs) are documented as a whole: `Purpose:`, `Side effects:`,
`Uses:` and `Errors:` go directly under `## <View>`, without member sections.

**Data types** (structs, enums with cases) need a section only when they have members.

## Side effect categories

| Category | Means | Detected from |
|---|---|---|
| `pasteboard-read` | reads the clipboard | `changeCount`, `pasteboardItems`, `readObjects`, `data(forType:)`, `string(forType:)`, `NSApp.sendAction` (edit actions: paste/copy/cut) |
| `pasteboard-write` | replaces the clipboard | `clearContents`, `writeObjects`, `setString`, `NSApp.sendAction` (edit actions) |
| `disk-read` | reads files or folders | `Data(contentsOf:)`, `NSImage(contentsOf…)`, `AVURLAsset`, `AVPlayer(url:)`, `CGImageSourceCreateWithURL`, `fileExists`, `contentsOfDirectory`, `attributesOfItem`, `resourceValues(forKeys:)` |
| `disk-write` | creates, changes or deletes files | `write(to:)`, `createDirectory`, `moveItem`, `removeItem` |
| `defaults-read` | reads settings | `UserDefaults` getters, `@AppStorage` |
| `defaults-write` | changes settings | `UserDefaults` setters, `register(defaults:)`, `@AppStorage`, `setFrameAutosaveName` |
| `keystroke` | types into another app | `CGEvent.post(tap:)` |
| `hotkey` | registers global shortcuts | `RegisterEventHotKey`, `UnregisterEventHotKey`, `InstallEventHandler` |
| `folder-watch` | starts/stops watching a folder | `makeFileSystemObjectSource`, `source.cancel()` |
| `login-item` | launch at login | `SMAppService` |
| `accessibility` | checks or requests Accessibility permission | `AXIsProcessTrusted…` |
| `apps-read` | asks which apps are running/installed | `frontmostApplication`, `runningApplications`, `urlForApplication`, `icon(forFile:)` |
| `open-external` | opens System Settings, Finder… | `NSWorkspace.open`, `activateFileViewerSelecting` |
| `input-source` | reads the keyboard layout | `TISCopyCurrentASCIICapableKeyboardLayoutInputSource` |
| `schedule` | runs something later | `Timer`, `asyncAfter`, `DispatchQueue.async`, `Task` |
| `notify-post` / `notify-observe` | in-app notifications | `NotificationCenter` `post` / `addObserver`, `publisher(for:)` |
| `event-monitor` | intercepts key presses in the app | `addLocalMonitorForEvents`, `removeMonitor` |
| `window` | shows, hides or focuses windows and menus | `makeKeyAndOrderFront`, `orderFront`, `orderOut`, `runModal`, `NSApp.activate`, status item |
| `terminate` | quits the app | `NSApp.terminate` |
| `sound` | beeps | `NSSound.beep` |
| `media-playback` | plays or pauses audio/video | `player.play()`, `player.pause()` |
| `memory` | returns freed memory to the system | `malloc_zone_pressure_relief` |
| `log` | writes to the system log | `NSLog` |

The full rule table is `Tools/pasty-docs/Sources/pasty-docs/EffectRules.swift`. Adding a new
kind of side effect to the app means adding a rule there first.

## What the check cannot prove

Static analysis sees *which* effects happen, not *why* or *with which values*. These stay the
author's responsibility and the reviewer's attention:

- business meaning (the `Purpose:` and the prose of each bullet);
- runtime values (sizes, delays, paths built at runtime) — keep them accurate in the text;
- conditions: the check knows a member *can* write a file, not *when* — say it in the bullet;
- behaviour of macOS itself (what the pasteboard server or AppKit does).

Invariants close part of this gap: each one is proven by a test that names its ID.

## Workflow

1. Change the code and the README of every module you touched **in the same commit**.
2. Run `scripts/check_docs.sh` (add `--fix` to regenerate the module graph).
3. List the assumptions you made where the request was silent; the reviewer moves the accepted
   ones into the README.
4. CI runs the same check, plus a warning when a module's code changed but its README did not.
