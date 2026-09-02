---
name: agent-teams
description: Orchestration playbook for parallel multi-agent work in Claude Code. Use when fanning out genuinely parallel, independent work — N independent modules, multi-lens review, competing-hypothesis debugging, backend+frontend that must agree on a contract. Defaults to background subagents (with worktree isolation only when they write files in parallel and merge later); covers when to reach for Workflows instead. Covers the lead's pipeline (plan → parallel execute → review → merge), per-role models, worktree/merge flow, and the plan-approval gate.
---

# Parallel multi-agent playbook (lead-side)

This skill is the lead/orchestrator's reference for fanning out parallel work.
Only the lead orchestrates and spawns — workers implement and report back.

## 1. Fan out only when work is genuinely parallel

Parallel agents cost significantly more tokens than one session (each is a full
Claude instance). Reach for fan-out only when parts are **independent and run at
the same time**:

- N independent modules/files with no shared edits
- multi-lens review (security / performance / tests) at once
- debugging with competing hypotheses
- backend + frontend that must agree on a contract

For **sequential** work (plan → build → ship), a dependency chain, or same-file
edits, do NOT fan out — run it through the `feature-workflow` skill, whose
delegated execute spawns one `step-executor` per step on the session's own
branch. The value here is the parallel **execution** phase only.

## 2. Pick the mechanism (this is the important decision)

| Mechanism | Use when | Coordination | Cost / overhead |
|-----------|----------|--------------|-----------------|
| **Background subagents** *(DEFAULT)* | independent units; contracts known up front | none — contract pre-specified in each prompt | low; in-process, no setup |
| **Workflows** | large fan-out (10s+), deterministic/repeatable orchestration, cross-checking/voting, resumable runs | script variables | medium; you write/run a script |

Default to **background subagents** (`Agent` tool, no `name`). `team-executor`
sets `background: true` in its frontmatter — the documented way to make a
subagent always run in the background; for ad-hoc spawns say "in the background"
(`run_in_background: true` on the Agent call also works on current builds). They
run **in-process** under the lead (no separate OS process), need
**no shutdown handshake**, and deliver a clean completion notification.
Pre-specify any cross-unit contract in each spawn prompt so they never need to
talk to each other.

Reach for **Workflows** when the fan-out is large or you want deterministic,
repeatable, resumable orchestration with built-in cross-checking. (In this kit
only the lead runs Workflows — the worker roles' `tools` lists deliberately omit
the Workflow and Agent tools, so they can't fan out on their own. That's a kit
choice, not a platform rule: since v2.1.172 a subagent whose `tools` includes
`Agent` can spawn nested subagents, up to a harness-enforced depth limit.)

## 3. Worktree isolation: every concurrent writer gets one

