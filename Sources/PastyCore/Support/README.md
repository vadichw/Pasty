# Support

Purpose: low-level helpers that any module may use and that depend on nothing in Pasty.
Depends on: none

## Memory

Purpose: keeps the idle footprint small.

### relieve()

Purpose: returns freed memory pages to the system, so the footprint shrinks after large temporary allocations (images, the popup's view tree, the Settings window).
Side effects:
- [memory] asks malloc to release unused pages.
