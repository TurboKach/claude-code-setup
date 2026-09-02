# Plan: kit-owned `codex-challenge.sh` replaces the gstack codex path; stage-4 review+fix loop made exact

**Goal.** One range-scoped script, installed by the kit, is the only codex invocation the doctrine names. Every `Skill(codex, …)` / `/codex challenge` site is cut over; the stage-4 per-step loop is specified so rounds are contiguous, pinned only when a writer is in flight, and fixer commits are always inside the next round's range. The arc dogfoods the script on itself.

**Context (measured 2026-09-02 from the 2026-09-01 backend and clipsy session transcripts and the 111 verdict files in both projects).** gstack's `/codex challenge <text>` parses `<text>` as a focus area and its prompt tells codex to run `git diff origin/<base>` — but no recorded run ever took that path: zero verdict files show a `git diff … origin/` command, 55 show an explicit sha range, and per-step rounds were step-scoped (`git diff 82d9731..HEAD` in a worktree pinned at the step sha). The masters got there by hand: one `Skill(codex)` load per session (102 KB into context), then 14 hand-assembled `gtimeout 2400 codex exec "$PROMPT" …` launches in the backend arc with the master's own prompt and three different JSONL parser variants — 13 of them dropped the `[codex ran]` lines, so every backend verdict file is unauditable for what codex actually read. The doctrine line `Skill(codex, "challenge <range>")` describes an invocation that never runs. This arc replaces the per-round improvisation with one deterministic script (range in the prompt, trace on demand, pin/timeout/retry encoded) and cuts the doctrine over to it. The owner keeps cross-model review and will battle-test on a real project.

Feature base: `git rev-parse HEAD` at plan approval (currently `99d0e8d`). The script lives inside the skill that owns it (Anthropic's skills doc: skills bundle supporting files; `${CLAUDE_SKILL_DIR}` exists for that). During this arc the master calls it by repo path (`/Users/turbokach/Dev/claude-code-setup/skills/feature-workflow/scripts/codex-challenge.sh`) — it is not in `~/.claude` until `install.sh` runs after ship. The doctrine names the installed absolute path `~/.claude/skills/feature-workflow/scripts/codex-challenge.sh` everywhere (CLAUDE.md's one-shot path runs with no skill loaded, so `${CLAUDE_SKILL_DIR}` would only work inside SKILL.md — one string, used consistently).

Decided, not open: the master always passes `--out`; per-step rounds always `--pin`; `--output-schema` deferred; split slices are contiguous commit sub-ranges; the 10 GB pin threshold stays (measured ENOSPC number) — the volume is 99% full (7.67 GiB free at planning), so the owner frees ≥1.5 GB before round 1.

## Step 1 — the script · `step-executor` (Sonnet)

Files: `skills/feature-workflow/scripts/codex-challenge.sh` (new, mode 755), `README.md` (one table row directly under the last `skills/…` row). **No `install.sh` change**: the skills loop (`install.sh:142–147`) already does `cp -R "$SRC/skills/$skill" "$DEST/skills/$skill"`, and BSD `cp -R` preserves the executable bit (verified on this machine). No `INSTALL.md` change in this step.

Write the file with exactly this content:

