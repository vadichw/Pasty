#!/bin/bash
# Builds Pasty.app into ./build. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Pasty"

APP="build/Pasty.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pasty"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns ]]; then
    swift scripts/make_icon.swift build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Sign with a stable identity if one exists, so macOS keeps the Accessibility permission
# across rebuilds (ad-hoc signatures change with every build). See scripts/make_cert.sh.
IDENTITY="${CODESIGN_IDENTITY:-Pasty Self-Signed}"
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
    echo "Signed with: $IDENTITY"
else
    codesign --force --deep --sign - "$APP"
    echo "Signed ad-hoc (run scripts/make_cert.sh once to keep permissions across rebuilds)"
fi
echo "Done: $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Pasty || true
    rm -rf /Applications/Pasty.app
    cp -R "$APP" /Applications/
    open /Applications/Pasty.app
    echo "Installed to /Applications and launched"
fi
