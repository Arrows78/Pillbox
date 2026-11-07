#!/bin/zsh
# Builds Pillbox and wraps it into build/Pillbox.app (ad-hoc signed unless PILLBOX_SIGN_IDENTITY is set).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Pillbox"
APP=build/Pillbox.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pillbox"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for lp in Resources/*.lproj; do [ -d "$lp" ] && cp -R "$lp" "$APP/Contents/Resources/"; done
[ -f scripts/claude-hook.sh ] && cp scripts/claude-hook.sh "$APP/Contents/Resources/claude-hook.sh"
codesign --force --deep --sign "${PILLBOX_SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
