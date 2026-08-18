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
edits, do NOT fan out — run it through the `feature-workflow` skill, whose
delegated execute spawns one `step-executor` per step on the session's own
branch. The value here is the parallel **execution** phase only.

## 2. Pick the mechanism (this is the important decision)

| Mechanism | Use when | Coordination | Cost / overhead |
|-----------|----------|--------------|-----------------|
| **Background subagents** *(DEFAULT)* | independent units; contracts known up front | none — contract pre-specified in each prompt | low; in-process, no setup |
| **Workflows** | large fan-out (10s+), deterministic/repeatable orchestration, cross-checking/voting, resumable runs | script variables | medium; you write/run a script |
| **Named teammates** *(experimental, almost never needed)* | you must dialogue *live* with a delegated agent running in parallel, off the master tab, AND a shared tree is acceptable | live `SendMessage` cross-talk | high; iTerm2 panes, separate processes, manual teardown |

Default to **background subagents** (`Agent` tool, no `name`). `team-executor`
sets `background: true` in its frontmatter — the documented way to make a
subagent always run in the background; for ad-hoc spawns say "in the background"
(`run_in_background: true` on the Agent call also works on current builds). They
run **in-process** under the lead (no separate OS process, no iTerm2 pane), need
**no shutdown handshake**, and deliver a clean completion notification.
Pre-specify any cross-unit contract in each spawn prompt so they never need to
talk to each other.

Reach for **Workflows** when the fan-out is large or you want deterministic,
repeatable, resumable orchestration with built-in cross-checking. (In this kit
only the lead runs Workflows — the worker roles' `tools` lists deliberately omit
the Workflow and Agent tools, so they can't fan out on their own. That's a kit
choice, not a platform rule: since v2.1.172 a subagent whose `tools` includes
`Agent` can spawn nested subagents, up to 5 levels deep.)

