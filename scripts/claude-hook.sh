#!/bin/sh
# Claude Code PreToolUse hook: asks Pillbox to show an Allow / Deny island.
# Prints nothing (so Claude Code falls back to its normal prompt) when Pillbox or its API is not running.
TOKEN="$(security find-generic-password -s dev.labs.pillbox.devapi -w 2>/dev/null)"
[ -n "$TOKEN" ] || exit 0
curl -s -m 125 -X POST "http://127.0.0.1:9998/approve" \
  -H "Authorization: Bearer $TOKEN" --data-binary @- 2>/dev/null || true
