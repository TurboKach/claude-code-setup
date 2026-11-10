#!/usr/bin/env bash
# Plain-bash tests for install.sh's master-model handling and hook
# registration — no framework. Exits
# non-zero on the first failure; prints PASS/FAIL per case. Each case installs
# into its own CLAUDE_HOME under mktemp -d, removed on exit.
set -u

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE="$REPO/settings.example.json"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; }

# install <case> <model or ""> <effort or ""> [flag] → sets $home and $out.
# The live settings get <model> and the master's modelSettings entry (the
# first in the example), its effort replaced by <effort> when given.
install() {
  home="$TMP/$1"
  mkdir -p "$home"
  python3 -c 'import json, sys
ex = json.load(open(sys.argv[1]))
mid, cfg = next(iter(ex["modelSettings"].items()))
d = {"modelSettings": {mid: {"effortLevel": sys.argv[3] or cfg["effortLevel"]}}}
if sys.argv[2]: d["model"] = sys.argv[2]
json.dump(d, open(sys.argv[4], "w"))' "$EXAMPLE" "$2" "$3" "$home/settings.json"
  out="$(CLAUDE_HOME="$home" bash "$REPO/install.sh" ${4:+"$4"} 2>&1)" || fail "$1: install.sh exited non-zero: $out"
}

# setting <python expression over d> → prints it from the case's settings.json
setting() {
  python3 -c 'import json, sys
d = json.load(open(sys.argv[1]))
print(eval(sys.argv[2]))' "$home/settings.json" "$1"
}

REC_MODEL="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["model"])' "$EXAMPLE")"
REC_EFFORT="$(python3 -c 'import json, sys; print(next(iter(json.load(open(sys.argv[1]))["modelSettings"].values()))["effortLevel"])' "$EXAMPLE")"
REC_ID="$(python3 -c 'import json, sys; print(next(iter(json.load(open(sys.argv[1]))["modelSettings"])))' "$EXAMPLE")"
OTHER_EFFORT="$( [ "$REC_EFFORT" = high ] && echo medium || echo high )"

expect_notice() {  # case, model, effort, want (yes|no)
  install "$1" "$2" "$3"
  if printf '%s' "$out" | grep -q 'Recommended master:'; then got=yes; else got=no; fi
  [ "$got" = "$4" ] || fail "$1: notice $got, want $4"
  pass "$1"
}

expect_notice "same model and effort: no notice" "$REC_MODEL" "" no
expect_notice "[1m] suffix only: no notice" "$REC_MODEL[1m]" "" no
expect_notice "[1M] suffix, other casing: no notice" "$REC_MODEL[1M]" "" no
expect_notice "pinned model id: notice" "claude-some-pinned-model" "" yes
expect_notice "[1m] suffix with other effort: notice" "$REC_MODEL[1m]" "$OTHER_EFFORT" yes

expect_model() {  # case, model, want model
  install "$1" "$2" "$OTHER_EFFORT" --master=recommended
  [ "$(setting 'd["model"]')" = "$3" ] || fail "$1: model $(setting 'd["model"]'), want $3"
  [ "$(setting 'd["modelSettings"]["'"$REC_ID"'"]["effortLevel"]')" = "$REC_EFFORT" ] \
    || fail "$1: effort not set to $REC_EFFORT"
  pass "$1"
}

expect_model "recommended keeps [1m]" "$REC_MODEL[1m]" "$REC_MODEL[1m]"
expect_model "recommended keeps [1M] casing" "$REC_MODEL[1M]" "$REC_MODEL[1M]"
expect_model "recommended moves a pinned [1m] model to the alias" "claude-some-pinned-model[1m]" "$REC_MODEL[1m]"
expect_model "recommended replaces a model without [1m]" "claude-some-pinned-model" "$REC_MODEL"
expect_model "recommended sets an unset model" "" "$REC_MODEL"

# Sonnet effort: filled in only where none is saved, never overridden.
SUB_ID=claude-sonnet-5-5
SUB_EFFORT="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["modelSettings"][sys.argv[2]]["effortLevel"])' "$EXAMPLE" "$SUB_ID")"
install "sonnet effort unset: filled in" "$REC_MODEL" ""
[ "$(setting 'd["modelSettings"]["'$SUB_ID'"]["effortLevel"]')" = "$SUB_EFFORT" ] || fail "sonnet effort not filled in"
pass "sonnet effort unset: filled in"
install "sonnet effort unset: no master notice" "$REC_MODEL" ""
printf '%s' "$out" | grep -q 'Recommended master:' && fail "sonnet entry leaked into the master notice"
pass "sonnet effort unset: no master notice"
home="$TMP/sonnet-saved"; mkdir -p "$home"
echo '{"modelSettings": {"'$SUB_ID'": {"effortLevel": "low"}}}' > "$home/settings.json"
CLAUDE_HOME="$home" bash "$REPO/install.sh" --master=recommended >/dev/null 2>&1 || fail "sonnet saved: install failed"
[ "$(setting 'd["modelSettings"]["'$SUB_ID'"]["effortLevel"]')" = low ] || fail "saved sonnet effort was overridden"
pass "sonnet effort saved: never overridden, even by --master=recommended"

