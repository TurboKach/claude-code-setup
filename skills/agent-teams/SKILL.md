---
name: agent-teams
description: Orchestration playbook for parallel multi-agent work in Claude Code. Use when fanning out genuinely parallel, independent work — N independent modules, multi-lens review, competing-hypothesis debugging, backend+frontend that must agree on a contract. Defaults to background subagents (with worktree isolation only when they write files in parallel and merge later); covers when to reach for Workflows instead, and the rarely-needed named-teammate (split-pane) escape hatch for live dialogue with a delegated agent. Covers the lead's pipeline (plan → prompts → parallel execute → review → merge), per-role models, worktree/merge flow, and the plan-approval gate.
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
edits, do NOT fan out — run it through the feature workflow in CLAUDE.md (the
master session delegating each step to a subagent). The value here is the
parallel **execution** phase only.

## 2. Pick the mechanism (this is the important decision)

| Mechanism | Use when | Coordination | Cost / overhead |
|-----------|----------|--------------|-----------------|
| **Background subagents** *(DEFAULT)* | independent units; contracts known up front | none — contract pre-specified in each prompt | low; in-process, no setup |
| **Workflows** | large fan-out (10s+), deterministic/repeatable orchestration, cross-checking/voting, resumable runs | script variables | medium; you write/run a script |
| **Named teammates** *(experimental, almost never needed)* | you must dialogue *live* with a delegated agent running in parallel, off the master tab, AND a shared tree is acceptable | live `SendMessage` cross-talk | high; iTerm2 panes, separate processes, manual teardown |

Default to **background subagents** (`Agent` tool, `run_in_background: true`, no
`name`). They run **in-process** under the lead (no separate OS process, no
iTerm2 pane), need **no shutdown handshake**, and deliver a clean completion
notification. Pre-specify any cross-unit contract in each spawn prompt so they
never need to talk to each other.

