---
name: agent-teams
description: Orchestration playbook for Claude Code agent teams (experimental parallel multi-agent). Use when fanning out genuinely parallel work — backend+frontend in parallel, N independent modules, competing-hypothesis debugging, multi-lens review — across teammates that coordinate via a shared task list and direct messaging. Covers the lead's pipeline (plan → prompts → parallel execute → review → merge), per-role models, worktree/merge flow, the plan-approval gate, and iTerm2 split-pane layout.
---

# Agent Teams playbook (lead-side)

This skill is the lead/orchestrator's reference for running a Claude Code agent
team. Teammates read it too, but the orchestration here is the **lead's** job —
only the lead spawns agents.

## Use a team only when work is genuinely parallel

Teams cost significantly more tokens than one session (each teammate is a full
Claude instance). Reach for a team only when parts are **independent and run at
the same time** and benefit from teammates talking to each other:

- backend + frontend developed in parallel that must agree on a contract
- N independent modules/files with no shared edits
- debugging with competing hypotheses (adversarial cross-talk)
- multi-lens review (security / performance / tests) at once

For **sequential** work (plan → build → ship), a pipeline with dependencies, or
same-file edits, do NOT use a team — use the multi-session workflow or plain
subagents. The team's value is the parallel **execution** phase only.

## Hard constraints (verified against the docs)

- **One team per session. The lead is fixed** for the session's lifetime.
- **Only the lead spawns.** No nested teams — a teammate cannot spawn teammates.
  So sequential pipeline steps (plan, prompt-prep, review, merge) are run by the
  lead as **subagents**; the **parallel execution** step is run as **teammates**.
- **Plan approval routes to the lead, not the user, natively.** To keep the
  human in the loop we override this below (the lead surfaces the plan to the
  user and does not auto-approve).
- **Layout is auto.** Each teammate gets its own auto-arranged iTerm2 pane;
  per-role tab grouping is impossible. Name teammates (`backend`, `frontend`,
  `exec-3`) so they're identifiable by name, not position.
- **CLAUDE.md + skills load for every teammate**, but a subagent definition's
  `skills`/`mcpServers` frontmatter is ignored when run as a teammate. Team
  tools (`SendMessage`, task tools) are always available to teammates.

## The pipeline

```
1. PLAN      (subagent: team-planner, opus)
   → produces docs/prompts/<feature>-plan.md, runs /autoplan, returns it
   → LEAD surfaces the plan to the USER and waits for approval   ← only gate
2. PROMPTS   (subagent: team-prompt-smith, sonnet)
   → turns the approved plan into one self-contained spawn prompt per executor
3. EXECUTE   (teammates: team-executor, sonnet; opus for hard modules)   ← parallel
   → lead spawns one teammate per independent unit, each in its own worktree
   → executors coordinate shared contracts via SendMessage
4. REVIEW    (subagent: team-reviewer, opus)
   → adversarially verifies each unit's diff before it lands
5. MERGE     (subagent: team-merger, sonnet)
   → merges each approved worktree into the base branch, reports completion
```

Steps 1, 2, 4, 5 are sequential and context-isolated (subagents). Step 3 is the
only fan-out (teammates). Keep the **lead thin**: it coordinates and ingests
summaries — it does not read large diffs or do the implementation itself. If the
lead starts implementing, stop and delegate.

## Approval gate: PLAN ONLY

The lead must get the **user's** approval on the plan (step 1) before any
fan-out. Surface the plan, name the open taste-decisions, wait. Do **not**
auto-approve and do **not** rely on the built-in lead-approval. After the plan
is approved, executors run, review runs, and the merger lands work and reports
completion — **no further user gates**.

## Models per role (smart + token-efficient)

Set **Default teammate model = Sonnet** in `/config` (token-efficient floor).
Per-role models come from the agent definition files:

| Role | Spawned as | Model | Rationale |
|------|-----------|-------|-----------|
| Orchestrator (lead) | main session | Opus | coordination, synthesis, user gate |
| `team-planner` | subagent | Opus | plan quality is judgment-heavy |
| `team-prompt-smith` | subagent | Sonnet | structured prompt writing |
| `team-executor` | **teammate** | Sonnet (Opus for architecturally hard modules) | bulk code |
| `team-reviewer` | subagent | Opus | catch subtle bugs |
| `team-merger` | subagent | Sonnet | conflict resolution needs care |
| researcher | subagent | (use built-in `Explore`) | broad reads, no custom file |

Override per spawn when a module is unusually hard: "spawn this executor on Opus".

## Worktrees + merge

Give each executor its own git worktree so parallel edits never collide
(`isolation: worktree` when spawning, or one worktree per teammate). Executors
own a disjoint file set. The `team-merger` subagent merges each reviewed
worktree into the base branch in turn, resolves conflicts, runs the test suite,
and reports "<unit> landed" back to the lead. Unchanged worktrees are discarded.

## Layout (decided: auto split-panes, one team)

`teammateMode: auto` is set; in iTerm2 (Python API on, `it2` installed)
teammates appear as split panes. Keep everything in **one** team so executors
can message each other — separate teams would buy cosmetic tab grouping at the
cost of cross-talk. Navigate panes by clicking, or in-process with up/down +
Enter; `Ctrl+T` toggles the task list.

## Spawn recipes

Plan (subagent), then gate:
> Use the team-planner agent to write an implementation plan for <feature> to
> `docs/prompts/<feature>-plan.md`, run /autoplan, and return it. I will get the
> user's approval before any execution.

Fan out execution (teammates), after approval:
> Spawn one team-executor teammate per unit in the approved plan, each in its own
> worktree, named for its unit (backend, frontend, ...). Give each the
> prompt-smith's spawn prompt. Have backend and frontend message each other to
> agree the API contract. Wait for all teammates to finish before merging.

Review + merge (subagents):
> Use team-reviewer to adversarially verify each unit's diff, then team-merger to
> merge approved worktrees into the base branch, run tests, and report completion.

## Relationship to the multi-session workflow

This is the parallel-execution variant of the multi-session feature workflow in
CLAUDE.md. Planning (`/office-hours`, `/autoplan`) and shipping (`/ship`,
`/land-and-deploy`) are unchanged; the team only replaces the "execute one step
per session" phase with parallel executors when the steps are independent.