```sh
#!/usr/bin/env bash
# codex-challenge.sh <base>..<head> [--pin] [--trace] [--out FILE]
# Adversarial cross-model review of exactly one commit range. Needs: codex, git, gtimeout.
# --out must be an absolute path: codex -o resolves against the process cwd (this script never cd's; -C does not change it).
# --pin   review a detached worktree at <head> (use whenever a writer is in flight in the live tree).
# --trace pass --json to codex; the event stream lands in <out>.log.
set -euo pipefail
range=${1:?usage: codex-challenge.sh <base>..<head> [--pin] [--trace] [--out FILE]}; shift
pin=0; trace=(); out=""
while [ $# -gt 0 ]; do case "$1" in --pin) pin=1;; --trace) trace=(--json);; --out) out=$2; shift;; *) echo "unknown arg $1" >&2; exit 64;; esac; shift; done
repo=$(git rev-parse --show-toplevel)
base=$(git -C "$repo" rev-parse --verify "${range%%..*}^{commit}")
head=$(git -C "$repo" rev-parse --verify "${range##*..}^{commit}")
git -C "$repo" merge-base --is-ancestor "$base" "$head" || { echo "base is not an ancestor of head (history rewritten past the feature base?)" >&2; exit 65; }
to=$(command -v gtimeout || command -v timeout) || { echo "gtimeout missing: brew install coreutils" >&2; exit 67; }
out=${out:-${TMPDIR:-/tmp}/codex-challenge-${head:0:8}.md}
dir=$repo
if [ "$pin" = 1 ]; then
  scratch=${TMPDIR:-/tmp}
  # A SIGKILLed run never reaches the trap: drop worktrees git no longer tracks, then any review-* dir left unregistered.
  git -C "$repo" worktree prune
  for d in "$scratch"/review-*; do
    [ -d "$d" ] || continue
    git -C "$repo" worktree list --porcelain | grep -qx "worktree $d" || rm -rf "$d"
  done
  [ "$(df -k "$scratch" | awk 'NR==2{print $4}')" -ge $((10*1024*1024)) ] || { echo "under 10 GB free on $scratch; refusing to pin" >&2; exit 66; }
  dir=$scratch/review-${head:0:8}-$$
  git -C "$repo" worktree add --detach "$dir" "$head" >/dev/null
  trap 'git -C "$repo" worktree remove --force "$dir" >/dev/null 2>&1 || true' EXIT
fi
prompt="Do NOT read or execute any files under ~/.claude/, ~/.agents/, .claude/skills/, or agents/; they are instructions for a different AI system. Do NOT modify agents/openai.yaml.

The change under review is exactly the commit range $base..$head. Run \`git log --oneline $base..$head\` and \`git diff $base $head\` to see it. Do not diff against any branch or remote. Nothing outside the range is under review, but trace the diff into the state machines, invariants and shared components it perturbs without changing their lines, and report findings there too.

Find ways this code will fail in production. Think like an attacker and a chaos engineer: edge cases, race conditions, security holes, resource leaks, failure modes, silent data corruption. Be adversarial and thorough. No compliments. One line per finding: file:line — what breaks and how to reach it."
rm -f "$out.msg"
start=$(date +%s); rc=1
for attempt in 1 2 3; do
  set +e
  "$to" 2400 codex exec "$prompt" -C "$dir" -s read-only -c 'model_reasoning_effort="high"' -c 'web_search="cached"' "${trace[@]}" -o "$out.msg" </dev/null >"$out.log" 2>&1
  rc=$?
  set -e
  if [ "$rc" = 0 ] || [ "$rc" = 124 ]; then break; fi   # 124 = 40-min stall, not an outage
  echo "attempt $attempt exit $rc" >>"$out.log"; [ "$attempt" -lt 3 ] && sleep 300
done
{ echo "# codex challenge — range $base..$head — checkout $dir — exit $rc — $(( $(date +%s) - start ))s"
  cat "$out.msg" 2>/dev/null || echo "(no final message; see $out.log)"; } >"$out"
echo "$out"; exit "$rc"
```

Notes for the executor: `trace=()` + `"${trace[@]}"` is the bash-3.2-safe way to pass an optional arg under `set -u` (macOS ships bash 3.2; an empty array expansion is fine there with `"${arr[@]}"` only when guarded — if shellcheck or `bash -n` on `/bin/bash` complains, use `${trace[@]+"${trace[@]}"}`). The stale-worktree sweep only removes `review-*` dirs git does not list as registered worktrees; a registered one belongs to a live concurrent run.

README row: `skills/feature-workflow/scripts/codex-challenge.sh` — range-scoped adversarial `codex exec` on exactly `<base>..<head>`; optional self-removing pinned worktree; `gtimeout 2400`, 3 attempts / 5 min; writes the verdict file and prints its path.

Acceptance: `bash -n` and `shellcheck` (at `/opt/homebrew/bin/shellcheck`) on the script exit 0; `test -x` true; no args → exit 64-class usage error; `HEAD..HEAD~1` → exit 65; `git status --short` shows exactly `?? skills/feature-workflow/scripts/codex-challenge.sh` and ` M README.md` (the new file is untracked — `git diff --stat` would miss it). Commit. The executor does **not** run codex — a real run exceeds a subagent's Bash cap; the master runs it as round 1.

