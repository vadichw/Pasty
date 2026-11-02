# Storage

Purpose: keeps the clipboard history — the list of items in memory, their raw data and thumbnails on disk — and survives restarts.
Depends on: none

On disk, in the directory given to `HistoryStore.init` (the app passes `~/Library/Application Support/Pasty`):

| File | Contents |
|---|---|
| `history.json` | metadata of every item (`[ClipItem]`, JSON) |
| `items/<id>.plist` | raw pasteboard data of one item (`ClipContents`, binary plist) |
| `items/<id>.png` | thumbnail of an image or video item |

## ClipItem

Purpose: metadata of one history entry — what it is, its searchable text, where it came from, when it was copied, whether it is pinned. The raw data is not here; it stays on disk.

Fields: `id`, `kind` (`text` / `image` / `video` / `files`), `text` (at most `searchTextLimit` = 2000 characters), `hash` (identifies the content for de-duplication), `filePath` (source file of screenshots, recordings and copied media), `appBundleID` (app that was frontmost when it was copied), `firstCopied`, `lastCopied`, `copyCount`, `pinned`.

### title: String

Purpose: one-line label for the list.
Output: the first 400 characters of `text` with every run of whitespace (including newlines) collapsed to one space; `(whitespace)` if nothing is left.
Side effects: none
Invariants:
- INV-Storage-9: `title` never contains a newline, and is `(whitespace)` for whitespace-only text.

### fileURLs: [URL]

Purpose: files the item refers to, for "Show in Finder" and the missing-file check before pasting.
Output: `[filePath]` if the item has a source file; for `files` items one URL per line of `text`; otherwise empty.
Side effects: none

## HistoryStore

Purpose: the single owner of the history. Every change goes through it; it keeps `items` sorted, enforces the size limit and persists everything.

`items` is published (`@Published`): the popup re-filters whenever it changes. Order is always: pinned items first, then by `lastCopied`, newest first.

### defaultDirectory: URL

Purpose: where the app keeps its history: `~/Library/Application Support/Pasty`.
Side effects: none

### init(directory:historyLimit:)

Purpose: opens (or creates) the history in `directory`.
Input: `directory` — where the files live; `historyLimit` — called whenever the store needs the current limit of unpinned items.
Side effects:
- [disk-write] creates `directory/items/` if missing.
- [disk-read] reads `history.json` and checks that each item's `items/<id>.plist` exists.
- [disk-write] deletes files in `items/` that belong to no item (left over from crashes or older versions).
Invariants:
- INV-Storage-6: items saved with `saveNow()` are loaded back unchanged by a new store on the same directory.
- INV-Storage-7: on load, items whose data file is missing are dropped, and files in `items/` that belong to no item are deleted.
Errors:
- [disk-read] a missing or unreadable `history.json` starts an empty history (the old file is overwritten on the next save).
- [disk-write] failing to create the folder or delete an orphan is ignored; later writes then fail silently too.

### hash(_:) -> String

Purpose: SHA-256 hex digest of a string (as UTF-8) or of raw data; used as the de-duplication key.
Side effects: none

### add(kind:text:hash:contents:appBundleID:thumbnail:filePath:) -> UUID

Purpose: records newly copied content.
Input: `kind`, `text` (searchable text), `hash` (content key), `contents` (raw pasteboard data), `appBundleID` (source app, may be nil), `thumbnail` (PNG data, may be nil), `filePath` (source file, may be nil).
Output: the id of the new item, or of the existing item with the same `hash`.
Side effects:
- [disk-write] writes `items/<id>.plist` with `contents` (atomic). For a new item also writes `items/<id>.png` if a thumbnail is given.
- [disk-write] deletes the files of unpinned items beyond the history limit (see `trim()`).
- [schedule] saves `history.json` 0.5 s later.
Calls later:
- `saveNow()` — once, 0.5 s after the first unsaved change.
Order: [disk-write] → [schedule]
Invariants:
- INV-Storage-1: adding content whose `hash` is already in the history creates no new item: the existing one keeps its id, gets `lastCopied = now`, `copyCount + 1`, the new data, and moves to the top (of the unpinned part if it is not pinned).
- INV-Storage-2: after any change, pinned items come first, then the rest by `lastCopied`, newest first.
- INV-Storage-8: `contents(for:)` returns exactly the `contents` given to the latest `add` for that item.
Errors:
- [disk-write] a failed write is ignored: the item is in the list, but `contents(for:)` returns nil and choosing it removes it.

