#!/usr/bin/env bash
# Plain-bash tests for hooks/stack-update-check.sh — no framework. Exits
# non-zero on the first failure; prints PASS/FAIL per case. The network and
# `claude --version` are fakes on PATH; state lives under mktemp -d.
set -u

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/stack-update-check.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; }

A=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
C=cccccccccccccccccccccccccccccccccccccccc
NOTICE_B="claude-code-setup: update available (installed aaaaaaa → remote bbbbbbb) — run /stack-update"
DRIFT="claude-code-setup: Claude Code 9.9.9 is running, doctrine last validated against 1.0.0 — diff the changelog 1.0.0 → 9.9.9 before the next pipeline change"

# Fakes: curl prints $FAKE_REMOTE (empty = offline) and records the call;
# claude prints $FAKE_CC.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
touch "$FAKE_LOG/curl-called"
[ -n "$FAKE_REMOTE" ] || exit 7
printf '%s' "$FAKE_REMOTE"
EOF
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "$FAKE_CC (Claude Code)"
EOF
chmod +x "$TMP/bin/curl" "$TMP/bin/claude"

# fresh <installed> → new empty CLAUDE_HOME with that stamp; sets $HOME_DIR, $S
fresh() {
  HOME_DIR="$(mktemp -d "$TMP/home.XXXX")"
  S="$HOME_DIR/.claude-code-setup"
  mkdir -p "$S"
  [ -n "$1" ] && echo "$1" > "$S/installed"
}

# run <fake remote> [fake cc version] → sets $out and $code
run() {
  rm -f "$TMP/curl-called"
  out="$(CLAUDE_HOME="$HOME_DIR" PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP" \
    FAKE_REMOTE="$1" FAKE_CC="${2:-1.0.0}" bash "$HOOK" 2>/dev/null)"
  code=$?
  [ "$code" -eq 0 ] || fail "exit code $code, want 0"
}

expect_silent() { [ -z "$out" ] || fail "$1: expected no stdout, got: $out"; }

# expect_notice <case> <systemMessage> <additionalContext>
expect_notice() {
  printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d == {"systemMessage": sys.argv[1], "hookSpecificOutput": {
    "hookEventName": "SessionStart", "additionalContext": sys.argv[2]}}, d
' "$2" "$3" || fail "$1: stdout is not the expected notice JSON (got: $out)"
}

curl_called() { [ -e "$TMP/curl-called" ]; }

[ -f "$HOOK" ] || fail "hook missing at $HOOK"

fresh ""
run "$B"; expect_silent "no installed stamp"; curl_called && fail "no stamp: curl called"
pass "no installed stamp -> silent, no network"

fresh "$A"; touch "$S/disabled"
run "$B"; expect_silent "disabled"; curl_called && fail "disabled: curl called"
pass "disabled -> silent, no network"

fresh "$A"
run "$A"; expect_silent "up to date"
[ "$(cat "$S/remote")" = "$A $A" ] || fail "up to date: remote cache not written"
pass "poll, up to date -> silent, cache written"

fresh "$A"
run "$B"; expect_notice "update" "$NOTICE_B" "$NOTICE_B"
[ "$(cat "$S/remote")" = "$A $B" ] || fail "update: remote cache not written"
pass "poll, update available -> JSON notice to user and Claude"

run "$C"; expect_notice "replay" "$NOTICE_B" "$NOTICE_B"
curl_called && fail "replay: curl called inside the 24h window"
pass "second start within 24h -> same notice replayed, no network"

echo "$C" > "$S/installed"
run "$C"; expect_silent "replay after update"
curl_called && fail "replay after update: curl called inside the 24h window"
pass "installed moved past the polled SHA -> no stale replay"

fresh "$A"; echo "$A $B" > "$S/remote"; echo 0 > "$S/last-check"
run ""; expect_silent "offline poll"
[ "$(cat "$S/remote")" = "$A $B" ] || fail "offline: known update overwritten"
run ""; expect_notice "offline then replay" "$NOTICE_B" "$NOTICE_B"
pass "offline poll -> silent, keeps the known update for replay"

fresh "$A"; echo "$(date +%s)" > "$S/last-check"
run "$B"; expect_silent "no cache"
pass "within 24h, no remote cache -> silent"

fresh "$A"; echo "$(date +%s)" > "$S/last-check"; echo "garbage" > "$S/remote"
run "$B"; expect_silent "corrupt cache"
pass "within 24h, corrupt remote cache -> silent"

fresh "$A"; echo 1.0.0 > "$S/validated-cc-version"
run "$B" 9.9.9; expect_notice "drift + update" "$NOTICE_B" "$DRIFT
$NOTICE_B"
pass "drift + update -> one JSON, drift line in Claude's context only"

fresh "$A"; echo 1.0.0 > "$S/validated-cc-version"
run "$A" 9.9.9
[ "$out" = "$DRIFT" ] || fail "drift only: expected plain drift line, got: $out"
pass "drift only -> plain line to Claude"

echo "all stack-update-check tests passed"
