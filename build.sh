#!/bin/zsh
# Builds Pillbox into build/Pillbox.app (ad-hoc signed unless PILLBOX_SIGN_IDENTITY is set), then installs it
# into /Applications and relaunches it, unless PILLBOX_NO_INSTALL is set or this runs in CI.
# PILLBOX_UNIVERSAL=1 builds for Apple Silicon and Intel (used by the release workflow).
set -euo pipefail
cd "$(dirname "$0")"

# The native build system links package products (Lottie) statically; the default one makes a Lottie.framework
# whose classes are also linked in, and that framework is not in the app bundle.
build_arch() {  # $1 = arm64 | x86_64 (empty = host); prints only the bin path on stdout
  local flags=(-c release --build-system native)
  [ -n "${1:-}" ] && flags+=(--triple "$1-apple-macosx")
  local log; log="$(mktemp)"
  if ! swift build "${flags[@]}" > "$log" 2>&1; then
    cat "$log" >&2; rm -f "$log"
    echo "error: swift build failed" >&2; exit 1   # a failed build must stop the script, never be hidden
  fi
  grep -E "warning:|error:" "$log" | grep -v -E "deprecated|repeated" >&2 || true
  rm -f "$log"
  swift build "${flags[@]}" --show-bin-path 2>/dev/null
}

APP=build/Pillbox.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [ "${PILLBOX_UNIVERSAL:-0}" = 1 ]; then
  ARM_DIR="$(build_arch arm64 | tail -1)"; X86_DIR="$(build_arch x86_64 | tail -1)"
  lipo -create "$ARM_DIR/Pillbox" "$X86_DIR/Pillbox" -output "$APP/Contents/MacOS/Pillbox"
  BINDIR="$ARM_DIR"
else
  BINDIR="$(build_arch | tail -1)"
  cp "$BINDIR/Pillbox" "$APP/Contents/MacOS/Pillbox"
fi
# Resource bundles produced by packages (Lottie_Lottie.bundle) sit next to the executable's resources.
for b in "$BINDIR"/*.bundle; do [ -d "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
for lp in Resources/*.lproj; do [ -d "$lp" ] && cp -R "$lp" "$APP/Contents/Resources/"; done
for h in claude-hook claude-stop-hook; do [ -f "scripts/$h.sh" ] && cp "scripts/$h.sh" "$APP/Contents/Resources/$h.sh"; done

# A stable signing identity keeps macOS privacy permissions across rebuilds; an ad-hoc signature changes on
# every build and makes macOS forget them.
IDENTITY="${PILLBOX_SIGN_IDENTITY:-Pillbox Local Signing}"
# On a CI runner the imported self-signed identity is not "trusted", so it is only listed without -v.
if { security find-identity -v -p codesigning; [ -n "${CI:-}" ] && security find-identity -p codesigning; true; } | grep -qF "$IDENTITY"; then
  SIGN="$IDENTITY"
else
  SIGN="-"
  echo "warning: signing identity '$IDENTITY' not found, falling back to ad-hoc (permissions will reset on every build)" >&2
fi
codesign --force --deep --sign "$SIGN" "$APP"
echo "Built $APP"

if [ -z "${CI:-}" ] && [ -z "${PILLBOX_NO_INSTALL:-}" ]; then
  ./install.sh --no-build
fi
