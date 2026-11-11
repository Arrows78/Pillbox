#!/bin/sh
# Generic approval hook for any coding agent whose pre-tool hook can run a command (Codex, Cursor, Gemini CLI...).
#
# Usage:  agent-approval-hook.sh <agent-name>        e.g. agent-approval-hook.sh codex
#
# The agent runs this before a tool call and sends the call's payload on stdin (JSON with the tool name and its
# input, as Claude Code does: "tool_name" and "tool_input"; "tool"/"name" and "input"/"arguments" also work).
# Pillbox shows an island "<agent-name> wants to run <tool>" with Allow / Deny, and the script answers:
#   - allow: prints {"decision":"allow","reason":...} and exits 0, so the call runs;
#   - deny:  prints {"decision":"deny",...}, writes the reason to stderr and exits 2, so the call is blocked
#            (exit 2 is the blocking code of Claude Code hooks; check how your agent reads a blocking hook);
#   - ask:   prints {"decision":"ask"} and exits 0 when nobody answers within two minutes, or when Pillbox is not
#            running. The agent then shows its own prompt.
#
# Setup: turn on Settings > Integrations > Developer API. The script reads the token from the Keychain, like the
# Claude Code hook. Copy the hook entry from Settings > Integrations ("Copy approval hook for another agent") and
# put your agent's name where "my-agent" is. The hook timeout must be above two minutes (130 s in the copied entry).
AGENT="${1:-}"
case "$AGENT" in
  "") echo "usage: agent-approval-hook.sh <agent-name>" >&2; exit 0 ;;
  *[!A-Za-z0-9._\ -]*) echo "agent-approval-hook: the agent name may hold only letters, digits, spaces, dots, dashes and underscores" >&2; exit 0 ;;
esac
TOKEN="$(security find-generic-password -s dev.labs.pillbox.devapi -w 2>/dev/null)"
[ -n "$TOKEN" ] || exit 0
QUERY="$(printf '%s' "$AGENT" | sed 's/ /%20/g')"
REPLY="$(curl -s -m 125 -X POST "http://127.0.0.1:9998/approve?agent=$QUERY" \
  -H "Authorization: Bearer $TOKEN" --data-binary @- 2>/dev/null)" || exit 0
[ -n "$REPLY" ] || exit 0
printf '%s\n' "$REPLY"
case "$REPLY" in
  *'"decision":"deny"'*) echo "Denied from Pillbox" >&2; exit 2 ;;
esac
exit 0
