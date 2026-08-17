# Plan: codex gate invocation, `/goal` scope, executor granularity — 2026-08-17

Session forensics (2026-08-13 → 08-17: 36 sessions, 191 executor spawns) found four recurring
misses. (1) The `/codex` gate ran as the OpenAI plugin agent `codex:codex-rescue` 33× — one clipsy
session had all 29 "codex review" gates as codex-rescue and zero gstack `/codex` calls; the owner
objected twice ("it doesn't mean codex-rescue, it means codex challenge"). Doctrine only ever says
"`/codex review`" and never names the invocation. (2) `/goal` conditions were 4-clause compound
texts ("zero real-or-regression findings … verdict pasted in full … max 3 rounds … or stop after N
turns"); the evaluator is the small/fast model judging the transcript only, so those produced 13
stop-hook rejections in 5 minutes (planner) and forced extra "confirmation" codex rounds after fix
rounds had shown non-zero findings (wizards: "28 real defects across 14 rounds… all remediated"
still judged unmet). (3) 104 of 191 executor spawns were fixers; a 5-step wizards plan became 39
executor spawns + 40 codex runs in 5.5 h; the round-3 cap was passed (8 fixer rounds on one step);
P2/docs findings were looped on for 42–66 min despite the "test-gap/theoretical never looped" rule.
Executor spend is a long tail: median 30 tool calls / 70k peak context, but the top-10 (all clipsy
iOS, e.g. "Arc3 playtest 4: color list + selection panel/deselect", "Step 7: snapshot evidence") ran
134–195 calls at 300–390k peak — bundled concerns plus raw xcodebuild/test logs in context — and blew
past the "~200k context or ~250 turns" retirement rule without retiring. (4) Master sessions averaged
250–310k context per call, peaking 400–500k in five sessions (drivers: codex verdicts pasted in
full, whole subagent reports, images) → repeated "context is full, write me a handoff". The model
split is fine (89% of execution on Sonnet 5 at effort medium; planning on Opus/Fable; review = Codex
+ master triage) and is not touched.

**Stage 3 (`/autoplan`) is skipped**: every taste decision was made interactively by the owner —
(a) the gate is gstack `/codex` in **challenge** mode scoped to the step's accumulated diff, never
`codex:codex-rescue`, `/codex review` only when asked by name; (b) `/goal` keeps driving only the
post-approval tail (stages 4–6) but with a one-end-state template, and the stage-5 inline fix-loop
goal is deleted; (c) plan steps sized to ≤~100 executor tool calls, one concern per spawn, build
output filtered before it enters context (retirement backstop stays ~200k/~250 — owner's call at approval); (d) full
challenge output goes to a file (session scratchpad by default) and the master shows only the
triaged verdict + path. The diff is doctrine text with no design/CEO dimension.

**Explicitly out of scope**: no hook-based enforcement of the round cap; no progress-heartbeat rule;
no model reassignment (and no new Opus-5-vs-Sonnet-5 equivalence claims — the docs only compare
Opus 5 to Sonnet 4.6); no changes to gstack skills (`/gstack-upgrade` hard-resets them).

---

## Step 1 — repo edits + live `~/.claude` mirror

**Executor: `step-executor`** (model `sonnet` — every edit is spelled out below). Repo
`/Users/turbokach/Dev/claude-code-setup`, branch `master`. Read each target file in full before
editing; anchors are line numbers as of `db494e2`. Quote-level precision matters: replace exactly
the quoted text, reflow nothing else, touch no adjacent bullet.

Convention: `global/CLAUDE.md`, `skills/*/SKILL.md`, and `agents/*.md` are sources whose live copies
in `~/.claude` are byte-identical today. `install.sh` refreshes skills/agents (back-up-then-replace)
but never clobbers an existing `~/.claude/CLAUDE.md` (`install.sh:38-39`), so CLAUDE.md is mirrored
by hand.

### 1a — `global/CLAUDE.md`

**:29** — the `/codex` merge-gate bullet. Replace the whole bullet:

> - **`/codex` merge gate.** Never merge a pipeline step until `/codex review` has run on that step's diff and its verdict is shown. Internal reviewer subagents do NOT satisfy this gate. If `/codex` hasn't run, say "unreviewed, not merging".

with:

> - **`/codex` merge gate.** Never merge a pipeline step until gstack's `/codex` skill has run in **challenge** mode on that step's accumulated diff — `Skill(codex, "challenge <step-base-sha>..HEAD")`, in the master or in a fresh `general-purpose` runner that invokes that Skill — and its triaged verdict is shown. NEVER `codex:codex-rescue` (the OpenAI plugin agent that hands Codex a coding task — not a review, does not satisfy this gate). Bare `codex exec` only if the gstack skill is unavailable, and say so; `/codex review` (pass/fail mode) only when I ask for it by name. Internal reviewer subagents do NOT satisfy this gate. If `/codex` hasn't run, say "unreviewed, not merging".

**:49** — in "It holds the six-stage pipeline (discuss → plan → autoplan → delegated execute → `/codex` review → ship)", replace "`/codex` review" with "`/codex` challenge". Nothing else on the line changes.

`:54` (gstack bullet, "then `/codex` for cross-model review") stays as is.

### 1b — `skills/feature-workflow/SKILL.md`

**:3** (frontmatter `description:`) — replace "→ /codex review → ship" with "→ /codex challenge → ship". Nothing else on the line changes.

**:17** (stage 4 **Execute**) — append to the end of the item, after "…and explicit instructions compound into waste.":

> Size and split spawns here, not later: a plan step is sized so a step-executor finishes in roughly ≤100 tool calls (split it in the plan if it can't), and every spawn carries exactly one concern — one step, or one fix. Never bundle several playtest fixes, regressions, or finding sets into a single spawn; a fixer gets the plan section, the unit diff, and the one finding set it is fixing.

(Placed in stage 4 rather than stage 2/3 because it governs every spawn — and 104 of 191 spawns were fixers, which never appear as plan steps; stage 2's "rough is fine" drafting inherits the ≤100-call sizing from here.)

**:18** (stage 5) — replace the whole item with:

> 5. **Independent review per step** → gstack `/codex` in **challenge** mode on the step's accumulated diff at the step boundary — `Skill(codex, "challenge <step-base-sha>..HEAD")`, where `<step-base-sha>` is the commit the step started from (the master records it before spawning); run it in the master or in a fresh `general-purpose` runner agent that invokes that Skill. Never per fixer commit; never `codex:codex-rescue`; bare `codex exec` only if the gstack skill is unavailable, and say so; `/codex review` (pass/fail) only when the user asks for it by name. Triage real / regression / test-gap / theoretical. **Clean = zero real-or-regression findings.** Test-gap and theoretical findings are reported to the user, never looped on. Re-challenge only after substantive fixes, label every round "round N of 3", and hard-stop at round 3 surfacing the remainder — a 4th round is a defect signal, not diligence. A step with no repo diff needs no verdict. Claude reviewer agents run at effort medium (review accuracy holds at lower effort — Opus 5 guide); reserve high for one final gate pass if the step was architecturally hard.

(This deletes the sentence "Drive the fix→re-review cycle with a bounded `/goal`: …" — that inline goal was the thrash source.)

**:27** ("Drive the post-approval tail" bullet) — replace the text from "The evaluator judges only the transcript and runs no tools, so each role must surface machine-checkable proof (test exit codes + output, `git status`, structured per-unit verdicts), not just "done". Example: `/goal all units in docs/prompts/<feature>-plan.md are merged to <base>; the reviewer approved each diff; the project's test suite exits 0 with its output shown; git status is clean and no feature worktrees/branches remain; or stop after 25 turns`." with:

> The evaluator is the small/fast model judging the transcript only, running no tools — so a condition states one measurable end state plus the turn bound and never enumerates per-round mechanics; each role still surfaces machine-checkable proof (test exit codes + output, `git status`, the triaged verdict) rather than "done". Template: `/goal every step of docs/prompts/<feature>-plan.md is committed on <branch>, each with a /codex challenge verdict shown (fix rounds allowed; hard-stop at round 3 with the remainder reported); or stop after <N> turns`. A step with no repo diff needs no verdict.

**:52** ("Fresh agent per review round") — replace "One review round = one fresh wrapper agent — a round needs only the diff range and prompt, never prior rounds' accumulated context." with "One challenge round = one fresh runner agent invoking `Skill(codex, "challenge <step-base-sha>..HEAD")` — a round needs only the diff range, never prior rounds' accumulated context." Keep the second sentence unchanged.

**:53** ("Verdict size contract") — replace the whole bullet with:

> - **Verdict size contract.** Full challenge output is written to a file — the session scratchpad by default (keeps review noise out of product repos), or `docs/reviews/<step>-round<N>.md` when the project wants the record — and the master shows only the triaged verdict ≤2,000 chars (counts, one-line findings with file:line, real/regression/test-gap/theoretical tags) plus that file path. Never paste a verdict in full. The master NEVER Reads challenge-output files.

### 1c — `agents/step-executor.md`

After **:37** (end of the 600000 ms timeout bullet, which stays) append one bullet:

> - Filter build and test output before it enters your context — e.g.
>   `xcodebuild … 2>&1 | xcbeautify --quiet`, `xcodebuild … 2>&1 | tail -n 60`,
>   `npm test 2>&1 | tail -n 80`, or `grep -nE 'error:|failed'` — never dump a raw
>   build or test log. Raw logs are what push executors past their budget.

### 1d — `agents/team-executor.md`

After **:32** (end of "Hard rules") append two bullets, in this file's voice:

> - Budget: if you exceed ~200k context or ~250 turns, commit `WIP:`, write a
>   handoff file to the scratchpad, and stop — report the handoff path.
> - Filter build and test output before it enters your context — e.g.
>   `xcodebuild … 2>&1 | xcbeautify --quiet`, `xcodebuild … 2>&1 | tail -n 60`,
>   `npm test 2>&1 | tail -n 80`, or `grep -nE 'error:|failed'` — never dump a raw
>   build or test log.

### 1f — `docs/decision-flow.md`

**:47** — replace `Stage 5 — <b>/codex review</b> per step's diff<br>⛔ hard gate: no merge without a verdict` with `Stage 5 — <b>/codex challenge</b> per step's diff<br>⛔ hard gate: no merge without a triaged verdict`. Nothing else in the file.

### 1g — `skills/agent-teams/SKILL.md` (wording only, no restructuring)

**:213-214** — replace "team-reviewer approved each diff and `/codex review` reports zero\nreal-or-regression findings on each unit's diff;" with "team-reviewer approved each diff and each unit has a `/codex challenge` verdict shown\n(fix rounds allowed; hard-stop at round 3 with the remainder reported);". Lines 212 and 215-216 unchanged.

**:222-224** — replace the fix-loop goal body with:

```
/goal every unit's diff has team-reviewer approval and a `/codex challenge` verdict shown
(fix rounds allowed; hard-stop at round 3 with the remainder reported); or stop after 12 turns.
```

`:118` ("`/codex` merge gate forbids…") stays.

### 1h — `README.md`

No edit: `:23` says "`/codex` merge gate" and `:149` names `/goal` generically; neither states the invocation. Confirm with the greps below.

### 1i — mirror refresh

- `cp global/CLAUDE.md ~/.claude/CLAUDE.md`
- `./install.sh` (or `cp` the four files) to refresh `~/.claude/skills/feature-workflow/SKILL.md`, `~/.claude/skills/agent-teams/SKILL.md`, `~/.claude/agents/step-executor.md`, `~/.claude/agents/team-executor.md`.
- One commit on `master`, message naming the forensics origin. **No push.**

**Acceptance**
- `grep -rn "codex review" global skills agents docs/decision-flow.md README.md` → only the two "only when the user asks/I ask for it by name" clauses (CLAUDE.md:29, SKILL.md stage 5). Historical plans under `docs/prompts/` are not edited and are excluded.
- `grep -rn "pasted in full" global skills agents docs README.md` → nothing (the historical `docs/prompts/*` are excluded — they are records).
- `grep -rn "codex-rescue" global skills agents docs/decision-flow.md README.md` → only the two NEVER clauses (CLAUDE.md:29, SKILL.md stage 5).
- `grep -rn "200k context or ~250 turns" agents skills` → step-executor, team-executor, team-prompt-smith, feature-workflow (team-executor is the new one).
- `diff -q` identical for each pair: `global/CLAUDE.md` ↔ `~/.claude/CLAUDE.md`, `skills/feature-workflow/SKILL.md`, `skills/agent-teams/SKILL.md`, `agents/step-executor.md`, `agents/team-executor.md` ↔ their `~/.claude/...` copies.
- `git diff` shows only 1a–1d, 1f, 1g; `git status` clean apart from the commit.

---

## Step 2 — gate (master session)

Record `<base>` = `db494e2` (the commit Step 1 starts from). After Step 1's commit lands, run
`Skill(codex, "challenge db494e2..HEAD")` in the master (or a fresh `general-purpose` runner that
invokes it); save the full output to the session scratchpad; show only the triaged verdict (≤2,000
chars, real/regression/test-gap/theoretical) plus the file path. Real/regression findings → one fresh
`step-executor` per finding set (this plan's section + the diff + that finding set), then
re-challenge; label rounds "round N of 3", hard-stop at round 3 with the remainder reported.
Test-gap/theoretical findings are reported, not looped. The Step 1 commit is accepted only after
the verdict. **No push** — the owner approves pushes separately.
