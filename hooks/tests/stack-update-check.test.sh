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
SRC="TurboKach/claude-code-setup@master"
notice() { echo "claude-code-setup: $1 (installed aaaaaaa → remote bbbbbbb) — run /stack-update"; }
NOTICE_B="$(notice "6 new changes")"
DRIFT="claude-code-setup: Claude Code 9.9.9 is running, doctrine last validated against 1.0.0 — diff the changelog 1.0.0 → 9.9.9 before the next pipeline change"

# Fakes: curl logs each URL; the SHA call prints $FAKE_REMOTE (empty =
# offline), the compare call a trimmed compare body with $FAKE_AHEAD (empty =
# 404/timeout). claude prints $FAKE_CC.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
url="${*: -1}"
echo "$url" >> "$FAKE_LOG/curl-called"
case "$url" in
  */compare/*)
    [ -n "$FAKE_AHEAD" ] || exit 22
    printf '{"status": "ahead", "ahead_by": %s, "behind_by": 0, "files": [{"status": "modified"}]}' "$FAKE_AHEAD" ;;
  *)
    [ -n "$FAKE_REMOTE" ] || exit 7
    printf '%s' "$FAKE_REMOTE" ;;
esac
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

# run <fake remote> [fake cc version] [fake ahead_by, default 6] → sets $out and $code
run() {
  rm -f "$TMP/curl-called"
  out="$(CLAUDE_HOME="$HOME_DIR" PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP" \
    FAKE_REMOTE="$1" FAKE_CC="${2:-1.0.0}" FAKE_AHEAD="${3-6}" bash "$HOOK" 2>/dev/null)"
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
compare_called() { grep -q /compare/ "$TMP/curl-called" 2>/dev/null; }

[ -f "$HOOK" ] || fail "hook missing at $HOOK"

fresh ""
run "$B"; expect_silent "no installed stamp"; curl_called && fail "no stamp: curl called"
pass "no installed stamp -> silent, no network"

fresh "$A"; touch "$S/disabled"
run "$B"; expect_silent "disabled"; curl_called && fail "disabled: curl called"
pass "disabled -> silent, no network"

fresh "$A"
run "$A"; expect_silent "up to date"
[ "$(cat "$S/remote")" = "$A $SRC $A -" ] || fail "up to date: remote cache not written"
compare_called && fail "up to date: compare called"
pass "poll, up to date -> silent, cache written, no compare call"

fresh "$A"
run "$B"; expect_notice "update" "$NOTICE_B" "$NOTICE_B"
[ "$(cat "$S/remote")" = "$A $SRC $B 6" ] || fail "update: remote cache not written"
grep -q "/compare/$A...$B?" "$TMP/curl-called" || fail "update: compare not called for installed...remote"
pass "poll, update available -> JSON notice with count to user and Claude"

run "$C"; expect_notice "replay" "$NOTICE_B" "$NOTICE_B"
curl_called && fail "replay: curl called inside the 24h window"
pass "second start within 24h -> same notice replayed, no network"

echo "$C" > "$S/installed"
run "$C"; expect_silent "replay after update"
curl_called && fail "replay after update: curl called inside the 24h window"
pass "installed moved past the polled SHA -> no stale replay"

fresh "$A"
run "$B" 1.0.0 1; expect_notice "one change" "$(notice "1 new change")" "$(notice "1 new change")"
pass "one commit behind -> singular"

fresh "$A"
run "$B" 1.0.0 ""; expect_notice "no count" "$(notice "update available")" "$(notice "update available")"
[ "$(cat "$S/remote")" = "$A $SRC $B -" ] || fail "no count: SHA not cached without count"
pass "compare fails -> notice without count, SHA still cached"

fresh "$A"
run "$B" 1.0.0 0; expect_silent "install ahead"
pass "remote has nothing the install lacks (ahead_by 0) -> silent"

fresh "$A"; echo "$A $SRC $B 6" > "$S/remote"; echo 0 > "$S/last-check"
run ""; expect_notice "offline poll" "$NOTICE_B" "$NOTICE_B"
[ "$(cat "$S/remote")" = "$A $SRC $B 6" ] || fail "offline: known update overwritten"
echo 0 > "$S/last-check"
run ""; expect_notice "offline again, >24h later" "$NOTICE_B" "$NOTICE_B"
pass "failed poll -> replays the known update, every time"

fresh "$A"; echo "$(date +%s)" > "$S/last-check"; echo "$A someone/fork@main $B 6" > "$S/remote"
run "$B"; expect_silent "other source"
pass "cache from another repo/branch -> no replay"

fresh "$A"; echo "$(date +%s)" > "$S/last-check"
run "$B"; expect_silent "no cache"
pass "within 24h, no remote cache -> silent"

fresh "$A"; echo "$(date +%s)" > "$S/last-check"; echo "$A $B" > "$S/remote"
run "$B"; expect_silent "old two-field cache"
fresh "$A"; echo "$(date +%s)" > "$S/last-check"; echo "garbage" > "$S/remote"
run "$B"; expect_silent "corrupt cache"
pass "within 24h, old-format or corrupt remote cache -> silent"

fresh "$A"; echo 'Новых изменений: {n} ({from} → {to}) — запустите /stack-update' > "$S/notice"
run "$B"; expect_notice "localized" \
  "claude-code-setup: Новых изменений: 6 (aaaaaaa → bbbbbbb) — запустите /stack-update" "$NOTICE_B"
pass "notice template -> user's copy in their language, Claude's copy in English"

fresh "$A"; printf '%s\n' 'Say "hi" \ {n}	tab' 'second line ignored' > "$S/notice"
run "$B" 1.0.0 ""; expect_notice "template escaping" 'claude-code-setup: Say "hi" \ ?tab' "$(notice "update available")"
pass "template with quotes, backslash, control chars -> valid JSON; unknown count -> ?"

fresh "$A"; echo "$(date +%s)" > "$S/last-check"; echo "$A $SRC $B 5\"x" > "$S/remote"
run "$B"; expect_notice "corrupt count" "$(notice "update available")" "$(notice "update available")"
pass "corrupt cached count -> generic notice, valid JSON"

fresh "$A"; echo "$A $SRC $B 6" > "$S/remote"; echo 0 > "$S/last-check"; chmod 444 "$S/last-check"
run "$B"; expect_notice "stamp unwritable" "$NOTICE_B" "$NOTICE_B"
curl_called && fail "stamp unwritable: curl called"
chmod 644 "$S/last-check"
pass "last-check unwritable -> no network, known update still replayed"

fresh "$A"; echo 1.0.0 > "$S/validated-cc-version"
run "$B" 9.9.9; expect_notice "drift + update" "$NOTICE_B" "$DRIFT
$NOTICE_B"
pass "drift + update -> one JSON, drift line in Claude's context only"

fresh "$A"; echo 1.0.0 > "$S/validated-cc-version"
run "$A" 9.9.9
[ "$out" = "$DRIFT" ] || fail "drift only: expected plain drift line, got: $out"
pass "drift only -> plain line to Claude"

echo "all stack-update-check tests passed"
