#!/usr/bin/env bash
# Plain-bash tests for install.sh's master-model handling — no framework. Exits
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
# The live settings get <model> and the recommendation's modelSettings, each
# effort replaced by <effort> when given.
install() {
  home="$TMP/$1"
  mkdir -p "$home"
  python3 -c 'import json, sys
ex = json.load(open(sys.argv[1]))
d = {"modelSettings": {mid: {"effortLevel": sys.argv[3] or cfg["effortLevel"]} for mid, cfg in ex["modelSettings"].items()}}
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
  [ "$(setting 'sorted({c["effortLevel"] for c in d["modelSettings"].values()})')" = "['$REC_EFFORT']" ] \
    || fail "$1: effort not set to $REC_EFFORT"
  pass "$1"
}

expect_model "recommended keeps [1m]" "$REC_MODEL[1m]" "$REC_MODEL[1m]"
expect_model "recommended keeps [1M] casing" "$REC_MODEL[1M]" "$REC_MODEL[1M]"
expect_model "recommended moves a pinned [1m] model to the alias" "claude-some-pinned-model[1m]" "$REC_MODEL[1m]"
expect_model "recommended replaces a model without [1m]" "claude-some-pinned-model" "$REC_MODEL"
expect_model "recommended sets an unset model" "" "$REC_MODEL"

echo "all install-master tests passed"
