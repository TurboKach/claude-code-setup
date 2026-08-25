# Review-cadence redesign + recovery rules (doctrine update)

## Context

Forensics on four sessions (clipsy iOS carousel arcs 2–3 + backend, 2026-08-23..25) showed the end-of-arc codex loop is the dominant cost: arc-2's loop ran 12 rounds (~1.0M output tokens — as much as the 11-step build), arc-3's ran 7h29m (60% of active time) with P1s *regressing* 8→8→10 until an Opus structural fixer broke the plateau. Bugs compound across unreviewed steps (14 P1s at once over 11 steps); fixes introduce same-mechanism regressions; the loop had no standing exit rule (owner imposed one live at hour 6). Separate findings: an 8.5h overnight stall with a finished test-suite notification left unconsumed (then answered "Not sleeping" and re-ran the suite), a 3h17m outage stall, a 6.4h unbounded xcodebuild call, an ENOSPC from accumulated review worktrees, and a three-file disagreement over Opus fixers. The owner approved a 14-item spec (conversation, 2026-08-25); research verified alignment with Anthropic best-practices ("adversarial review step", failing-test-first) and OpenAI repair-loop guidance (delta-plateau stopping). Prior art constraint: commit `eac1896` removed a char cap on a reviewer because caps suppress findings — **no new char caps anywhere**.

**Execution locus: the main session edits directly — owner's explicit override of the master-writes-zero-product-code gate for this doctrine-only arc (AskUserQuestion, 2026-08-25).** Codex ship gate: **skipped** per the decided rule for doctrine-only kit diffs (memory `codex-gate-scope-doubt`, 2026-08-22).

## Design decisions

- **One `codex-triage` spawn per round, fed all slice files.** Replaces N-triage-plus-master-hand-dedup. codex-triage.md widens from "exactly one output file" to "one round's output file(s)", merging and deduping across slices into the single verdict. No separate consolidator agent, no caps.
- **New `agents/spec-reviewer.md`** (Sonnet, effort medium, read-only tools, maxTurns 60) for the final-gate spec-conformance pass — kit agents are self-contained by design, and no existing agent fits (team-reviewer is Opus/per-unit). install.sh copies `agents/*.md` wholesale; only its `echo` listing (install.sh:168) needs the name added.
- **P0 added above P1**: P0 = crash, data loss, security, or a regression breaking a core flow — fixed immediately, always blocks ship. P1 = wrong behavior in normal use; any other regression is ≥P1, never P2. P2 = real but pathological-input-only. test-gap/theoretical unranked, never looped. Replaces "P1 = wrong behavior, crash, data loss…; a regression is always P1" everywhere it appears.

## Steps (all: main session, per override)

### Step 1 — `skills/feature-workflow/SKILL.md` stage 4 + stage 5

Stage 4:
- Add per-step review cadence: after a step's commit lands, the master launches a codex challenge on that step's diff (`<prev-step-sha>..<step-sha>`) as one background Bash (same launch pattern as stage 5, pinned worktree since the next executor is writing) while the next step's executor runs; triage lands at the next step boundary; P0/P1 findings go to a fixer before the following step spawns. Per-step rounds flag only correctness/requirement gaps — no style or speculative hardening. Per-step rounds are bug-catching, **not** the gate.
- Rewrite the red-then-green passage ("revert the fix, show the test red, restore, show it green"): test-first — the test is written and run red *before* the fix is applied; one red run, one green run, both shown; the revert-restore sequence stays only as fallback for an already-written fix. Keep the rationale sentence (a suite never seen red is why bugs survive green rounds).

