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
6. TEARDOWN  (lead, after merge + any eyeball)
   → shut each teammate down via the handshake, THEN prune worktrees/branches
```

Steps 1, 2, 4, 5 are sequential and context-isolated (subagents). Step 3 is the
only fan-out (teammates). Step 6 is the lead's own cleanup. Keep the **lead
thin**: it coordinates and ingests summaries — it does not read large diffs or do
the implementation itself. If the lead starts implementing, stop and delegate.

## Approval gate: PLAN ONLY

The lead must get the **user's** approval on the plan (step 1) before any
fan-out. Surface the plan, name the open taste-decisions, wait. Do **not**
auto-approve and do **not** rely on the built-in lead-approval. After the plan
is approved, executors run, review runs, and the merger lands work and reports
completion — **no further user gates**.

## Models per role (smart + token-efficient)

Set **Default teammate model = Sonnet** in `/config` (token-efficient floor).
Per-role model and **effort** come from the agent definition files (`model:` +
`effort:` frontmatter). Effort deviates from the model default (`high` on Opus
4.8 / Sonnet 4.6): judgment roles go **up**, high-volume roles go **down** to
save tokens.

| Role | Spawned as | Model | Effort | Rationale |
|------|-----------|-------|--------|-----------|
| Orchestrator (lead) | main session | Opus | session default | coordination, synthesis, user gate |
| `team-planner` | subagent | Opus | xhigh | one pass, highest leverage |
| `team-prompt-smith` | subagent | Sonnet | medium | structured prompt writing |
| `team-executor` | **teammate** | Sonnet (Opus for hard modules) | medium | token-heavy fan-out |
| `team-reviewer` | subagent | Opus | xhigh | adversarial bug-hunting |
| `team-merger` | subagent | Sonnet | medium | mechanical merge/verify |
| researcher | subagent | (use built-in `Explore`) | — | broad reads, no custom file |

Override per spawn when a module is unusually hard: "spawn this executor on Opus
at high effort".

**Effort knobs:** per-role `effort:` frontmatter (above); session-wide via
`/effort`, `--effort`, `effortLevel` in settings, or `CLAUDE_CODE_EFFORT_LEVEL`
(env wins over frontmatter). Caveat: per-**teammate** effort is undocumented —
only `tools` and `model` are confirmed to carry from a definition to a teammate,
so the executor's `effort: medium` is honored as a subagent and may be ignored
as a teammate (falls back to the session default — harmless).

## Workflows vs teams — pick one orchestration layer

The Workflow tool (deterministic multi-agent scripts) is a **lead-only**
mechanism and an **alternative** to agent teams — not something teammates use.
Teammates and subagents are workers; they cannot invoke Workflow (a teammate
running a workflow that spawns agents would violate the no-nested-teams design).
For a given task choose **either** a Workflow (scripted, deterministic fan-out
you control) **or** an agent team (teammates that coordinate and that you can
message). Never design a role that depends on a teammate launching a workflow.

## Worktrees + merge

Give each executor its own git worktree so parallel edits never collide
(`isolation: worktree` when spawning, or one worktree per teammate). Executors
own a disjoint file set. The `team-merger` subagent merges each reviewed
worktree into the base branch in turn, resolves conflicts, runs the test suite,
and reports "<unit> landed" back to the lead. Unchanged worktrees are discarded.

## Teardown (step 6 — order matters)

When a teammate's work is landed (and eyeballed, if the project needs it), tear
it down **handshake first, pane-close second**. A teammate leaves the team roster
ONLY when the shutdown handshake completes — closing its iTerm pane does NOT
deregister it and can orphan its process.

Per teammate, in order:
1. `SendMessage` a `{type:"shutdown_request", reason:"…"}`.
2. **Wait for the `shutdown_response{approve:true}`.** That is what cleanly
   terminates the process AND removes it from the roster. Don't proceed on a bare
   "sent" ack — confirm the response.
3. ONLY THEN, optionally close the now-empty pane for tidiness:
   `it2 session close -s <UUID> -f`. Get the UUID from `it2 session list`
   (widen with `COLUMNS=400` — the table truncates IDs). **Never** close the
   lead's own pane or any session you didn't spawn (e.g. the user's other
   `claude`/`claude -c` windows). Match panes by name/UUID, not position.
4. After all teammates are down, prune the merged worktrees + delete the merged
   branches (`git worktree remove --force …`, `git branch -D …`).

Pitfall (observed): if the channel is flaky and a teammate never answers the
handshake, closing its pane anyway leaves a **stale roster entry** (it lingers
in the team list until the lead session ends) and can **orphan** the agent
process on the detached tty — check with `ps` and `kill` the orphan if so. Closing
panes is cosmetic; the handshake is the real teardown. Prefer fixing the channel /
re-sending the request over force-closing.

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
