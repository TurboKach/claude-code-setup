#!/usr/bin/env bash
# Plain-bash tests for hooks/skill-reload-after-compact.sh — no framework. Exits
# non-zero on the first failure; prints PASS/FAIL per case. Temp transcripts
# under mktemp -d, removed on exit. Never installed: install.sh copies
# hooks/*.sh only, and that glob does not descend here.
set -u

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/skill-reload-after-compact.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $1"; }

LINE='This session loaded the feature-workflow skill before the compaction, and compaction can drop its text: invoke the skill again before the next pipeline step.'

# run <stdin> → sets $out and $code
run() {
  out="$(printf '%s' "$1" | "$BASH" "$HOOK" 2>/dev/null)"
  code=$?
}

expect_line() {  # case name, stdin
  run "$2"
  [ "$code" -eq 0 ] || fail "$1: exit code (got $code, want 0)"
  [ "$out" = "$LINE" ] || fail "$1: stdout (expected the reminder line, got: $out)"
  pass "$1"
}

expect_silent() {  # case name, stdin
  run "$2"
  [ "$code" -eq 0 ] || fail "$1: exit code (got $code, want 0)"
  [ -z "$out" ] || fail "$1: stdout (expected empty, got: $out)"
  pass "$1"
}

input() {  # source, transcript path → hook stdin JSON
  printf '{"session_id":"s1","transcript_path":"%s","cwd":"/tmp","source":"%s"}' "$2" "$1"
}

SKILL_CALL='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"loading"},{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"feature-workflow","args":"x"}}]}}'
USER_MENTION='{"type":"user","message":{"role":"user","content":"please use the feature-workflow skill, name Skill"}}'
OTHER_SKILL='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"agent-teams","args":"feature-workflow"}}]}}'
TOOL_RESULT='{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"{\"name\":\"Skill\",\"input\":{\"skill\":\"feature-workflow\"}}"}]}}'
NOT_TOOL_USE='{"type":"user","message":{"role":"user","content":[{"type":"text","name":"Skill","input":{"skill":"feature-workflow"}}]}}'

[ -f "$HOOK" ] || fail "hook missing at $HOOK"

with="$TMP/with.jsonl"; printf '%s\n%s\n%s\n' "$USER_MENTION" "$SKILL_CALL" "$USER_MENTION" > "$with"
expect_line "compact + Skill call -> reminder" "$(input compact "$with")"

without="$TMP/without.jsonl"; printf '%s\n' '{"type":"user","message":{"role":"user","content":"hi"}}' > "$without"
expect_silent "compact + no Skill call -> silent" "$(input compact "$without")"

mention="$TMP/mention.jsonl"; printf '%s\n%s\n%s\n%s\n' "$USER_MENTION" "$OTHER_SKILL" "$TOOL_RESULT" "$NOT_TOOL_USE" > "$mention"
expect_silent "compact + mentions only (user text, other skill, tool result, non-tool_use block) -> silent" "$(input compact "$mention")"

for s in startup resume clear fork; do
  expect_silent "source $s + Skill call -> silent" "$(input "$s" "$with")"
done

expect_silent "missing transcript file -> silent" "$(input compact "$TMP/nope.jsonl")"
expect_silent "transcript_path absent -> silent" '{"session_id":"s1","source":"compact"}'
expect_silent "malformed stdin -> silent" '{"source":"compact","transcript_path":'
expect_silent "empty stdin -> silent" ''

big="$TMP/big.jsonl"
python3 -c 'import sys; sys.stdout.write("{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"" + "x" * 2000000 + " feature-workflow\"}}\n")' > "$big"
printf '%s\n' "$SKILL_CALL" >> "$big"
expect_line "line over 1 MB before the match -> reminder" "$(input compact "$big")"

echo "all passed"
