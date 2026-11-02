#!/bin/bash
# Checks that every module README in Sources/PastyCore matches the code (see docs/DOC_FORMAT.md).
#   scripts/check_docs.sh              check
#   scripts/check_docs.sh --fix        regenerate the module graph in docs/ARCHITECTURE.md, then check
#   scripts/check_docs.sh --base REF   also warn about modules whose code changed since REF but README did not
#   scripts/check_docs.sh --facts      print the facts extracted from code (JSON)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build --package-path Tools/pasty-docs -c release >/dev/null
TOOL="Tools/pasty-docs/.build/release/pasty-docs"

case "${1:-}" in
    --fix)   "$TOOL" graph --root . --write; exec "$TOOL" check --root . ;;
    --facts) exec "$TOOL" facts --root . ;;
    --base)  exec "$TOOL" check --root . --base "$2" ;;
    *)       exec "$TOOL" check --root . ;;
esac