Reach for **Workflows** when the fan-out is large or you want deterministic,
repeatable, resumable orchestration with built-in cross-checking. (Workflows are
a lead-only mechanism; workers can't invoke them.)

Reach for **named teammates almost never.** The only case they earn their keep:
you want to dialogue *live* with a **delegated** agent running **in parallel**,
off the master tab — and you accept that **teammates are not isolated in
worktrees** (Claude Code does not honor `isolation: worktree` for teammates; they
share the lead's checkout, so you must partition files by hand). Note what does
NOT qualify: a planning gate. `/autoplan` runs in the lead (interactive there),
and any input a delegated subagent needs is bubbled up to the lead — so the
master already funnels approvals to you. Agent-to-agent contract negotiation
doesn't qualify either: pre-specify the contract in each spawn prompt instead.
This is the heaviest path; see §"Named-teammate path".

> Critical fact (verified against the docs + observed 2026-06): `isolation:
> worktree` is a **subagent** feature. A definition spawned as a *teammate* keeps
> only its `tools` and `model` — worktree isolation is silently dropped. Spawning
> the executors as named teammates once put all four in the same checkout
> committing to `main`, clobbering each other. Background subagents are the safe
> default precisely because they CAN get real worktrees when they need them.

## 3. Worktree isolation: only for parallel writes that merge

Worktree isolation has a real cost (≈200-500ms setup + disk per agent), so add it
only when it earns its keep:

- **Parallel agents that WRITE files and merge later** (the EXECUTE step) → spawn
  with `isolation: worktree`. Each gets its own checkout so concurrent edits never
  collide; the merger lands them afterward.
- **Read-only parallel fan-out** (review, research, multi-lens analysis) → **no
  worktree**. Nothing is written, so isolation is pure overhead.
- **A single writer, or writers touching strictly disjoint files you're certain
  won't be merged through git** → no worktree needed.

**Clean up after merge.** Once a unit is landed, its worktree and branch are
dead weight — the merger removes the worktree (`git worktree remove`) and deletes
the merged branch (`git branch -d`) immediately after each successful merge.
A subagent's worktree is also auto-removed if it made no changes. The net result:
nothing lingers on disk once work is merged, and there is no pane or process to
tear down.

## The pipeline

```
1. PLAN      (subagent drafts → LEAD runs /autoplan, interactive)
   → team-planner subagent (opus) writes the ROUGH plan to
     docs/prompts/<feature>-plan.md and returns it — it does NOT run /autoplan
   → the LEAD runs /autoplan **itself** (interactive): the user answers its
     option-picks in the master tab; /autoplan spawns its own review subagents,
     so the heavy reads stay off the lead. Then surface the refined plan and
     wait for the user's approval.   ← only gate
2. PROMPTS   (subagent: team-prompt-smith, sonnet)
   → turns the approved plan into one self-contained spawn prompt per unit
3. EXECUTE   (background subagents: team-executor, isolation: worktree)   ← parallel
   → lead spawns one background subagent per independent unit; these WRITE
     in parallel and merge later, so each gets a worktree; contracts are
     pre-specified in each prompt
4. REVIEW    (subagent: team-reviewer, opus — read-only, NO worktree)
   → adversarially verifies each unit's diff before it lands
5. MERGE     (subagent: team-merger, sonnet)
   → merges each approved worktree into the base branch; after each successful
     merge removes that worktree + deletes its branch; reports completion
```

Every step delegates to a subagent except the lead's own `/autoplan` pass in
step 1; step 3 is the only fan-out (one background subagent per unit). Keep the
**lead thin**: it coordinates, runs `/autoplan`, and ingests summaries — it does
not read large diffs or implement. If the lead starts implementing, stop and
delegate.

**Subagents are headless — they never prompt the user.** A subagent runs to
completion and hands its result back; it has no channel to ask you anything
mid-run. So never delegate an *interactive* gate to one — `/autoplan` surfaces
option-picks, but run in a spawned/headless session it detects that and
**auto-picks the recommended option silently**, so the user never sees the
questions. Interactive skills run in the **lead** (the session you're attached
to); only headless work goes to subagents. (This is why step 1 splits: the
subagent drafts headlessly, the lead runs `/autoplan` interactively.)

(For the rare named-teammate path, step 3's agents are teammates instead and a
TEARDOWN step is required — see §"Named-teammate path".)

## Approval gate: PLAN ONLY

The lead must get the **user's** approval on the plan (step 1) before any
fan-out. The lead runs `/autoplan` **itself** (interactive) — never a subagent,
which would run headless and silently auto-pick instead of surfacing the
option-picks. Surface the refined plan, name the open taste-decisions, wait.
After the plan is approved, executors run, review runs, and the merger lands work
and reports completion — **no further user gates**.

## Models + effort per role

Per-role `model:` and `effort:` come from the agent definition files and are
honored when the role runs as a subagent. Effort deviates from the model default:
judgment roles go **up**, high-volume roles go **down** to save tokens.

| Role | Spawned as | Model | Effort | Rationale |
|------|-----------|-------|--------|-----------|
| Orchestrator (lead) | main session | Opus | session default | coordination, synthesis, user gate |
| `team-planner` | subagent | Opus | xhigh | one pass, highest leverage |
| `team-prompt-smith` | subagent | Sonnet | medium | structured prompt writing |
| `team-executor` | **background subagent** | Sonnet (Opus for hard units) | medium | token-heavy fan-out |
| `team-reviewer` | subagent | Opus | xhigh | adversarial bug-hunting |
| `team-merger` | subagent | Sonnet | medium | mechanical merge/verify |
| researcher | subagent | (use built-in `Explore`) | — | broad reads, no custom file |

Override per spawn when a unit is unusually hard: "spawn this executor on Opus at
high effort". As background subagents these roles honor their `effort:`
frontmatter; the named-teammate path may ignore per-teammate effort and fall back
to the session default — harmless.

## Spawn recipes

Plan (subagent drafts, lead refines), then gate:
> Use the team-planner agent to write a ROUGH implementation plan for <feature>
> to `docs/prompts/<feature>-plan.md` and return it — it must NOT run /autoplan.
> Then I (the lead) run /autoplan myself, interactively, so the user answers its
> option-picks; I'll get the user's approval before any execution.

Fan out execution (background subagents that write + merge → worktree), after approval:
> Spawn one team-executor as a background subagent per unit in the approved plan,
> each with `isolation: worktree` and `run_in_background: true` and **no name**.
> Give each the prompt-smith's self-contained spawn prompt (the cross-unit
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

## Named-teammate path (almost never needed — live dialogue only)

Use this ONLY when you must dialogue live with a delegated agent running in
parallel and a shared checkout is acceptable. A planning gate is NOT such a case:
`/autoplan` runs interactively in the lead, and subagent input bubbles up to the
lead, so approvals already reach you in the master tab. It is the heaviest path:
separate processes, iTerm2 panes, and manual teardown. Requirements: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, `teammateMode:
auto`, iTerm2 with the Python API enabled, and the `it2` CLI (see
`docs/agent-teams-setup.md`).

Hard constraints (verified against the docs):
- **One team per session; the lead is fixed.** Only the lead spawns — teammates
  can't spawn teammates (no nested teams).
- **Teammates are NOT isolated in worktrees** — `isolation: worktree` is dropped
  for teammates. Partition files by hand so no two teammates edit the same file.
- **Layout is auto** — each teammate gets its own iTerm2 pane. Name teammates
  (`backend`, `frontend`) so they're identifiable by name, not position.
- CLAUDE.md + skills load for every teammate, but a definition's
  `skills`/`mcpServers` frontmatter is ignored for a teammate; `tools` and
  `model` carry over.
- `/resume` and `/rewind` don't restore in-process teammates.

Spawn (only if cross-talk is genuinely required):
> Spawn one team-executor teammate per unit, named for its unit (backend,
> frontend, …). Give each the prompt-smith's spawn prompt. Have backend and
> frontend message each other to agree the API contract. Wait for all to finish.

**Immediately after spawning, record the roster map** so teardown is
deterministic — `ps -axo pid,tty,command | grep -- '--agent-name'` and
`COLUMNS=400 it2 session list` → save `name → {agent-id, PID, iTerm UUID, TTY,
worktree}`. Match every later teardown action by UUID/PID, never by pane position.

### Teardown (teammates only — order matters)

When a teammate's work is landed and eyeballed, tear it down **handshake first,
pane-close second**. A teammate leaves the roster ONLY when the shutdown
handshake completes — closing its pane does NOT deregister it and can orphan its
process.

Per teammate, in order:
1. `SendMessage` a `{type:"shutdown_request", reason:"…"}`.
2. **Wait for `shutdown_response{approve:true}`** — that is what cleanly
   terminates the process AND removes it from the roster. Don't proceed on a bare
   "sent" ack.
3. ONLY THEN close the empty pane: `it2 session close -s <UUID> -f` (UUID from
   the roster map). **Never** close the lead's pane or a session you didn't spawn.
4. After all teammates are down, prune merged worktrees + delete merged branches.

The handshake can fail two ways:
1. **Context-exhausted zombie.** A teammate at its context limit (pane shows
   `Context limit reached · /compact or /clear`) CANNOT process any message —
   including `shutdown_request`. It emits stale `idle` pings but never
   `shutdown_response`, so the handshake can never complete. Bound your wait:
   after ~one cycle with no ACK, treat it as unreachable.
2. **Unreachable teammate whose work is already merged → kill the tree.** Verify
   liveness with a TESTED ps pattern matching the real arg (`ps -axo pid,command
   | grep -- '--agent-name <name>'`, cross-checked by PID — note the real string
   is `--agent-id X@team … --agent-name X`, so an untested grep can falsely read
   "all dead"). Kill the agent PID **and its MCP children** (uv/npm/node, via `ps
   -axo pid,ppid`), SIGTERM then SIGKILL, confirm by PID, then close the pane by
   recorded UUID.

Closing a pane is cosmetic and never deregisters a live agent; killing the
process is the real teardown when the handshake is impossible. This entire class
of problem — orphans, zombies, pane-mapping — is why background subagents are the
default: no pane, no separate process, no handshake, nothing to orphan.

## Relationship to the feature workflow

This is the parallel-execution variant of the feature workflow in CLAUDE.md.
Planning (`/office-hours`, `/autoplan`) and shipping (`/ship`,
`/land-and-deploy`) are unchanged; fan-out only replaces the execute phase's
sequential per-step subagents with parallel agents when the steps are
independent.