## Round 1 (dogfood, master, same turn as the step-2 spawn)

**Before launching:** `df -k "$TMPDIR"` reads ~7.67 GiB free — under the script's 10 GB pin refusal (exit 66). The owner frees ≥1.5 GB first (decided, item (i)); the master reports the `df` reading it launched at.

Verbatim Bash, `run_in_background: true`:
```
/Users/turbokach/Dev/claude-code-setup/skills/feature-workflow/scripts/codex-challenge.sh <feature-base>..<step1-sha> --pin --trace --out <session-scratchpad>/codex-step1.md
```
(`--pin` because the step-2 executor is writing. Step 2 is blocked by nothing round 1 produces, so under the dependency-aware boundary rule its executor spawns in this same turn.)

On the completion notification: one `codex-triage` spawn (sonnet, unnamed) whose prompt carries: the file path(s); the range `<base>..<head>`; the head sha; the instruction that findings are verified with `git show <head>:<path>` and `git diff <base> <head>` (no checkout exists); and, for this round only, the trace check: "in `<out>.log`, list every command codex executed that contains `git diff`; report PASS if every one names `<base> <head>` (or `<base>..<head>`) and none contains `origin/`, else FAIL with the offending lines. The event type carrying commands is expected to be `command_execution`, but that name is a hypothesis — if zero `git diff` commands match, do not report FAIL: list the distinct item/event types actually present in the log and the first command-like entry of each, and let the master judge." P0/P1 → one `fixer` before step 3's executor spawns (step 3 is blocked by step 2 in the task list; see the boundary rule).

## Step 2 — core doctrine: CLAUDE.md + feature-workflow · `step-executor` (Sonnet)

Files: `global/CLAUDE.md` (lines 27, 37, 49, 50, 57), `skills/feature-workflow/SKILL.md` (frontmatter `description`, line 8, line 28, stage 4 **Per-step review**, stage 5, the split-range paragraph, Token-discipline bullets at lines 54, 56, 59).