Stage 5:
- Adjust "ONE challenge per feature" wording: per-step rounds do not satisfy the gate; the final whole-range challenge at a single HEAD remains the gate (keep the existing out-of-diff evidence).
- Replace the P1/P2 definitions with the P0–P2 taxonomy (Design decisions above). Clean = zero P0/P1.
- Replace the fix loop ("round N of 3", round-3 stop/AskUserQuestion) with the convergence rule: loop on P0/P1 only; a round whose P0/P1 count does not strictly decrease forces the structural branch (Opus mechanism-fixer per the existing same-mechanism clause, or AskUserQuestion if it exceeds the plan's design contract) — never another patch round; exit at zero P0/P1 or two consecutive non-decreasing rounds → stop, defer remainder, report.
- Add P2 adjacency to fix routing: a fixer's set includes any P2 sharing a file or mechanism with its P1s; standalone P2s keep going to the close-out fix-or-defer question.
- Replace the deferral entry format ("file:line, description, why deferred, verdict-file path") with the index format: one line per entry — `[P2 conf:0.6] file:line — summary → docs/reviews/<verdict-file>.md #finding-N`; descriptions stay in the committed verdict file.
- Add the spec-conformance pass: at the final gate, in parallel with the whole-range challenge, one `spec-reviewer` spawn (Sonnet) reviews `<feature-base>...HEAD` against the approved plan file — unimplemented/incomplete requirements, scope creep, wrong-logic-vs-spec; gaps only. Missing requirements route to the P0/P1 lane; scope creep is reported at the gate.
- Multi-slice rounds: one codex-triage spawn reads all slice files (update the "three concurrent runners… consolidate into one triaged verdict" passage to name the actor).

Acceptance: no occurrence of "round N of 3", the old red-green mechanics, or the old deferral format remains in the file; stage 4/5 read coherently start to end.

### Step 2 — `skills/feature-workflow/SKILL.md` Token discipline

- Pin-or-serialize passage: state the refinement — pinned worktree only when a writer runs concurrently (per-step overlap is the normal case); no writer in flight → live tree. Add: the worktree is removed (`git worktree remove`) in the same turn its round's triage returns — accumulated review checkouts contributed to the 2026-08-24 ENOSPC — and a `df` free-space check (≥10GB) precedes every worktree pin, failing loudly instead of burning the launch.
- Codex-launch pattern: the background Bash wrapper carries a built-in retry loop — up to 3 attempts, 5-minute spacing — so an API/CLI outage during an unattended run self-heals. Also applies to backgrounded full-suite runs.
- Test watchdog: long test invocations run backgrounded with an explicit generous `gtimeout` (3600s), never unbounded — a single `xcodebuild test` call "ran" 6.4h on 2026-08-23. Fold the arc-3 external-kill check into this step's execution: read `~/.claude/settings.json` for `BASH_MAX_TIMEOUT_MS`; if the two arc-3 full-suite kills match the cap, say so in the passage (backgrounded runs with explicit gtimeout are the fix either way).
- Verdict contract: add P0 to the prefix scheme (`[P0 conf:0.9]`), note the triage agent may receive several slice files for one round and returns one merged verdict. Keep the ≤2,000-char verdict shape as-is (it's a summary contract with lossless-P0/P1 rules, not a finder cap).

Acceptance: taxonomy, retry, watchdog, preflight, and cleanup all present; no contradiction with stage 4/5 text from Step 1.

### Step 3 — agent files

- `agents/codex-triage.md`: "one round's output file(s)" (merge + dedupe across slices, one verdict); P0–P2 definitions replacing the P1/P2 sentence; P0 prefix in the format line.
- `agents/fixer.md`: rewrite the red-then-green proof rule to test-first (red before fix; revert dance as fallback); add one line: the spawn prompt may include adjacent P2s sharing the file/mechanism of the set's P1s — they are in scope. Frontmatter description gains the Opus carve-out pointer ("Sonnet at effort medium; Opus only for a same-mechanism structural fix, with the reason stated at spawn").
- New `agents/spec-reviewer.md`: self-contained; Sonnet, effort medium, `tools: Read, Glob, Grep, Bash`, maxTurns 60; brief — read the named plan file and diff range, report gaps only (unimplemented/incomplete requirements, scope creep, wrong-logic-vs-spec), each as one `file:line — summary` line tagged `[missing-requirement]` / `[scope-creep]` / `[wrong-logic]`; no style findings, no fixes; quote owner chat messages verbatim (kit convention).
- `install.sh:168`: add spec-reviewer to the echo listing.
- `agents/step-executor.md`: no change (per-step review is master-side).

Acceptance: each file internally consistent; spec-reviewer.md follows the kit's agent-file pattern (frontmatter + self-contained rules).

### Step 4 — `global/CLAUDE.md` + `README.md`

- CLAUDE.md model-pin list (Operations, line 39): after "`opus` for planner / plan-reviewer / team-reviewer, and for an executor only when the plan marks that step Opus with a reason" add "and for a fixer only in the same-mechanism structural case (reason stated at spawn)". Ends the three-file disagreement — 6 legitimate Opus-fixer spawns in the 08-23..25 arcs read as violations.
- CLAUDE.md "silence is not progress" clause (same paragraph): add the retry counts — a subagent dead on an API error is respawned up to 2 times (transcript salvaged first) before parking with a PushNotification; and the wake-after-gap rule as its own Operations bullet: on resuming after any gap, drain pending task-notifications first and read what completed; state the elapsed time plainly; never re-run work whose finished result sits unconsumed. State the honest limit: a master-side request killed mid-outage with its harness retry cancelled (Esc) or exhausted cannot self-resume.
- CLAUDE.md hard gate `/codex` ship gate (line 28): unchanged except it must not contradict per-step rounds — verify wording still says the *whole-diff* challenge is the gate.
- README: update the fixer row (red-then-green → test-first phrasing), codex-triage row (slice files), add spec-reviewer row; add a changelog entry in the `Decisions` list style (date 2026-08-25, the arcs' evidence: 12-round/7-round loops, plateau data, 8.5h unconsumed notification, taxonomy + convergence + per-step cadence changes).

Acceptance: CLAUDE.md diff ≤ ~12 lines changed; README table matches the agent files.

### Step 5 — consistency sweep (verification)

Grep the repo for stale references; fix any hit:
- `round N of 3`, `round 3` (loop context), `revert the fix, show the test red`
- `P1 = wrong behavior, crash` (old taxonomy), `a regression is always P1`
- old deferral format text (`why deferred`)
- `exactly one finished` (codex-triage description), `ONE gstack` (should now read as final gate only)
- skills/agent-teams/SKILL.md `CODEX (lead)` line and any other cross-file mention of the loop cap or taxonomy.
Run `hooks/tests/*.test.sh` only if any hook was touched (none planned). Show the clean grep output as the completion evidence.

## Commit plan

Two commits, evidence-bearing messages in repo style:
1. `Per-step review cadence, P0 taxonomy, and a convergence rule for the fix loop` — SKILL.md stages 4/5 + token discipline, codex-triage.md, fixer.md, spec-reviewer.md, install.sh, README (body: arc-2 12 rounds ≈ build cost, arc-3 8→8→10 plateau broken by structural fixer, seam-bug evidence, eac1896 no-caps constraint, Anthropic/OpenAI alignment).
2. `Wake-after-gap honesty, outage retry counts, and run watchdogs` — global/CLAUDE.md + SKILL.md recovery bits + README changelog (body: 8.5h unconsumed notification + "Not sleeping", 3h17m 529 stall, 6.4h unbounded xcodebuild, ENOSPC).

No push without approval. Codex gate skipped (doctrine-only kit diff, decided 2026-08-22).
