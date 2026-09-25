#!/usr/bin/env bash
# Plain-bash tests for hooks/session-name.sh — no framework. Exits non-zero
# on the first failure; prints PASS/FAIL per case. Temp git repos under
# mktemp -d, removed on exit.
set -u

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/session-name.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; }

# repo <name> → creates an empty git repo under $TMP, prints its path
repo() {
  mkdir -p "$TMP/$1" && git -C "$TMP/$1" init -q && printf '%s' "$TMP/$1"
}

# input <source> <cwd> [session_title]
input() {
  python3 -c 'import json, sys
d = {"hook_event_name": "SessionStart", "source": sys.argv[1], "cwd": sys.argv[2]}
if len(sys.argv) > 3: d["session_title"] = sys.argv[3]
print(json.dumps(d))' "$@"
}

# run <stdin> → sets $out and $code
run() {
  out="$(printf '%s' "$1" | bash "$HOOK" 2>/dev/null)"
  code=$?
}

expect_name() {  # case name, stdin, expected title
  run "$2"
  [ "$code" -eq 0 ] || fail "$1: exit code (got $code, want 0)"
  printf '%s' "$out" | python3 -c '
import json, sys
h = json.load(sys.stdin)["hookSpecificOutput"]
assert h == {"hookEventName": "SessionStart", "sessionTitle": sys.argv[1]}, h
' "$3" || fail "$1: stdout is not a sessionTitle JSON for '$3' (got: $out)"
  pass "$1"
}

expect_silent() {  # case name, stdin
  run "$2"
  [ "$code" -eq 0 ] || fail "$1: exit code (got $code, want 0)"
  [ -z "$out" ] || fail "$1: stdout (expected empty, got: $out)"
  pass "$1"
}

[ -f "$HOOK" ] || fail "hook missing at $HOOK"

r="$(repo plain)"; printf '# Proj\n\nSession name: acme-ios\n' > "$r/CLAUDE.md"
expect_name "line present -> name" "$(input startup "$r")" "acme-ios"
expect_name "source resume -> name" "$(input resume "$r")" "acme-ios"
expect_name "source fork -> name" "$(input fork "$r")" "acme-ios"

r="$(repo ticks)"; printf 'Session name:   `acme_api`  \n' > "$r/CLAUDE.md"
expect_name "backticked name, extra whitespace -> name" "$(input startup "$r")" "acme_api"

r="$(repo dotclaude)"; mkdir -p "$r/.claude"; printf 'Session name: dot-claude\n' > "$r/.claude/CLAUDE.md"
expect_name ".claude/CLAUDE.md location -> name" "$(input startup "$r")" "dot-claude"

r="$(repo sub)"; printf 'Session name: from-root\n' > "$r/CLAUDE.md"; mkdir -p "$r/src/deep"
expect_name "cwd in a subdirectory -> root name" "$(input startup "$r/src/deep")" "from-root"

r="$(repo first)"; printf 'Session name: first-one\nSession name: second-one\n' > "$r/CLAUDE.md"
expect_name "first matching line wins" "$(input startup "$r")" "first-one"

d="$TMP/nogit"; mkdir -p "$d"; printf 'Session name: no-git\n' > "$d/CLAUDE.md"
expect_name "not a git repo -> cwd is the root" "$(input startup "$d")" "no-git"

r="$(repo titled)"; printf 'Session name: repo-name\n' > "$r/CLAUDE.md"
expect_silent "session_title already set -> silent" "$(input startup "$r" "my own name")"
expect_silent "source clear -> silent" "$(input clear "$r")"
expect_silent "source compact -> silent" "$(input compact "$r")"

r="$(repo none)"
expect_silent "no CLAUDE.md -> silent" "$(input startup "$r")"

r="$(repo noline)"; printf '# Proj\n\nThe session name: nope\n  Session name: indented\n' > "$r/CLAUDE.md"
expect_silent "CLAUDE.md without the line -> silent" "$(input startup "$r")"

r="$(repo spaced)"; printf 'Session name: acme ios\n' > "$r/CLAUDE.md"
expect_silent "invalid name (space) -> silent" "$(input startup "$r")"

r="$(repo badchar)"; printf 'Session name: `acme.ios`\n' > "$r/CLAUDE.md"
expect_silent "invalid name (dot) -> silent" "$(input startup "$r")"

r="$(repo empty)"; printf 'Session name:\n' > "$r/CLAUDE.md"
expect_silent "empty name -> silent" "$(input startup "$r")"

expect_silent "malformed stdin -> silent" '{"source":'
expect_silent "empty stdin -> silent" ''

r="$(repo symlinked)"; printf 'Session name: via-link\n' > "$r/AGENTS.md"; ln -s AGENTS.md "$r/CLAUDE.md"
expect_name "CLAUDE.md symlink to a regular file -> name" "$(input startup "$r")" "via-link"

# A module in the hook's cwd must never be imported: python3 -c would put
# the cwd first on sys.path and run this json.py on every session start.
r="$(repo shadow)"; printf 'Session name: shadowed\n' > "$r/CLAUDE.md"
printf 'open(%s, "w").close()\n' "'$TMP/shadow-marker'" > "$r/json.py"
stdin="$(input startup "$r")"
out="$(cd "$r" && printf '%s' "$stdin" | bash "$HOOK" 2>/dev/null)"; code=$?
[ ! -e "$TMP/shadow-marker" ] || fail "json.py in cwd -> not imported: marker written"
[ "$code" -eq 0 ] && [ -n "$out" ] || fail "json.py in cwd -> still named (got: $out)"
pass "json.py in cwd -> not imported, still named"

# expect_bounded <case> <stdin>: the hook must finish within 3s, silent, exit
# 0. Run in the background and killed (with its python child) on overrun, so
# a red run fails instead of hanging the suite.
expect_bounded() {
  printf '%s' "$2" | bash "$HOOK" > "$TMP/out" 2>/dev/null &
  pid=$!
  for _ in $(seq 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$pid" 2>/dev/null; then
    pkill -P "$pid"; kill "$pid"; wait "$pid" 2>/dev/null
    fail "$1: still running after 3s"
  fi
  wait "$pid"; code=$?
  [ "$code" -eq 0 ] || fail "$1: exit code (got $code, want 0)"
  [ ! -s "$TMP/out" ] || fail "$1: stdout (expected empty, got: $(cat "$TMP/out"))"
  pass "$1"
}

r="$(repo devzero)"; ln -s /dev/zero "$r/CLAUDE.md"
expect_bounded "CLAUDE.md -> /dev/zero -> silent, bounded" "$(input startup "$r")"

r="$(repo fifo)"; mkfifo "$r/CLAUDE.md"
expect_bounded "CLAUDE.md is a FIFO -> silent, bounded" "$(input startup "$r")"

echo "all cases passed"