Reach for **named teammates almost never.** The only case they earn their keep:
you want to dialogue *live* with a **delegated** agent running **in parallel**,
off the master tab — and you accept that **teammates are not isolated in
worktrees** (Claude Code does not honor `isolation: worktree` for teammates; they
share the lead's checkout, so you must partition files by hand). Note what does
NOT qualify: a planning gate. `ExitPlanMode` and `AskUserQuestion` run in the lead,
and any input a delegated subagent needs is bubbled up to the lead — so the
master already funnels approvals to you. Agent-to-agent contract negotiation
doesn't qualify either: pre-specify the contract in each spawn prompt instead.
This is the heaviest path; see §"Named-teammate path".

> Documented: teammates are **not** worktree-isolated. `isolation: worktree` is
> a **subagent** feature; a definition spawned as a *teammate* keeps only its
> `tools` and `model`, and the isolation is silently dropped ([docs](https://code.claude.com/docs/en/agents):
> "Agent teams don't isolate teammates in worktrees, so partition the work so
> each teammate owns a different set of files"). Spawning the executors as
> named teammates once put all four in the same checkout committing to `main`,
> clobbering each other. Background subagents are the safe default precisely
> because they CAN get real worktrees when they need them.

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
   → the LEAD calls EnterPlanMode, then spawns team-planner (opus), which
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
2. PROMPTS   (subagent: team-prompt-smith, sonnet)
   → turns the approved plan into one self-contained spawn prompt per unit
3. EXECUTE   (background subagents: team-executor)   ← parallel
   → lead marks each unit's task in_progress as it spawns its executor and
     completed when the unit's report is ingested (never with red tests);
   → lead spawns one background subagent per independent unit; each gets a
     worktree from team-executor's own `isolation: worktree` frontmatter, not
     from the spawn call; contracts are pre-specified in each prompt
4. REVIEW    (subagent: team-reviewer, opus — read-only, NO worktree)
   → adversarially verifies each unit's diff before it lands
5. MERGE     (subagent: team-merger, sonnet)
   → merges each approved worktree into the base branch; after each successful
     merge removes that worktree + deletes its branch; reports completion
```

Every step delegates to a subagent except the lead's own plan-mode transcription
and gates in step 1; step 3 is the only fan-out (one background subagent per unit).
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

(For the rare named-teammate path, step 3's agents are teammates instead and a
TEARDOWN step is required — see §"Named-teammate path".)

## Approval gate: PLAN ONLY

The lead must get the **user's** approval on the plan (step 1) before any
fan-out. The gate is Claude's native `ExitPlanMode` in the lead — never a
subagent, which has no channel to the user. Resolve the open taste-decisions with
one AskUserQuestion first, then present the plan and wait.
After the plan is approved, executors run, review runs, and the merger lands work
and reports completion.
6. CODEX     (lead, or a fresh general-purpose runner)
   → ONE `Skill(codex, "challenge <feature-base>..<base-HEAD>")` on the merged
     feature diff — full output to a file, triaged verdict shown; P1/P2 → fresh
     Sonnet fixer on the base branch → re-challenge, round N of 3 (feature-workflow
     stage 5 rules: P1 open at round 3 → ask; test-gap/theoretical → one
     fix-now / defer-to-tech-debt question). No further user gates before that.

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
honored when the role runs as a subagent. Effort deviates from the model default:
judgment roles go **up**, high-volume roles go **down** to save tokens.

| Role | Spawned as | Model | Effort | Rationale |
|------|-----------|-------|--------|-----------|
| Orchestrator (lead) | main session | Opus | session default | coordination, synthesis, user gate |
| `team-planner` | subagent | Opus | high | one pass, highest leverage (Opus 5: prior-model effort defaults don't transfer; `high` is the sweet spot); returns text, lead transcribes |
| `team-plan-reviewer` | subagent | Opus | high | validates the plan against the code before the gate; read-only |
| `team-prompt-smith` | subagent | Sonnet | medium | structured prompt writing |
| `team-executor` | **background subagent** | Sonnet (Opus only when the plan justifies it) | xhigh | token-heavy fan-out; Sonnet 5 guide: xhigh for coding |
| `team-reviewer` | subagent | Opus | high | adversarial bug-hunting (Opus 5 review stays accurate at lower effort) |
| `team-merger` | subagent | Sonnet | medium | mechanical merge/verify |
| `explorer` | subagent | Sonnet | medium | codebase search, read-only (built-in `Explore` would inherit the lead's model + effort) |

Pin `model:` on every spawn (unpinned = inherits the lead's Fable tier; `fable`
never in a subagent; search → `explorer`, not built-in `Explore`, which inherits the lead's model and effort). Override per spawn only when the plan marks a
unit Opus with a reason. As background subagents these roles honor their `effort:`
frontmatter; the named-teammate path may ignore per-teammate effort and fall back
to the session default — harmless.

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
`ExitPlanMode` runs in the lead, and subagent input bubbles up to the lead, so
approvals already reach you in the master tab. It is the heaviest path:
separate processes, iTerm2 panes, and manual teardown. Requirements: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, `teammateMode:
auto` (or `iterm2` to force iTerm2 native panes; the default is `in-process`),
iTerm2 with the Python API enabled, and the `it2` CLI (see
`docs/agent-teams-setup.md`).

Hard constraints (documented, except where marked observed):
- **One team per session; the lead is fixed.** Only the lead spawns — teammates
  can't spawn teammates (no nested teams).
- **Teammates are NOT isolated in worktrees** — `isolation: worktree` is dropped
  for teammates. Partition files by hand so no two teammates edit the same file.
- **A teammate needs `SendMessage` in its `tools` allowlist to report back** —
  a teammate's plain final text is never delivered to the lead. The `team-*`
  definitions omit `SendMessage` because they're written for the subagent path;
  add it to the definition before spawning one as a teammate, or the report is
  lost.
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
process. (The docs describe shutdown only as "lead sends a shutdown request,
teammate approves or rejects"; the JSON shapes below are the observed wire
format.)

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

This is the parallel-execution variant of the `feature-workflow` skill's pipeline; its stage-5 codex rules (per-feature range, P1/P2, rounds, tech-debt deferral) apply verbatim.
Planning (`/office-hours`, native plan mode) and shipping (`/ship`,
`/land-and-deploy`) are unchanged; fan-out only replaces the execute phase's
sequential per-step subagents with parallel agents when the steps are
independent.
