# Working on Pasty

Pasty is described in plain text next to the code: `Sources/PastyCore/<Module>/README.md`.
Reviewers read those READMEs **instead of the code**, so they must say exactly what the code
does. The format and every rule are in `docs/DOC_FORMAT.md`; the overview is `docs/ARCHITECTURE.md`.

## Rules

1. **Code and README change together.** Every change to a module's code updates that module's
   README in the same commit: new or changed members, side effects, uses, callbacks, order,
   invariants, error behaviour. Describe observable behaviour, not implementation.
2. **Run the check before you finish.** `scripts/check_docs.sh` must print "Docs match the code";
   `swift test` must pass. If the module graph changed, run `scripts/check_docs.sh --fix`.
3. **Never edit the generated block** in `docs/ARCHITECTURE.md` by hand.
4. **Invariants need tests.** A new `INV-<Module>-<n>` needs a test in `Tests/PastyCoreTests`
   whose name or comment contains the ID. Don't reuse or renumber IDs; retire one by deleting it
   together with its test.
5. **New kind of side effect → new rule first.** If code touches the outside world in a way
   `Tools/pasty-docs/Sources/pasty-docs/EffectRules.swift` doesn't detect, add a rule (and a row
   to the category table in `docs/DOC_FORMAT.md`) before documenting it.
6. **List your assumptions.** When the request leaves something open (an error case, a limit, an
   order), say what you assumed in your final message, so the reviewer can move the accepted ones
   into the README.
7. **Independent verification.** For non-trivial changes, ask a separate agent with no context of
   the task to read the changed code and its README and report every sentence the code does not
   back up. The mechanical check covers effects and links between modules, not the meaning of the
   prose.

## Layout

- `Sources/Pasty/main.swift` — entry point, calls `PastyApp.run()`.
- `Sources/PastyCore/<Module>/` — all logic, one folder per module, each with its README.
- `Tests/PastyCoreTests/` — Swift Testing; tests touching `Prefs` go in the serialized `UsesPrefs` suite.
- `Tools/pasty-docs/` — the fact extractor and checker (separate package; the app has no dependencies).

## Commands

```bash
swift build                      # build
swift test                       # tests
scripts/check_docs.sh            # READMEs vs code
scripts/check_docs.sh --fix      # regenerate the module graph, then check
scripts/check_docs.sh --facts    # what the extractor sees, as JSON
./build.sh [--install]           # build Pasty.app (and install it)
```
