#!/usr/bin/env bash
# Plain-bash tests for hooks/subagent-no-background.sh — no framework. Exits
# non-zero on the first failure; prints PASS/FAIL per case. Never installed:
# install.sh copies hooks/*.sh only, and that glob does not descend here.
set -u

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/subagent-no-background.sh"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; }

# run <name> <stdin-json> → sets $out and $code
run() {
  out="$(printf '%s' "$2" | bash "$HOOK" 2>/dev/null)"
  code=$?
}

expect_deny() {  # name, stdin, substring the reason must contain
  run "$1" "$2"
  [ "$code" -eq 0 ] || fail "$1: exit code (got $code, want 0)"
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
h = d["hookSpecificOutput"]
assert h["hookEventName"] == "PreToolUse", h
assert h["permissionDecision"] == "deny", h
assert sys.argv[1] in h["permissionDecisionReason"], h["permissionDecisionReason"]
' "$3" || fail "$1: stdout is not a deny JSON containing '$3' (got: $out)"
  pass "$1"
}

expect_allow() {  # name, stdin
  run "$1" "$2"
  [ "$code" -eq 0 ] || fail "$1: exit code (got $code, want 0)"
  [ -z "$out" ] || fail "$1: stdout (expected empty, got: $out)"
  pass "$1"
}

[ -f "$HOOK" ] || fail "hook missing at $HOOK"

# Rule A — run_in_background inside a subagent (agent_id present) is denied.
expect_deny "subagent + run_in_background:true -> deny" \
  '{"tool_name":"Bash","agent_id":"a1","agent_type":"fixer","tool_input":{"command":"xcodebuild test","run_in_background":true}}' \
  "foreground"

expect_allow "subagent + run_in_background:false -> allow" \
  '{"tool_name":"Bash","agent_id":"a1","agent_type":"fixer","tool_input":{"command":"xcodebuild test","run_in_background":false,"timeout":600000}}'

expect_allow "subagent, run_in_background absent -> allow" \
  '{"tool_name":"Bash","agent_id":"a1","tool_input":{"command":"ls"}}'

# The master (no agent_id) keeps run_in_background: the codex run and the full
# suite live there by doctrine.
expect_allow "master + run_in_background:true -> allow" \
  '{"tool_name":"Bash","tool_input":{"command":"codex-challenge.sh a..b","run_in_background":true}}'

# Rule B — a poll loop on the never-written .output.done marker is denied in
# every context; a plain mention of the marker (forensics grep, heredoc) is not.
expect_deny "master until-loop on .output.done -> deny" \
  '{"tool_name":"Bash","tool_input":{"command":"until [ -f /tmp/tasks/bsu9.output.done ]; do sleep 5; done","run_in_background":true}}' \
  "output.done"

expect_deny "subagent foreground while-loop on .output.done -> deny" \
  '{"tool_name":"Bash","agent_id":"a1","tool_input":{"command":"while ! test -f /tmp/tasks/x.output.done; do sleep 2; done","timeout":300000}}' \
  "output.done"

expect_deny "until with negated test on .output.done -> deny" \
  '{"tool_name":"Bash","agent_id":"a1","tool_input":{"command":"until [ ! -f /tmp/tasks/x.output.done ]; do sleep 1; done"}}' \
  "output.done"

expect_allow "grep for the marker string -> allow" \
  '{"tool_name":"Bash","tool_input":{"command":"grep -rn output.done ~/.claude/projects | head"}}'

expect_allow "commit message mentioning until + output.done -> allow" \
  '{"tool_name":"Bash","agent_id":"a1","tool_input":{"command":"git commit -m \"hook: deny until/while polls on the .output.done marker\""}}'

# Fail-open: never block on anything the hook does not understand.
expect_allow "tool_name Read -> allow" \
  '{"tool_name":"Read","agent_id":"a1","tool_input":{"file_path":"/tmp/x"}}'

expect_allow "empty stdin -> allow" ''

expect_allow "malformed JSON -> allow" '{"tool_name":'

echo "all cases passed"