You're in this skill because the fan-out decision already came back "parallel"
— that call is made *before* `agent-teams` loads, per the global CLAUDE.md rule
("Inside a pipeline, delegation is the default … If one subagent can do it, use
one") and `feature-workflow`'s "When to offer (lead only)" bullet. So within a
fan-out the rule is simple: **writers that run concurrently get `isolation:
worktree` each** — even if the plan says their files are disjoint. Read-only
fan-out (review, research, multi-lens analysis) never gets a worktree,
regardless of count — nothing is written, so isolation is pure overhead.

**You don't decide this per spawn.** `team-executor` carries `isolation:
worktree` in its own frontmatter, so every executor gets a worktree whether or
not the spawning prompt remembers to ask. That's deliberate: the decision was
already made when you picked the parallel path, and a rule that has to be
re-derived at each spawn is a rule that gets skipped.

**If you get here with only one writer, that's not an agent-teams run.** It
means the fan-out decision was wrong or skipped — stop, and hand the work to
`feature-workflow`'s sequential delegated execute, which spawns `step-executor`
on the session's own branch with no worktree and nothing to merge.

**Set `worktree.baseRef` to `"head"` before the first fan-out.** Subagent
worktrees branch from the repository's *remote default branch* unless you
change this — so with the default (`"fresh"`), every executor starts from a
clean `origin/main` that has neither `docs/prompts/<feature>-plan.md` nor any
of the session's in-progress commits, and the merger then drags main↔branch
divergence into each unit. `settings.example.json` ships `{"worktree":
{"baseRef": "head"}}`; the docs name this exact case ("use this when isolating
subagents that need to operate on in-progress work" —
[docs](https://code.claude.com/docs/en/worktrees#choose-the-base-branch)).
A worktree is also a fresh checkout, so gitignored files don't come along —
add a `.worktreeinclude` if executors need `.env` or similar to run tests.

**Why "disjoint files" isn't a safe reason to skip worktrees with 2+ writers.**
Disjointness isn't knowable at spawn time. *(Observed, 20 sessions reviewed):*
of 3 genuinely-parallel execute batches, 2 collided — in `claude-watch`, units
U0+U3 and separately U2+U5 all edited the CLI entrypoint despite being planned
as independent. A new unit usually has to register itself in some hub file (a
dispatcher, router, barrel export, `package.json`) that the plan assigned to
nobody. Only one batch (wizards U1/U2) was genuinely clean. Plan around this:
**if units keep colliding on a hub file, give that file to one unit** instead
of isolating three agents that all want to edit it — prefer fewer, larger
units over more, smaller colliding ones.

**Why review needs a separable diff.** `team-reviewer` reviews "its worktree
diff" and `team-merger` merges each unit in turn after approval; the global
`/codex` ship gate challenges the merged feature diff once, but the reviewer
still needs a per-unit diff. With 2+ concurrent writers sharing one checkout there is no per-unit
diff to review or merge independently, and a unit that fails review can't be
dropped without untangling it from the others it shares a tree with.

> **Deliberate deviation (from the platform docs' file-overlap test):** the
> [docs](https://code.claude.com/docs/en/agents) key worktree isolation to
> whether tasks touch the same files. This kit keys it to concurrent-writer
> count instead — a stricter test (a superset of the docs' cases): even units
> with disjoint files get worktrees the moment 2+ of them write at the same
> time, because disjointness can't be verified at spawn time and review needs a
> separable diff either way.

**Clean up after merge — nothing else will.** Once a unit lands, the merger
removes its worktree (`git worktree remove`) and deletes the merged branch
(`git branch -d`) immediately after each successful merge. That is not a
tidiness step: **neither platform cleanup path ever reclaims an executor
worktree.** Claude Code auto-removes a subagent worktree only if the subagent
made no changes, and the periodic `cleanupPeriodDays` sweep skips any worktree
still holding work — changed files, untracked files, or **unpushed commits** —
which describes every executor worktree by construction, since executors commit
locally and never push ([docs](https://code.claude.com/docs/en/worktrees#clean-up-subagent-and-background-session-worktrees)).
If the merger doesn't remove it, it stays until someone runs `git worktree
remove --force` by hand. For a run that dies before the merger gets there, the
backstop is the lead's end-of-run check that no feature worktrees/branches
remain. The net result: nothing lingers on disk once work
is merged, and there is no pane or process to tear down.

## The pipeline

```
1. PLAN      (LEAD in native plan mode; subagents draft + validate)
   → the LEAD calls EnterPlanMode, then spawns team-planner (fable, medium), which
     RETURNS the plan as text (units, file boundaries, shared contracts, open
     decisions) — subagents can't write files while the lead is in plan mode
   → the LEAD writes it verbatim to the plan file, spawns team-plan-reviewer
     (read-only) to validate it against the code, splices in any blocking
     fixes from a fresh planner spawn, resolves the open decisions with one
     AskUserQuestion, then calls ExitPlanMode.   ← only gate
   → on approval: copy the plan file to docs/prompts/<feature>-plan.md, commit,
     and mirror the units into the native task list (one task per unit, `owner`
     = the executor that gets it, `addBlockedBy` for any cross-unit ordering;
     REVIEW/MERGE/CODEX tasks blocked by the units) — the list is the work
     queue and the progress view (`Ctrl+T`)
2. EXECUTE   (background subagents: team-executor)   ← parallel
   → lead marks each unit's task in_progress as it spawns its executor and
     completed when the unit's report is ingested (never with red tests);
   → lead spawns one background subagent per independent unit; each gets a
     worktree from team-executor's own `isolation: worktree` frontmatter, not
     from the spawn call; contracts are pre-specified in each prompt
3. REVIEW    (subagent: team-reviewer, opus — read-only, NO worktree)
   → adversarially verifies each unit's diff before it lands
4. MERGE     (subagent: team-merger, sonnet)
   → merges each approved worktree into the base branch; after each successful
     merge removes that worktree + deletes its branch; reports completion
```

Every step delegates to a subagent except the lead's own plan-mode transcription
and gates in step 1; step 2 is the only fan-out (one background subagent per unit).
Keep the **lead thin**: it coordinates, runs the gates and the single codex challenge, and ingests summaries — it
does not read large diffs or implement. If the lead starts implementing, stop and
delegate.

**Subagents are headless — they never prompt the user.** A subagent runs to
completion and hands its result back; it has no channel to ask you anything
mid-run. So never delegate an *interactive* gate to one — `ExitPlanMode` and
`AskUserQuestion` are unavailable to a subagent, so a delegated gate either
auto-picks silently or dies. Gates run in the **lead** (the session you're
attached to); only headless work goes to subagents. (This is why step 1 splits:
subagents draft and validate headlessly, the lead transcribes and gates.)

## Approval gate: PLAN ONLY

The lead must get the **user's** approval on the plan (step 1) before any
fan-out. The gate is Claude's native `ExitPlanMode` in the lead — never a
subagent, which has no channel to the user. Resolve the open taste-decisions with
one AskUserQuestion first, then present the plan and wait.
After the plan is approved, executors run, review runs, and the merger lands work
and reports completion.
5. CODEX     (lead launches `codex exec` as one background Bash; `codex-triage` agent triages)
   → ONE `Skill(codex, "challenge <feature-base>..<base-HEAD>")` on the merged
     feature diff — full output to a file, triaged verdict shown; P0/P1 (plus
     adjacent P2s) → fresh Sonnet fixer on the base branch → re-challenge until
     convergence (feature-workflow stage 5 rules: a non-decreasing P0/P1 round
     forces the structural branch, two non-decreasing rounds end the loop;
     standalone-P2/test-gap/theoretical → one fix-now / defer-to-tech-debt
     question). No further user gates before that.

## No `/goal`

The approved tail (EXECUTE → REVIEW → MERGE → CODEX) runs unprompted from plan
approval: the lead spawns, ingests summaries, and moves on without returning to
the user except at the real gates (a P1 still open at codex round 3, the
test-gap/theoretical fix-or-defer question, push approval). Roles still return
machine-checkable proof — test exit code + output tail, `git worktree list` /
`git status`, structured per-unit verdicts — because the lead judges completion
from those, not from prose "done".

## Models + effort per role

Per-role `model:` and `effort:` come from the agent definition files and are
honored when the role runs as a subagent. Judgment roles run on the top tier at
moderate effort; high-volume roles run on Sonnet.

| Role | Spawned as | Model | Effort | Rationale |
|------|-----------|-------|--------|-----------|
| Orchestrator (lead) | main session | Fable 5.1 | medium (`/effort medium`, persisted per model) | coordination, transcription, gates; cache re-reads at a quarter of Fable 5's price and half Opus 5's — experiment from 2026-09-02, reviewed after one arc (before: Opus 5, session default) |
| `team-planner` | subagent | Fable 5.1 | medium | one pass, highest leverage; Fable 5.1 guide: `medium` ≈ Fable 5 quality, and lower effort often beats prior-tier models on cost per task — experiment from 2026-09-02, reviewed after one arc (before: Opus 5 high); returns text, lead transcribes |
| `team-plan-reviewer` | subagent | Fable 5.1 | medium | validates the plan against the code before the gate; read-only. Same experiment as the planner — the whole-codebase read that justified `high` on Opus is re-tested at Fable's `medium` |
| `team-executor` | **background subagent** | Sonnet (Opus only when the plan justifies it) | high | token-heavy fan-out; Sonnet 5 guide: high for most work, xhigh only for the hardest |
| `team-reviewer` | subagent | Opus | medium | adversarial bug-hunting on a bounded diff (Opus 5 review stays accurate at lower effort) |
| `team-merger` | subagent | Sonnet | medium | mechanical merge/verify |
| `explorer` | subagent | Sonnet | medium | codebase search, read-only (built-in `Explore` runs on the lead's model capped at Opus since 2.1.257) |

The global spawn-pin rule applies; the table above is this pipeline's role→model
mapping. Override per spawn only when the plan marks a unit Opus with a reason. As background subagents these roles honor their `effort:`
frontmatter.

## Spawn prompt contract (the lead writes these inline)

Each executor is a background subagent with **no inherited context** — it never
sees this conversation, the plan file's surrounding discussion, or its siblings.
So each spawn prompt must stand alone. Write it yourself as you spawn: it's a
handful of tool calls' worth of text per unit, and routing it through a separate
prompt-writing agent only puts the same words through another context on the way
back to you.

State the unit's **goal and its boundaries**, then stop — don't enumerate
procedure. Sonnet 5 takes an explicit scope statement literally, which is what
earns it its place; step-by-step instructions written for prior models reduce
quality on current ones.

Every prompt carries:
- **Scope + ownership** — what the unit is for, the files it owns, and the files
  it must not touch. Ownership is disjoint across units by construction; a hub
  file belongs to exactly one unit.
- **The full cross-unit contract** it must honor (API shapes, types, names),
  baked in. Background subagents don't talk to each other, so anything it needs
  from a sibling has to be in the text.
- **Acceptance criteria and how to verify them** — the tests or commands that
  prove the unit is done. State them once; no "re-verify" or "double-check"
  rituals.
- **The worktree/branch** it works in, and the retirement budget verbatim: "if
  you exceed ~200k context or ~250 turns — commit WIP, write a handoff file to
  the scratchpad, and stop".
- **The model pin** from the table above (`sonnet`, or `opus` only where the
  approved plan marks that unit Opus with a reason) — set via the Agent tool's
  `model:` parameter on the spawn call, not text inside the prompt.

One concern per prompt, sized so the executor finishes in roughly ≤100 tool
calls — a unit bigger than that was planned too large; split it. A fixer prompt
carries exactly one finding set, never several. Nothing in a prompt goes beyond
the approved plan.

## Spawn recipes

Plan (lead in plan mode; subagents draft + validate), then gate:
> [EnterPlanMode] Use the team-planner agent to return a ROUGH implementation plan
> for <feature> as text — units, file boundaries, shared contracts, open decisions.
> I write it to the plan file, have team-plan-reviewer validate it, resolve the open
> decisions with the user, and get approval via ExitPlanMode before any execution.

Fan out execution (background subagents that write + merge → worktree), after approval:
> Spawn one team-executor as a background subagent per unit in the approved plan,
> with **no name** (team-executor's `background: true` and `isolation: worktree`
> frontmatter already handle backgrounding and the per-unit worktree).
> Give each a self-contained spawn prompt per the contract above (the cross-unit
> contract is baked in, so they don't message each other). Notify me when each
> completes.

Review + merge (subagents; reviewer is read-only, no worktree):
> Use team-reviewer to adversarially verify each unit's diff, then team-merger to
> merge approved worktrees into the base branch, run tests, and report completion.

Read-only fan-out (no worktree) — e.g. multi-lens review with no executors:
> Spawn 3 background subagents to review this change in parallel — one on
> security, one on performance, one on test coverage — and report findings. No
> worktrees; they only read.

For a large or repeatable fan-out, consider a **Workflow** instead of hand-
spawning subagents: a deterministic script (plan → fan-out → review → merge) that
scales to many units, cross-checks results, and resumes if interrupted.

## Relationship to the feature workflow

This is the parallel-execution variant of the `feature-workflow` skill's pipeline; its stage-5 codex rules (per-feature range, P0/P1 convergence loop, tech-debt deferral) apply verbatim.
Planning (`/office-hours`, native plan mode) and shipping (`/ship`,
`/land-and-deploy`) are unchanged; fan-out only replaces the execute phase's
sequential per-step subagents with parallel agents when the steps are
independent.
