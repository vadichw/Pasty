#!/bin/bash
# Packs build/Pasty.app into build/Pasty.dmg: open it, drag Pasty to Applications.
# Usage: scripts/make_dmg.sh [version]   (the version goes into the app's Info.plist)
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Pasty.app"
[[ -d "$APP" ]] || { echo "Run ./build.sh first" >&2; exit 1; }

if [[ -n "${1:-}" ]]; then
    VERSION="${1#v}"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
    codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" "$APP" # the plist is part of the signature
fi

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f build/Pasty.dmg
hdiutil create -volname Pasty -srcfolder "$STAGE" -ov -format UDZO -quiet build/Pasty.dmg
echo "Done: build/Pasty.dmg"
