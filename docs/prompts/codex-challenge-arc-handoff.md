# Handoff: evaluate the codex-challenge arc (2026-09-02) and decide what, if anything, to improve

Cold-start ready: a fresh session needs no other file to begin. The job is
analysis and a decision, not building. Discuss before changing anything.

## What the next session is for

Answer, with evidence from the files named below: did the 2026-09-02 changes
to the codex gate and the stage-4 review loop make the pipeline better, and
which of the open items below are worth doing? Produce a keep / tune / revert
verdict per item and one combined summary before any edit.

## What was done on 2026-09-02 (all pushed: `99d0e8d..3eba442` on `master`)

1. **Audit of the kit against Anthropic docs and the Claude Code 2.1.258
   binary** (204-agent workflow). Digest with all 68 confirmed findings, the
   refuted ones, and before/after diffs:
   `docs/reviews/codex-challenge-arc/kit-audit-2026-09-02.md`. Only the codex
   path was acted on; the rest of the audit's proposals are still open (see
   "Open items", group C).
2. **Measured the old codex gate from transcripts** (backend session
   `11b46684`, clipsy session `41f4cca3`, both 2026-09-01, plus 111 verdict
   files under both projects' `docs/reviews/`): no recorded run ever diffed
   `origin/`; masters loaded gstack's 102 KB codex skill once per session and
   then hand-assembled every `codex exec` launch (14 in the backend arc, three
   parser variants, 13 without `[codex ran]` lines). The defect was
   determinism and audit trail, not scope. Memory:
   `~/.claude/projects/-Users-turbokach-Dev-claude-code-setup/memory/codex-launch-measured.md`.
3. **Built `skills/feature-workflow/scripts/codex-challenge.sh`** (69 lines):
   range in the prompt, `--pin` (per-repo worktree namespace, PID liveness,
   10 GB preflight, hooks disabled), `--trace` (`--json` stream to `<out>.log`),
   `--out` (relative resolves against the repo root, parent created), gtimeout
   2400 with kill-after, 3 attempts / 5 min, exit map 64/65/66/67/124,
   `-c project_doc_max_bytes=0` (AGENTS.md injection verified blocked).
   Plan: `docs/prompts/codex-challenge-script-plan.md`.
4. **Cut the doctrine over**: `global/CLAUDE.md` (gate, one-shot, tooling),
   `skills/feature-workflow/SKILL.md` (stage 4 per-step loop: contiguous rounds,
   always pin, dependency-aware boundary via the task list; stage 5 launch,
   failure paths, split-range, token discipline, verdict contract),
   `skills/agent-teams/SKILL.md`, `agents/codex-triage.md` (verifies via
   `git show <head>:<path>`), README, INSTALL, install.sh, tech-debt,
   decision-flow, references. gstack stays for office-hours, ship, browse,
   context-save; it no longer touches the codex path.
5. **Dogfooded the loop on itself**: 2 per-step rounds, 3 whole-range rounds,
   4 fixers, 17 findings closed red-then-green; the master read the five trace
   logs in-session, but the sidecars did not survive, and the only surviving
   log is a plain-text transcript from a fixer's orphaned test run, so the
   claim is not re-verifiable. Gate clean at `ac1424d`; round 3 at `5acce42`
   found one new P1 (INSTALL.md
   readiness line), fixed in `3eba442`. 14 standalone items deferred as index
   lines in `docs/tech-debt.md` ("Deferred from the codex-challenge arc").
   Verdicts: `docs/reviews/codex-challenge-arc/codex-step1.md`, `codex-step2.md`,
   `codex-final-round1..3.md` (trace `.log` sidecars stayed in the session
   scratchpad and may be gone).

## Measurements from this arc (a 12-file, +165/−44 diff in this kit)

| Run | Range | Duration | Result |
|---|---|---|---|
| per-step 1 (script, 49 lines) | 83c9b33..a382c44 | 733 s | 1 P0, 3 P1, 4 P2, 2 test-gap |
| per-step 2 (doctrine only) | a382c44..40101aa | 551 s | 2 P1, 4 theoretical |
| whole-range 1 | 83c9b33..d692216 | not recorded by triage | 4 P1, 6 P2, 3 theoretical |
| whole-range 2 | 83c9b33..ac1424d | 714 s | clean; 6 P2, 2 theoretical |
| whole-range 3 | 83c9b33..5acce42 | 1000 s | 1 P1 (new), 3 P2, 1 theoretical, 10 re-reports |

Agent cost (tokens / wall-clock, from task notifications): planner 64k/4.4 min,
plan-reviewer 86k/2.3 min, planner revision 33k/1.8 min; executors 34k/1 min,
116k/6.4 min, 91k/4.2 min; fixers 56k/6.1 min, 52k/2.5 min, 67k/3.4 min,
33k/2.5 min; triages 27k, 71k, 41k, 53k, 45k (1.6–2.4 min each); spec-reviewer
109k/2.3 min. Audit workflow: 204 agents, 10.9M tokens, 58 min. Master context
peak: 566k (last assistant usage block; above the 400k defect line). Session
transcript for exact numbers (dedupe by `message.id`):
`~/.claude/projects/-Users-turbokach-Dev-claude-code-setup/0ad60543-195a-457c-b542-2b2e4fea00a6.jsonl`
and its `subagents/` directory (19 agent transcripts; the audit workflow's 204
live under subagents/workflows/).

## What the arc showed (facts, not yet doctrine)

- **A codex run's duration is not size-invariant.** Runs measured 551–1000 s
  here and 237–1670 s per step on the 2026-09-01 backend arc; launch-to-
  triaged-verdict ran 11.5–18.7 min; the step-3 boundary wait measured 21.5
  min; no per-step diff sizes exist to correlate.
- **Codex varies between rounds.** Round 3 flagged a line rounds 1 and 2 had
  passed. The convergence rule ("a non-decreasing P0/P1 round forces the
  structural branch") fired on a one-liner and needed a user gate.
- **Per-step rounds found real bugs early**: the P0 (bash 3.2 unbound array
  without `--trace`) was invisible to the executor's own checks and to every
  run that used `--trace`.
- **All five runs were unpinned** because the data volume never had 10 GB
  free (7.65–8.70 GB). Safe here (only doctrine files were being written); not
  safe on a product repo.
- **Fixers built throwaway fake-codex stubs** to get red-then-green without
  spending runs; one fixer accidentally started codex for under a second on
  the unfixed script (read-only, artifact removed). The owner declined a
  committed self-test; this is the data point for revisiting.
- **Softening plan criteria in a spawn prompt leaks defects**: the plan said
  exit 64 on no-args, the step-1 prompt said "non-zero", the spec-reviewer
  caught it.

## Open items to decide

**A. Stage-4 loop tuning (doctrine, `skills/feature-workflow/SKILL.md`)**
1. Replace "waiting costs a step-sized codex run" with the measured ~10 min
   per run; decide whether per-step rounds run on every step, only on code
   steps, or only where the task list shows a dependency.
2. Convergence rule: key on repeat findings of the same mechanism, not any
   non-decreasing count; a new low-confidence finding after a clean round goes
   to fix-or-defer.
3. Should `--trace` be the default (always auditable, ~100–400 KB per run)?
4. The 10 GB pin threshold versus the owner's disk reality; or make the
   threshold a measured checkout size.

**B. Script follow-ups (`docs/tech-debt.md`, 14 index lines)** — the ones with
teeth: symlink at `--out`; wrapper-PID liveness; worktree add outside the
timeout; `--ephemeral`; a committed self-test script.

**C. Audit proposals not yet applied** (`kit-audit-2026-09-02.md`, and the
diff list in the session's second reply): seven factual defects from the
2026-09-02 morning commits (Explore cap is 2.1.198 not 2.1.257 in three files;
three unsupported Fable-guide attributions in `docs/references.md`; README
"Opus roles"; wrong "encoded in" pointers), six cross-file contradictions
(maxTurns SendMessage vs respawn; agent-teams prose budget; decision-flow Gate 0;
CLAUDE.md "3+ steps" vs one-shot), agent-body duplication of CLAUDE.md,
missing `maxTurns` on five agents, the push-approval hook, and the skill-body
"why" narration move. Decide which groups to run; groups 1–2 are doctrine-only
and mechanical.

**D. Battle test on a product repo** (owner's stated next step): run one real
arc on clipsy or backend with `--pin` (free disk first) and `--trace`; measure
per-run duration, whether per-step rounds catch anything the whole-range gate
would not, how often codex re-reports deferred items, and whether the
dependency-aware boundary blocks more than it helps. Compare against the
2026-09-01 backend arc numbers in memory.

**E. Installed-kit drift**: the installed kit under `~/.claude` was 14 commits
stale at evaluation time (stamp `60ad075`); the live gate named the retired
gstack skill and the script path did not exist. `install.sh`'s default mode
leaves an existing `CLAUDE.md` untouched.

## Ground rules that apply (from `~/.claude/CLAUDE.md` and memory)

Every claim grounded in a doc or a transcript, else labeled hypothesis.
Version diff first on any "optimize" ask (stamp in `docs/references.md`:
2.1.258). Doctrine-only kit diffs skip the codex gate; anything with a shell
surface does not. Research → combined summary → discussion before edits.