Installed path string used everywhere below: `~/.claude/skills/feature-workflow/scripts/codex-challenge.sh` (absolute; never `${CLAUDE_SKILL_DIR}` — CLAUDE.md's one-shot path has no skill loaded).

Contracts the executor writes to (measured numbers and the "why" sentences stay; mechanics the script now encodes go):

- **CLAUDE.md:27** — heading "**The codex gate.**": ship only after `~/.claude/skills/feature-workflow/scripts/codex-challenge.sh <feature-base-sha>..HEAD` has run once on the whole range as one background Bash in the master and the `codex-triage` verdict is shown; internal reviewers don't satisfy it; "unreviewed, not merging". Drop "gstack's `/codex` skill", `Skill(codex…)`, "on a pinned worktree".
- **CLAUDE.md:37** — "formal gates — team-reviewer, `/codex`" → "formal gates — team-reviewer, the codex gate".
- **CLAUDE.md:49** — one-shot: "one `codex-challenge.sh <pre-change-sha>..HEAD` run on its diff, stage-5 triage rules".
- **CLAUDE.md:50** — "one `/codex` challenge per feature → ship" → "one codex challenge per feature → ship".
- **CLAUDE.md:57** — gstack bullet keeps `/browse` and `/review`; "then `/codex challenge`" → "then the codex gate (`codex-challenge.sh`, feature-workflow stage 5)". This is the one remaining `/codex`-free mention of gstack + codex and the only grep exemption.
- **SKILL.md description + line 8** — "one codex challenge per feature" wording; no `/codex`. **SKILL.md:28** — "the `/codex` merge gate" → "the codex gate".
- **Stage 4, Per-step review** (replace the sentence block; keep the 2026-08-23 "why"):
  - Round N launches in the same turn step N's commit lands. Range = `<previous round's head>..<HEAD now>` (round 1's base = the feature base). Contiguous by construction: every commit between two rounds — including fixer commits — is in exactly one round; the rounds jointly cover the range with no gap. The last step gets no per-step round: stage 5 covers it.
  - Always `--pin` (a later executor may be writing). The script creates and removes its own worktree; the master never adds or removes worktrees.
  - Verbatim call: `~/.claude/skills/feature-workflow/scripts/codex-challenge.sh <base>..<head> --pin --out <scratchpad>/codex-step<N>.md` as one `run_in_background` Bash (or `docs/reviews/<feature>-step<N>.md` when the project keeps records); the master ends its turn or does work not depending on the verdict.
  - On completion: one `codex-triage` spawn — file path(s), range, head sha; verifies with `git show <head>:<path>` / `git diff <base> <head>`. P0/P1 → one `fixer` before the next executor that depends on the reviewed step spawns (fixer and executor are both single-writer; fixer first, so the following round's range contains the fix).
  - **Step boundary is dependency-aware**, using the task list the stage-3 mirror already builds (`addBlockedBy` where a step consumes an earlier step's output): an executor spawns only when every step it is blocked by has its per-step verdict in and its P0/P1 fixed; a step blocked by nothing pending spawns immediately, and its round launches in the same turn. Waiting costs a step-sized codex run (per-step rounds were already step-scoped in practice; the 14–22 min figure is whole-range). Concurrent read-only runs are fine, each pinned at its own head.
  - Stage 5 launches only when no per-step round is in flight and no fixer is pending — a fixer commit after the whole-range launch invalidates it.
  - Per-step rounds are bug-catching, not the gate (existing sentence stays).
- **Stage 5** — replace the "The master runs it, backgrounded:" mechanics sentence with: the master launches `~/.claude/skills/feature-workflow/scripts/codex-challenge.sh <feature-base-sha>..HEAD --out <file>` as one `run_in_background` Bash — no `--pin` (nothing writes during the gate; the fix loop is serial: challenge → fixer → re-challenge on the same command with the new HEAD) — and spawns `codex-triage` on the completion notification. Delete the "bare `codex exec` only if gstack is unavailable" clause and the gstack framing of the `codex:codex-rescue` / `/codex review` clauses (keep "never `codex:codex-rescue`"). Everything from "In parallel with the whole-range run, one `spec-reviewer`…" through the end of the stage-5 paragraph is untouched (taxonomy, confidence, convergence, two non-decreasing rounds, deferral index lines).
- **Failure paths** (new sentences in stage 5, referenced from stage 4; decided): exit 124 → relaunch once with the same arguments (a different `--out` name, e.g. `-r2`); a second 124 → the range is too big: split (stage 5) or, in stage 4, skip the round and note it in the cost checkpoint (stage 5 still covers it). Non-zero after the script's three attempts, or a header under 60 s (auth/usage-limit — triage reports it verbatim) → park: push-notify, end the turn, no relaunch — the script already retried for 10 minutes.
- **Split-range paragraph** — slices are contiguous commit sub-ranges, one script run each, concurrent, **unpinned** (no writer at stage 5, and unpinned slices read the final tree, so out-of-diff tracing sees the finished code); gaplessness is by construction and each slice's range is recorded in its header line. Keep the "one triage spawn for all slices", "master never hand-dedups", and 47-unpushed-commits sentences.
- **Token discipline :54** — keep: 14–22 min measured, the two 600 s ceilings (say gstack's `gtimeout 600` was the second one and is gone with the script), the subagent-can't-wait mechanics, the 3.4 h runner loss, the 529 outage. Replace the "so the run is a single … retry loop …" clause with: the run is `codex-challenge.sh` as one `run_in_background` Bash in the master — the script carries `gtimeout 2400`, the 3-attempt/5-min retry, the optional pin, and writes the output file. Triage sentence: "checks each finding against the pinned checkout" → "against `git show <head>:<path>`".
- **Token discipline :56** — keep the coupling explanation and the "pin or serialize" rule, the sha-X limit, the history-rewrite limit (now the script's exit 65), the ENOSPC/10 GB fact. Replace the `git worktree add`/`-C`/`git worktree remove` mechanics with: `--pin` does the free-space check, the stale-worktree sweep, the detached worktree, and its removal on exit; per-step rounds always pin, a run with no writer in flight doesn't.
- **Verdict size contract :59** — actor sentence: "the master's background `codex-challenge.sh` call writes the full output to the verdict file (`--out`), and the `codex-triage` spawn prompt names that round's file(s), the range and the head sha". Keep the never-read rule (`$out.log` and `$out.msg` are challenge output too).

Acceptance: `grep -n 'Skill(codex\|/codex\|gstack.*codex\|worktree add\|worktree remove' global/CLAUDE.md skills/feature-workflow/SKILL.md` returns nothing except CLAUDE.md:57's `/browse`/`/review` gstack bullet (the only exemption); `grep -c 'gtimeout 2400' skills/feature-workflow/SKILL.md` ≥ 1; every measured number listed above still present (grep `14–22`, `529`, `3.4 h`, `ENOSPC`, `10 GB`, `600 s`); stage 5's convergence text byte-identical from "Triage real / regression" onward. Commit.

## Step 3 — periphery · `step-executor` (Sonnet)

Files: `skills/agent-teams/SKILL.md` (:97, :156, :176–177, :189, :282), `agents/codex-triage.md`, `agents/team-reviewer.md:21`, `README.md` (:20, :30, :55, :154–160, one Notes entry), `docs/tech-debt.md` (:136–155), `docs/decision-flow.md` (:45, :97), `docs/references.md` (:86), `INSTALL.md` (Step 0 :13–17, plus :48), `install.sh:322`.

Installed path in all step-3 prose: `~/.claude/skills/feature-workflow/scripts/codex-challenge.sh`.

Contracts:
- agent-teams :176–177: `5. CODEX (lead launches codex-challenge.sh as one background Bash; codex-triage triages) → ONE ~/.claude/skills/feature-workflow/scripts/codex-challenge.sh <feature-base-sha>..HEAD on the merged feature diff …`; :97/:156/:282 "the codex gate"; :189 "No /goal" — "codex round 3" → "a non-decreasing P0/P1 round" (the real gate list, matching stage 5).
- codex-triage.md: description + body — reads one round's output file(s) written by `codex-challenge.sh`; the checkout is gone, verify against `git show <head>:<path>` and `git diff <base> <head>`; the spawn prompt names file(s), range, head sha. Step 1 of "How you work" also reads the header line (`exit RC — Ns`): non-zero exit or under 60 s → report verbatim and stop (already the rule; name the header as the source). No other changes.
- team-reviewer.md:21: "the `/codex` gate" → "the codex gate".
- README: :20 "`/codex` merge gate" → "codex gate"; :30 triage row reads "Reads one round's `codex-challenge.sh` output file(s)…"; :55 diagram line becomes `CODEX (lead) → one codex-challenge.sh <feature-base>..HEAD ─┘   ← triaged verdict, P0/P1 fixed` — replace the text only; per the cited rule (`docs/prompts/prompt-smith-retirement-plan.md:163–167`, "do not re-align the remaining characters") the `─┘` stays where it falls, no padding; :154–160 gstack is optional for `/office-hours`, `/ship`, `/context-save`, `/browse`; the codex gate needs `codex` (codex-cli) + `gtimeout` (`brew install coreutils`), not gstack — drop "skip the codex gate (say so)"; `install.sh:322` and `INSTALL.md:48` lose `/codex` from the gstack list. One Notes entry dated 2026-09-02: transcripts of the 2026-09-01 backend and clipsy arcs show the `Skill(codex, "challenge <range>")` path was never what ran — gstack would have treated the range as a focus area and diffed `origin/<default>`, so each master loaded the 102 KB skill once and then hand-assembled every launch (14 in the backend arc, three parser variants, 13 without the `[codex ran]` audit lines); every recorded run did diff the explicit range. Replaced by the kit-owned `codex-challenge.sh`: one deterministic call, range in the prompt, `--trace` for the audit trail, pin/timeout/retry encoded. The step-1 table row already exists.
- `docs/references.md:86`: "The shape of the `/codex` gate." → "The shape of the codex gate."
- `INSTALL.md` Step 0: one detection line after the gstack probe — `command -v codex >/dev/null && command -v gtimeout >/dev/null && echo "codex gate: ready" || echo "codex gate: needs codex-cli + coreutils (gtimeout)"` — and a bullet under it: if missing, `brew install coreutils` and install codex-cli; the codex gate does not run without them.
- tech-debt.md: the ":18 diff range probably ignored" entry → resolved 2026-09-02 (keep the entry, add a `**Resolved:**` line: measured — no recorded run diffed `origin/`; masters bypassed the gstack path by hand-assembling each launch, which drifted (three parser variants, lost `[codex ran]` lines); `skills/feature-workflow/scripts/codex-challenge.sh` now owns the invocation; follow the file's existing resolved-entry convention if any).
- decision-flow.md :45 node: `ONE codex-challenge.sh <feature-base-sha>..HEAD`; :97 "without the codex gate". Leave "P1/P2 fixed, rounds ≤3" — pre-existing stale text, out of scope (report it).

Acceptance: `grep -rn 'Skill(codex\|/codex' global skills agents README.md INSTALL.md install.sh docs/decision-flow.md docs/tech-debt.md docs/references.md` returns only: CLAUDE.md:57 (exempt), README Notes :166–172 (dated, historical — expected, untouched), tech-debt historical lines (verdict paths, the resolved entry's quote). `docs/prompts/*` untouched. Commit.

## Step 4 — final gate (master; the arc's "full suite")

1. Wait for no round in flight / no fixer pending. Launch `/Users/turbokach/Dev/claude-code-setup/skills/feature-workflow/scripts/codex-challenge.sh <feature-base>..HEAD --out <scratchpad>/codex-final.md` (no pin) as background Bash; in parallel one `spec-reviewer` spawn on `<feature-base>...HEAD` against the plan file.
2. Completion → `codex-triage` (file, range, head sha). Stage-5 loop as written: P0/P1 → `fixer` → re-run the same command with the new HEAD; convergence rule unchanged. Standalone P2/test-gap/theoretical → the one fix-or-defer AskUserQuestion.
3. Report: triaged verdict ≤2k + file path; round-1 trace PASS/FAIL line; `bash -n`/shellcheck results; `git worktree list` showing no `review-*` leftovers; the `df` reading round 1 launched at (owner freed space first). Then push approval (hard gate). After ship, the owner runs `./install.sh` — the skills loop copies `scripts/` with the executable bit; confirm with `test -x ~/.claude/skills/feature-workflow/scripts/codex-challenge.sh` — say so in the report.

## Edge cases
- Round pinned at head X with a fixer commit landing after X: by design, not covered until the next round — the range rule handles it.
- One-shot on a pushed default branch: `<pre-change-sha>..HEAD` is non-empty regardless of remotes — the defect this closes.
- History rewrite past the feature base → exit 65, fail loud (was silent).
- `$TMPDIR` on macOS ends with `/` — path gets `//`, harmless.
- Two concurrent runs at the same head (relaunch after 124 while the first is somehow still alive) — distinct `-$$` worktree dirs; `--out` names must differ (`-r2` suffix) or the second overwrites the first.
- A SIGKILLed pinned run leaves a registered-but-dead worktree: the next `--pin` run's `git worktree prune` + unregistered `review-*` sweep removes it; the master's end-of-arc `git worktree list` check stays as the backstop.

## Verification
Step-level: the greps and `bash -n`/shellcheck above. Arc-level: round-1 trace PASS (real `codex exec` on step 1's range, `git diff <base> <head>` only, no `origin/`); the final-gate verdict; no leftover worktrees. No fake-codex test (owner declined).

## Taste / open decisions

None open. Decided by the owner and folded above: (a) script inside `skills/feature-workflow/scripts/`, installed by the existing skills `cp -R` (executable bit verified preserved); (b) master always passes `--out`; (c) per-step rounds always `--pin`; (d) `--trace` kept; (e) `--output-schema` deferred; (f) failure handling = 124 relaunch once → split/skip, else park with push-notify; (g) dependency-aware step boundary via the task list's `addBlockedBy`; (h) split slices = contiguous commit sub-ranges; (i) 10 GB threshold kept, owner frees ≥1.5 GB before round 1.

Plan-reviewer pass 1: 3 blocking (all fixed in this revision), 8 advisory (all folded). No second review pass: the revision applied exactly the reviewer's prescriptions, and the script is checked by shellcheck in step 1 and by its own codex round.
