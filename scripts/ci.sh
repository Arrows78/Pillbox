#!/bin/zsh
# The same checks as CI: translations, build, then the non-interactive self-test in English and French.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check_l10n.py
./build.sh
build/Pillbox.app/Contents/MacOS/Pillbox --selftest
build/Pillbox.app/Contents/MacOS/Pillbox --selftest -AppleLanguages "(fr)"
