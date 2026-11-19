#!/bin/bash
# Build "build/Ducky Lights.app": release binary, icon, Info.plist, ad-hoc signature, no sandbox.
#   scripts/build-app.sh            # build only
#   scripts/build-app.sh --install  # also stop running copies and install to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=0.3.0
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 1)
APP="build/Ducky Lights.app"

swift build -c release --product DuckyLights
BIN="$(swift build -c release --show-bin-path)/DuckyLights"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DuckyLights"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Packaging/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --sign - --timestamp=none "$APP"
echo "built $APP ($VERSION, build $BUILD)"

if [[ "${1:-}" == "--install" ]]; then
    # Two copies driving the keyboard at once would fight. SIGTERM makes a running copy
    # hand the keyboard back to the firmware before it exits.
    if pkill -TERM -x DuckyLights; then
        for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x DuckyLights >/dev/null || break; sleep 0.3; done
    fi
    DEST="/Applications/Ducky Lights.app"
    rm -rf "$DEST"
    ditto "$APP" "$DEST"
    echo "installed $DEST"
    open "$DEST"
fi
