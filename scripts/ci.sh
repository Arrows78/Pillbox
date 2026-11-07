#!/bin/zsh
# The same checks as CI: build the app, then run the non-interactive self-test.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh
build/Pillbox.app/Contents/MacOS/Pillbox --selftest
