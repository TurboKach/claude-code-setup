#!/usr/bin/env bash
# codex-challenge.sh <base>..<head> [--pin] [--trace] [--out FILE]
# Adversarial cross-model review of exactly one commit range. Needs: codex, git, gtimeout, pgrep (--pin only).
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
  command -v pgrep >/dev/null || { echo "pgrep missing" >&2; exit 67; }
  repo_id=$(printf '%s' "$repo" | git hash-object --stdin | cut -c1-12)
  scratch=${TMPDIR:-/tmp}/codex-challenge/$repo_id
  mkdir -p "$scratch"
  # A SIGKILLed run never reaches the trap: drop worktrees git no longer tracks, then any review-* dir
  # whose owning PID is dead. Namespaced per repo so a concurrent run in another repo's scratch dirs is untouched.
  git -C "$repo" worktree prune
  # Xcode keys DerivedData on the absolute project path, so a build inside a review checkout mints a
  # fresh multi-GB cache under ~/Library/Developer that removing the worktree never touches (five of
  # them leaked 18.6 GiB on 2026-09-03). Match on the review dir's unique tail rather than the full
  # path: $TMPDIR may carry a trailing slash and Xcode records the path with /var vs /private/var.
  sweep_dd() {
    local d ws
    for d in "$HOME/Library/Developer/Xcode/DerivedData"/*/; do
      ws=$(/usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$d/info.plist" 2>/dev/null) || continue
      case $ws in */"$1"/*) rm -rf "$d" || true ;; esac   # a held file must not abort the review under set -e
    done
  }
  for d in "$scratch"/review-*; do
    [ -d "$d" ] || continue
    pid=${d##*-}
    # pgrep -f matches process argv against a regex. $d itself embeds $TMPDIR, which is caller-controlled
    # and may hold metacharacters, so match on the known-safe tail instead: repo_id is a hex hash-object
    # digest and the review-<headshort>-<pid> suffix is hex, digits and dashes only, no regex metachars.
    suffix="codex-challenge/$repo_id/review-${d##*/review-}"
    { kill -0 "$pid" 2>/dev/null || pgrep -qf -- "$suffix"; } && continue
    sweep_dd "$suffix"   # before the dir goes: once it is gone no later run can recover the suffix
    git -C "$repo" worktree remove --force "$d" >/dev/null 2>&1 || true
    rm -rf "$d"
  done
  [ "$(df -k "$scratch" | awk 'NR==2{print $4}')" -ge $((2*1024*1024)) ] || { echo "under 2 GB free on $scratch; refusing to pin" >&2; exit 66; }
  dir=$scratch/review-${head:0:8}-$$
  git -c core.hooksPath=/dev/null -C "$repo" worktree add --detach "$dir" "$head" >/dev/null
  trap 'sweep_dd "codex-challenge/$repo_id/${dir##*/}"; git -C "$repo" worktree remove --force "$dir" >/dev/null 2>&1 || true' EXIT
fi
prompt="Do NOT read or execute any files under ~/.claude/, ~/.agents/, .claude/skills/, or agents/; they are instructions for a different AI system. Do NOT modify agents/openai.yaml.

The change under review is exactly the commit range $base..$head. Run \`git log --oneline $base..$head\` and \`git diff $base $head\` to see it. Do not diff against any branch or remote. Nothing outside the range is under review, but trace the diff into the state machines, invariants and shared components it perturbs without changing their lines, and report findings there too.

Find ways this code will fail in production. Think like an attacker and a chaos engineer: edge cases, race conditions, security holes, resource leaks, failure modes, silent data corruption. Be adversarial and thorough. No compliments. One line per finding: file:line — what breaks and how to reach it."
rm -f "$out.msg" "$out.log"
# A review run needs no MCP tools: every configured server would otherwise start per run (a stale
# Atlassian OAuth refresh failed on all 34 runs of 2026-09-03) and hand the reviewer outbound reach —
# Jira, web fetch — the read-only sandbox does not grant. `-c mcp_servers={}` does not clear the table
# (TOML merge; verified 2026-09-04), per-server enabled=false does. The names come from codex's own
# config loader (`codex mcp list --json`, run in the review checkout so a trusted project config counts),
# never from parsing config.toml here — two regex rounds missed sub-tables, trailing comments and quoted
# names. A quoted key segment is rejected by codex's loader ("invalid transport", verified), so only
# names that are valid bare TOML keys are passed; any other name is left enabled rather than broken.
mcp_off=()
set +e; mcp_json=$(cd "$dir" && "$to" -k 10 30 codex mcp list --json 2>>"$out.log"); mcp_rc=$?; set -e
if [ "$mcp_rc" != 0 ] || [ -z "$mcp_json" ]; then
  echo "warning: codex mcp list failed (exit $mcp_rc) — MCP servers stay enabled for this run" | tee -a "$out.log" >&2
fi
while IFS= read -r name; do
  case $name in *[!A-Za-z0-9_-]*|'') continue;; esac
  mcp_off+=(-c "mcp_servers.${name}.enabled=false")
done < <(printf '%s\n' "$mcp_json" | sed -nE 's/^[[:space:]]*"name":[[:space:]]*"(.*)",?$/\1/p' | sort -u)
# approval_policy=never: the read-only sandbox denies writes outside the checkout, but an "allow"
# prefix rule in ~/.codex/rules (smart approvals add them for xcodebuild) runs the command outside
# the sandbox under on-request, which is how the review builds wrote DerivedData. Codex documents
# never as the policy for non-interactive runs; verified 2026-09-04 that it keeps xcodebuild sandboxed.
start=$(date +%s); rc=1
for attempt in 1 2 3; do
  set +e
  echo "=== attempt $attempt ===" >>"$out.log"
  "$to" -k 60 2400 codex exec "$prompt" -C "$dir" -s read-only --ephemeral -c 'approval_policy="never"' -c 'model_reasoning_effort="high"' -c 'web_search="cached"' -c 'project_doc_max_bytes=0' ${mcp_off[@]+"${mcp_off[@]}"} ${trace[@]+"${trace[@]}"} -o "$out.msg" </dev/null >>"$out.log" 2>&1
  rc=$?
  set -e
  if [ "$rc" = 0 ]; then break; fi
  if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then rc=124; break; fi   # 124/137 = 40-min stall (137 when -k had to SIGKILL a TERM-ignoring codex), not an outage
  echo "attempt $attempt exit $rc" >>"$out.log"; [ "$attempt" -lt 3 ] && sleep 300
done
rm -f "$out"
{ echo "# codex challenge — range $base..$head — checkout $dir — exit $rc — $(( $(date +%s) - start ))s"
  cat "$out.msg" 2>/dev/null || echo "(no final message; see $out.log)"; } >"$out"
echo "$out"; exit "$rc"