### updateMedia(id:thumbnail:text:)

Purpose: fills in details computed after the item was added — a video's thumbnail and its "name — duration" text.
Input: `id` of the item; `thumbnail` PNG data and `text`, each optional.
Side effects:
- [disk-write] overwrites `items/<id>.png` when a thumbnail is given (and drops the cached image).
- [schedule] saves `history.json` 0.5 s later.
Calls later:
- `saveNow()`
Errors:
- [disk-write] a failed thumbnail write is ignored; the item shows its kind icon instead.
Does nothing if the item was deleted in the meantime.

### touch(_:)

Purpose: marks an item as just used after it was pasted from the history.
Side effects:
- [schedule] saves `history.json` 0.5 s later.
Calls later:
- `saveNow()`
Effect on `items`: `lastCopied = now`, `copyCount + 1`, re-sorted (so it moves to the top of its group). Does nothing for an unknown item.

### togglePin(_:)

Purpose: pins or unpins an item. Pinned items stay on top and are never removed by `trim()` or `clear(keepPinned: true)`.
Side effects:
- [disk-write] unpinning can push the history over the limit; the oldest unpinned items' files are deleted (see `trim()`).
- [schedule] saves `history.json` 0.5 s later.
Calls later:
- `saveNow()`
Errors:
- [disk-write] failed deletes are ignored; the orphans are removed on the next launch.

### remove(_:)

Purpose: deletes one item.
Side effects:
- [disk-write] deletes `items/<id>.plist` and `items/<id>.png`.
- [schedule] saves `history.json` 0.5 s later.
Calls later:
- `saveNow()`
Invariants:
- INV-Storage-5: after `remove`, the item is gone from `items` and both of its files are gone from disk.
Errors:
- [disk-write] failed deletes are ignored; the orphans are removed on the next launch.

### clear(keepPinned:)

Purpose: deletes every item, or every unpinned item.
Input: `keepPinned` — keep pinned items (the "Clear" buttons) or delete everything ("Delete All…").
Side effects:
- [disk-write] deletes the files of every removed item.
- [schedule] saves `history.json` 0.5 s later.
Calls later:
- `saveNow()`
Invariants:
- INV-Storage-4: `clear(keepPinned: true)` keeps exactly the pinned items, and their files.
Errors:
- [disk-write] failed deletes are ignored; the orphans are removed on the next launch.

### trim()

Purpose: enforces the history size limit. Called after `add`, after unpinning, and when the limit is lowered in Settings.
Side effects:
- [disk-write] deletes the files of every unpinned item beyond `historyLimit()`, oldest first.
- [schedule] saves `history.json` 0.5 s later — only if something was dropped.
Calls later:
- `saveNow()`
Order: [disk-write] → [schedule]
Invariants:
- INV-Storage-3: after `trim()` there are at most `historyLimit()` unpinned items, the newest ones; pinned items are never dropped.
Errors:
- [disk-write] failed deletes are ignored; the orphans are removed on the next launch.

### contents(for:) -> ClipContents?

Purpose: the raw pasteboard data of an item, for pasting it and for the preview.
Output: the data written by the latest `add`, or nil.
Side effects:
- [disk-read] reads `items/<id>.plist`.
Errors:
- [disk-read] a missing or corrupt file returns nil (callers treat the item as broken and remove it).

### fullImage(for:) -> NSImage?

Purpose: the full-size picture for the image preview.
Output: the image from the item's source file if it still exists; otherwise the first image-typed data (PNG, TIFF, …) in the stored contents; otherwise nil.
Side effects:
- [disk-read] reads the source file, then `items/<id>.plist` if needed.
Invariants:
- INV-Storage-10: `fullImage` prefers the source file; when it is gone, it falls back to the image data stored with the item.
Errors:
- [disk-read] unreadable files fall through to the next source; nil when none works.

### purgeCaches()

Purpose: drops all decoded thumbnails from memory (called when the popup is torn down).
Side effects: none

### thumbnail(for:) -> NSImage?

Purpose: the item's thumbnail for the list, cached in memory (at most 60 images).
Side effects:
- [disk-read] reads `items/<id>.png` on a cache miss.
Output: nil when the item has no thumbnail file.

### saveNow()

Purpose: writes the item list to `history.json` right away. Runs 0.5 s after a change and when the app quits.
Side effects:
- [disk-write] writes `history.json` (atomic).
Errors:
- [disk-write] a failed write is ignored; the changes since the last successful save are lost on quit.
