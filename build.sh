#!/bin/zsh
# Builds Pillbox and wraps it into build/Pillbox.app (ad-hoc signed unless PILLBOX_SIGN_IDENTITY is set).
set -euo pipefail
cd "$(dirname "$0")"
# The native build system links package products (Lottie) statically; the default one makes a Lottie.framework
# whose classes are also linked in, and that framework is not in the app bundle.
SWIFT_FLAGS=(-c release --build-system native)
swift build "${SWIFT_FLAGS[@]}" 2>&1 | grep -v -E "deprecated|repeated" || true
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path 2>/dev/null)/Pillbox"
APP=build/Pillbox.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Pillbox"
BINDIR="$(dirname "$BIN")"
# Resource bundles produced by packages (Lottie_Lottie.bundle) sit next to the executable's resources.
for b in "$BINDIR"/*.bundle; do [ -d "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for lp in Resources/*.lproj; do [ -d "$lp" ] && cp -R "$lp" "$APP/Contents/Resources/"; done
[ -f scripts/claude-hook.sh ] && cp scripts/claude-hook.sh "$APP/Contents/Resources/claude-hook.sh"
codesign --force --deep --sign "${PILLBOX_SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
