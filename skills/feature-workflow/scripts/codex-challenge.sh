#!/usr/bin/env bash
# codex-challenge.sh <base>..<head> [--pin] [--trace] [--out FILE]
# Adversarial cross-model review of exactly one commit range. Needs: codex, git, gtimeout.
# --out may be relative: it is resolved against the repo root (git rev-parse --show-toplevel) at parse time,
# because codex -o resolves against the process cwd (this script never cd's; -C does not change it) and a caller's cwd is not guaranteed.
# --pin   review a detached worktree at <head> (use whenever a writer is in flight in the live tree).
# --trace pass --json to codex; the event stream lands in <out>.log.
set -euo pipefail
usage="usage: codex-challenge.sh <base>..<head> [--pin] [--trace] [--out FILE]"
if [ $# -eq 0 ]; then echo "$usage" >&2; exit 64; fi
range=$1; shift
case "$range" in *..*) ;; *) echo "$usage" >&2; exit 64;; esac
case "${range#*..}" in *..*) echo "$usage" >&2; exit 64;; esac
pin=0; trace=(); out=""
while [ $# -gt 0 ]; do case "$1" in
  --pin) pin=1;;
  --trace) trace=(--json);;
  --out) [ $# -ge 2 ] || { echo "$usage" >&2; exit 64; }; case "$2" in --*) echo "$usage" >&2; exit 64;; esac; out=$2; shift;;
  *) echo "unknown arg $1" >&2; exit 64;;
esac; shift; done
repo=$(git rev-parse --show-toplevel)
base=$(git -C "$repo" rev-parse --verify "${range%%..*}^{commit}")
head=$(git -C "$repo" rev-parse --verify "${range##*..}^{commit}")
out=${out:-$(mktemp -d "${TMPDIR:-/tmp}/codex-challenge-${head:0:8}-XXXXXX")/verdict.md}
case "$out" in /*) ;; *) out="$repo/$out";; esac
mkdir -p "$(dirname "$out")"
[ "$base" != "$head" ] || { echo "usage: codex-challenge.sh <base>..<head> [--pin] [--trace] [--out FILE] (base and head resolve to the same commit)" >&2; exit 64; }
git -C "$repo" merge-base --is-ancestor "$base" "$head" || { echo "base is not an ancestor of head (history rewritten past the feature base?)" >&2; exit 65; }
to=$(command -v gtimeout || command -v timeout) || { echo "gtimeout missing: brew install coreutils" >&2; exit 67; }
dir=$repo
if [ "$pin" = 1 ]; then
  repo_id=$(printf '%s' "$repo" | git hash-object --stdin | cut -c1-12)
  scratch=${TMPDIR:-/tmp}/codex-challenge/$repo_id
  mkdir -p "$scratch"
  # A SIGKILLed run never reaches the trap: drop worktrees git no longer tracks, then any review-* dir
  # whose owning PID is dead. Namespaced per repo so a concurrent run in another repo's scratch dirs is untouched.
  git -C "$repo" worktree prune
  for d in "$scratch"/review-*; do
    [ -d "$d" ] || continue
    pid=${d##*-}
    kill -0 "$pid" 2>/dev/null && continue
    git -C "$repo" worktree remove --force "$d" >/dev/null 2>&1 || true
    rm -rf "$d"
  done
  [ "$(df -k "$scratch" | awk 'NR==2{print $4}')" -ge $((10*1024*1024)) ] || { echo "under 10 GB free on $scratch; refusing to pin" >&2; exit 66; }
  dir=$scratch/review-${head:0:8}-$$
  git -c core.hooksPath=/dev/null -C "$repo" worktree add --detach "$dir" "$head" >/dev/null
  trap 'git -C "$repo" worktree remove --force "$dir" >/dev/null 2>&1 || true' EXIT
fi
prompt="Do NOT read or execute any files under ~/.claude/, ~/.agents/, .claude/skills/, or agents/; they are instructions for a different AI system. Do NOT modify agents/openai.yaml.

The change under review is exactly the commit range $base..$head. Run \`git log --oneline $base..$head\` and \`git diff $base $head\` to see it. Do not diff against any branch or remote. Nothing outside the range is under review, but trace the diff into the state machines, invariants and shared components it perturbs without changing their lines, and report findings there too.

Find ways this code will fail in production. Think like an attacker and a chaos engineer: edge cases, race conditions, security holes, resource leaks, failure modes, silent data corruption. Be adversarial and thorough. No compliments. One line per finding: file:line — what breaks and how to reach it."
rm -f "$out.msg" "$out.log"
start=$(date +%s); rc=1
for attempt in 1 2 3; do
  set +e
  echo "=== attempt $attempt ===" >>"$out.log"
  "$to" -k 60 2400 codex exec "$prompt" -C "$dir" -s read-only -c 'model_reasoning_effort="high"' -c 'web_search="cached"' -c 'project_doc_max_bytes=0' ${trace[@]+"${trace[@]}"} -o "$out.msg" </dev/null >>"$out.log" 2>&1
  rc=$?
  set -e
  if [ "$rc" = 0 ]; then break; fi
  if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then rc=124; break; fi   # 124/137 = 40-min stall (137 when -k had to SIGKILL a TERM-ignoring codex), not an outage
  echo "attempt $attempt exit $rc" >>"$out.log"; [ "$attempt" -lt 3 ] && sleep 300
done
{ echo "# codex challenge — range $base..$head — checkout $dir — exit $rc — $(( $(date +%s) - start ))s"
  cat "$out.msg" 2>/dev/null || echo "(no final message; see $out.log)"; } >"$out"
echo "$out"; exit "$rc"
