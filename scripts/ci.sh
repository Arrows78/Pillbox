#!/bin/sh
# Local CI: release tool tests, release files check, translations, app build, then the non-interactive self-test
# in English, French, Spanish and German. CI runs this same script.
set -eu
cd "$(dirname "$0")/.."
python3 -B -m unittest discover -s scripts/tests -q
python3 -B scripts/release.py check
python3 -B scripts/check_l10n.py
# Never install into /Applications from a check.
PILLBOX_NO_INSTALL=1 ./build.sh
build/Pillbox.app/Contents/MacOS/Pillbox --selftest
for lang in fr es de; do build/Pillbox.app/Contents/MacOS/Pillbox --selftest -AppleLanguages "($lang)"; done
echo "CI OK"
