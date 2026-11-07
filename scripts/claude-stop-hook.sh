#!/bin/sh
# Claude Code Stop hook: asks Pillbox to show how many tokens the turn that just ended used.
# Prints nothing and never blocks Claude Code, whether or not Pillbox is running.
TOKEN="$(defaults read dev.labs.pillbox devAPIToken 2>/dev/null)"
[ -n "$TOKEN" ] || exit 0
curl -s -m 5 -X POST "http://127.0.0.1:9998/turn" -H "Authorization: Bearer $TOKEN" --data-binary @- >/dev/null 2>&1 || true