# The subagent-no-background hook sits in one "Bash|Monitor" group: a fresh
# install puts it there; an earlier install's "Bash" entry is moved as it is,
# the user's own Bash hooks stay, and a re-run adds no copy.
hook_count() {  # <matcher> → entries in that PreToolUse group that run the hook
  setting 'sum(1 for g in d.get("hooks", {}).get("PreToolUse", []) if g.get("matcher") == "'"$1"'" for e in g.get("hooks", []) if e.get("command", "").endswith("/hooks/subagent-no-background.sh"))'
}
install "hook: fresh install" "$REC_MODEL" ""
[ "$(hook_count 'Bash|Monitor')" = 1 ] && [ "$(hook_count Bash)" = 0 ] || fail "hook: fresh install is not in one Bash|Monitor group"
pass "hook: fresh install registers it for Bash|Monitor"
home="$TMP/hook-upgrade"; mkdir -p "$home"
echo '{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "~/.claude/hooks/subagent-no-background.sh", "timeout": 7}, {"type": "command", "command": "/usr/local/bin/own-hook"}]}]}}' > "$home/settings.json"
CLAUDE_HOME="$home" bash "$REPO/install.sh" >/dev/null 2>&1 || fail "hook upgrade: install failed"
CLAUDE_HOME="$home" bash "$REPO/install.sh" >/dev/null 2>&1 || fail "hook upgrade: re-run failed"
[ "$(hook_count 'Bash|Monitor')" = 1 ] || fail "hook upgrade: not exactly one Bash|Monitor entry"
[ "$(hook_count Bash)" = 0 ] || fail "hook upgrade: still in the Bash group"
[ "$(setting '[e for g in d["hooks"]["PreToolUse"] if g["matcher"] == "Bash|Monitor" for e in g["hooks"]][0]["timeout"]')" = 7 ] || fail "hook upgrade: the entry was not moved as it was"
[ "$(setting '[e["command"] for g in d["hooks"]["PreToolUse"] if g["matcher"] == "Bash" for e in g["hooks"]]')" = "['/usr/local/bin/own-hook']" ] || fail "hook upgrade: the user's own Bash hook was not kept"
pass "hook: upgrade moves the Bash entry, keeps the user's hooks, re-run adds no copy"
home="$TMP/hook-only"; mkdir -p "$home"
echo '{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "~/.claude/hooks/subagent-no-background.sh", "timeout": 5}]}]}}' > "$home/settings.json"
CLAUDE_HOME="$home" bash "$REPO/install.sh" >/dev/null 2>&1 || fail "hook-only: install failed"
[ "$(setting 'sum(1 for g in d["hooks"]["PreToolUse"] if g.get("matcher") == "Bash")')" = 0 ] || fail "hook-only: the emptied Bash group was left behind"
pass "hook: an emptied Bash group is removed"
home="$TMP/hook-own-if"; mkdir -p "$home"
echo '{"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "~/.claude/hooks/subagent-no-background.sh", "timeout": 5, "if": "Bash(git *)"}]}, {"matcher": "Bash|Monitor", "hooks": [{"type": "command", "command": "~/.claude/hooks/subagent-no-background.sh", "timeout": 5}]}]}}' > "$home/settings.json"
CLAUDE_HOME="$home" bash "$REPO/install.sh" >/dev/null 2>&1 || fail "hook-own-if: install failed"
[ "$(hook_count 'Bash|Monitor')" = 2 ] && [ "$(hook_count Bash)" = 0 ] || fail "hook-own-if: a hand-edited entry was lost or not moved"
pass "hook: a hand-edited entry is moved, never dropped"


# The skill-reload hook sits in its own SessionStart group with matcher
# "compact": a fresh install adds it once, a re-run adds no copy, and the
# user's own SessionStart hooks stay.
reload_count() {  # → entries in the SessionStart "compact" group that run the hook
  setting 'sum(1 for g in d.get("hooks", {}).get("SessionStart", []) if g.get("matcher") == "compact" for e in g.get("hooks", []) if e.get("command", "").endswith("/hooks/skill-reload-after-compact.sh"))'
}
install "reload: fresh install" "$REC_MODEL" ""
[ "$(reload_count)" = 1 ] || fail "reload: fresh install does not register the hook once in the compact group"
CLAUDE_HOME="$home" bash "$REPO/install.sh" >/dev/null 2>&1 || fail "reload: re-run failed"
[ "$(reload_count)" = 1 ] || fail "reload: a re-run duplicated the entry"
pass "reload hook: fresh install registers it in a compact group, a re-run adds no copy"
home="$TMP/reload-own"; mkdir -p "$home"
echo '{"hooks": {"SessionStart": [{"matcher": "", "hooks": [{"type": "command", "command": "/usr/local/bin/own-start"}]}]}}' > "$home/settings.json"
CLAUDE_HOME="$home" bash "$REPO/install.sh" >/dev/null 2>&1 || fail "reload-own: install failed"
[ "$(reload_count)" = 1 ] || fail "reload-own: the hook was not registered once"
[ "$(setting '[e["command"] for g in d["hooks"]["SessionStart"] if g["matcher"] == "" for e in g["hooks"] if "own-start" in e["command"]]')" = "['/usr/local/bin/own-start']" ] || fail "reload-own: the user's own SessionStart hook was lost"
pass "reload hook: the user's own SessionStart hooks survive"

echo "all install-master tests passed"
