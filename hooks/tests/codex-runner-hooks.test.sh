#!/usr/bin/env bash
# Plain-bash tests for hooks/codex-runner-hooks.sh — no framework. Exits
# non-zero on the first failure; prints PASS/FAIL per case.
set -u

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/codex-runner-hooks.sh"

fail() {
  echo "FAIL: $1"
  exit 1
}

pass() {
  echo "PASS: $1"
}

# 1. pre-bash with run_in_background true -> exit 2, stderr non-empty
err_file="$(mktemp)"
out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"run_in_background":true,"command":"sleep 1"}}' \
  | bash "$HOOK" pre-bash 2>"$err_file")"
code=$?
[ "$code" -eq 2 ] || fail "pre-bash run_in_background:true exit code (got $code, want 2)"
[ -s "$err_file" ] || fail "pre-bash run_in_background:true stderr (expected non-empty)"
rm -f "$err_file"
pass "pre-bash run_in_background:true -> exit 2, stderr non-empty"

# 2. pre-bash with run_in_background false -> exit 0, no output
err_file="$(mktemp)"
out="$(printf '%s' '{"tool_name":"Bash","tool_input":{"run_in_background":false,"command":"ls"}}' \
  | bash "$HOOK" pre-bash 2>"$err_file")"
code=$?
[ "$code" -eq 0 ] || fail "pre-bash run_in_background:false exit code (got $code, want 0)"
[ -z "$out" ] || fail "pre-bash run_in_background:false stdout (expected empty, got: $out)"
[ ! -s "$err_file" ] || fail "pre-bash run_in_background:false stderr (expected empty)"
rm -f "$err_file"
pass "pre-bash run_in_background:false -> exit 0, no output"

# 3. pre-bash with tool_name Read -> exit 0
out="$(printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' \
  | bash "$HOOK" pre-bash 2>/dev/null)"
code=$?
[ "$code" -eq 0 ] || fail "pre-bash tool_name:Read exit code (got $code, want 0)"
pass "pre-bash tool_name:Read -> exit 0"

# 4. pre-bash with empty stdin -> exit 0
out="$(printf '' | bash "$HOOK" pre-bash 2>/dev/null)"
code=$?
[ "$code" -eq 0 ] || fail "pre-bash empty stdin exit code (got $code, want 0)"
pass "pre-bash empty stdin -> exit 0"

# 5. stop with no codex process -> exit 0, empty stdout
out="$(printf '%s' '{}' | bash "$HOOK" stop 2>/dev/null)"
code=$?
[ "$code" -eq 0 ] || fail "stop (no process) exit code (got $code, want 0)"
[ -z "$out" ] || fail "stop (no process) stdout (expected empty, got: $out)"
pass "stop (no codex process) -> exit 0, empty stdout"

# 6. stop with a fake `codex exec` process alive -> exit 0, stdout is JSON with decision == block
FAKE_PID=""
cleanup_fake() {
  if [ -n "$FAKE_PID" ]; then
    kill "$FAKE_PID" 2>/dev/null
    wait "$FAKE_PID" 2>/dev/null
  fi
}
trap cleanup_fake EXIT

bash -c 'exec -a "codex exec fake-for-test" sleep 30' &
FAKE_PID=$!
sleep 0.5

out="$(printf '%s' '{}' | bash "$HOOK" stop 2>/dev/null)"
code=$?
[ "$code" -eq 0 ] || fail "stop (fake codex running) exit code (got $code, want 0)"
printf '%s' "$out" | python3 -c '
import json, sys
data = json.load(sys.stdin)
decision = data.get("decision")
assert decision == "block", "decision was %r" % (decision,)
' || fail "stop (fake codex running) stdout did not parse as JSON with decision==block (got: $out)"
pass "stop (fake codex exec alive) -> exit 0, stdout JSON decision==block"

cleanup_fake
trap - EXIT
FAKE_PID=""

# 7. stop with empty stdin and no process -> exit 0
out="$(printf '' | bash "$HOOK" stop 2>/dev/null)"
code=$?
[ "$code" -eq 0 ] || fail "stop (empty stdin, no process) exit code (got $code, want 0)"
pass "stop (empty stdin, no process) -> exit 0"

echo "ALL PASS"
