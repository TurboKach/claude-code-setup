---
name: feature-workflow
description: The user's six-stage feature pipeline (discuss → plan → autoplan review → delegated execute → /codex review → ship), the parallel multi-agent mechanism picker, and the token-discipline rules for long-running agents. Invoke BEFORE starting any non-trivial feature — multiple steps, or work that benefits from a formal review cycle — and before any parallel/multi-agent fan-out. One-shot edits and small fixes outside an active pipeline skip it.
---

# Feature workflow

For non-trivial work — anything with multiple steps or that benefits from a formal review cycle. One-shot edits and small fixes outside an active pipeline skip this entirely.

One **master session** owns the feature end-to-end. It stays thin by running every token-heavy stage **out of main context** — in a subagent or an agent-team agent. The master coordinates and ingests summaries; it does not implement substantial work or hand-author specs. Plan files live in the repo at `docs/prompts/<feature>-plan.md`.

Six stages, each delegated out of main context by the master session:

1. **Discuss approach** → `/office-hours`. Explore the problem space, surface constraints, decide what's worth building. No code.
2. **Scope + rough plan** → delegate codebase discovery and a rough draft to a Plan/team-planner subagent; it saves `docs/prompts/<feature>-plan.md` and returns the path. Rough is fine; the next step polishes. Scoping/planning counts as research: "scope"/"plan"/"design" requests go to this subagent — the main loop never hand-authors the spec inline.
3. **Review + refine** → `/autoplan`. Runs CEO + Design + Eng + DX review skills sequentially, auto-decides mechanical questions, surfaces only taste decisions at a final approval gate. "Updates the plan in place" does NOT exempt the master from the no-hand-authoring rule: each phase's plan-integration edits are applied by a subagent fed that phase's findings; the master runs only the gates. The master never Reads the review sub-skill files — pass the skill path in the subagent prompt instead.
4. **Execute** → delegate each step to a subagent — parallel via agent-teams where steps are independent, sequential otherwise; commit per step.
5. **Independent review per step** → `/codex review`. Triage real / regression / test-gap / theoretical. Re-challenge only after substantive fixes. Drive the fix→re-review cycle with a bounded `/goal`: `/goal /codex review reports zero real-or-regression findings on every step's diff (the verdict pasted in full each round); or stop after 3 rounds, reporting anything unresolved`.
6. **Ship** → `/ship` (PR) → `/land-and-deploy` (merge + deploy + post-deploy verify).

Rules:
- The always-on hard gates in global CLAUDE.md apply throughout: push approval, the `/codex` merge gate, verified-claims, AFK-is-not-approval.
- **The master delegates implementation.** Substantial implementation — anything beyond a handful of tool calls — goes to a subagent; the master coordinates and stays lean. Trivial mechanical fixes (a one-line edit, a typo, a config value) may be done inline rather than spawning an agent for them — they still go through the normal commit and stage-5 review gates. Never redo or re-derive a subagent's work once its report is back.
- **Interactive gates never go to subagents.** Subagents are headless — run headless, `/autoplan` silently auto-picks and the user never sees the questions. Interactive skills run in the master session; only headless work is delegated.
- **Plan-approval is the trigger, not a suggestion.** The moment build approval lands, transition unprompted into the delegated tail: print the ready-to-paste `/goal` command (below) and fan out per-step subagents once it's fired. Never write an ExitPlanMode plan whose steps have the master implementing units itself — each execution step must name who it's delegated to.
- **Drive the post-approval tail (stages 4–6) with `/goal`.** `/goal` is user-typed — at the plan-approval gate the master prints the exact ready-to-paste `/goal` command (plan path, base branch, review gates, turn bound) and asks the user to fire it. Bound every goal (`or stop after N turns`) and pair with auto mode. **Never wrap stages 1–3 in a goal** — plan approval is the one interactive, taste-based gate. The evaluator judges only the transcript and runs no tools, so each role must surface machine-checkable proof (test exit codes + output, `git status`, structured per-unit verdicts), not just "done". Example: `/goal all units in docs/prompts/<feature>-plan.md are merged to <base>; the reviewer approved each diff; the project's test suite exits 0 with its output shown; git status is clean and no feature worktrees/branches remain; or stop after 25 turns`.
- If the master nevertheless approaches the context ceiling (~500k tokens; 600k absolute max), do a **deliberate, user-assisted handoff** to a fresh master session — don't silently push past it. `/context-save` + `/context-restore` are the bridge.
- **Master budget: a normal feature arc finishes under ~400k with no compression machinery.** Crossing ~400k mid-goal is a *defect signal*, not a reason to compress or hand off: stop, post the cost checkpoint, and name what's flooding the context so the flow gets fixed. During unattended `/goal` runs, post a one-line cost checkpoint at every unit boundary (elapsed time, review rounds, approx context size), and END the session the moment the goal completes — never leave a finished session idling (each cache expiry re-pays the full context at premium pricing).
- Make handoff artifacts cold-start-ready *without being asked*: one standalone root README a fresh session needs no other file for, and attach plans to their task/ticket so a future session finds them by reference.
- Plan reviews used individually (`/plan-eng-review` etc.) run via sub-agents — review token burn doesn't belong in main context.
- If work is interrupted mid-step, commit `WIP:` so a resume is clean.

# Parallel multi-agent

For genuinely **parallel, independent** work only; sequential pipelines belong to the feature workflow above. Pick the mechanism by need:

- **Background subagents (DEFAULT):** independent units, contracts known up front. Add `isolation: worktree` **only** when they write files in parallel and merge later; read-only fan-out needs no worktree.
- **Workflows:** large (10s+), deterministic/repeatable/resumable fan-outs with cross-checking.
- **Named teammates (experimental, almost never needed):** only to dialogue *live* with a delegated agent running in parallel, off the master tab, AND a shared tree is acceptable — teammates are NOT worktree-isolated. Needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` + `teammateMode: auto` + iTerm2.
- **Keep `teammateMode: "in-process"` (the built-in default).** Pane modes (`auto`/`iterm2`/`tmux`) spawn full named-teammate sessions that do NOT self-close; `"off"` is not a valid value. The delegate→build→review→fix workflow never needs live dialogue. Full pane/teardown mechanics live in the `agent-teams` skill.
- **Kill delegated agents the moment their unit closes.** Once an agent's output is ingested (commit merged, verdict triaged, report received), stop it in the same turn — agents are per-unit disposables, never kept warm. Before declaring a multi-agent goal complete, enumerate live agents and confirm zero remain; the user must never have to kill leftovers by hand.
- **Serial pipelines never run as named teammates.** Fire-and-return background subagents produce one summary each; a teammate that is somehow unavoidable gets stopped the moment its unit closes.
- **When to offer (lead only):** if a task has independent parallel parts AND the user hasn't specified the approach AND the project's CLAUDE.md hasn't set a preference → ask whether to fan out before starting. If you are a worker, never re-ask — just do your assigned task.
- **How:** invoke the `agent-teams` skill for the full playbook (mechanism choice, roles, models, worktree/merge flow, the plan-only approval gate). Don't inline the playbook here.

# Token discipline

Cost ≈ turn-count × context size: every agent turn re-pays its entire context as cache-read, so burn grows quadratically in a long-lived agent. Agent *lifetime* is the lever — not result size or output verbosity.

- **Retirement is mechanical, not prose.** Every executor spawn prompt carries the budget inline: "if you exceed ~200k context or ~250 turns — commit WIP, write a handoff file to the scratchpad, and stop." The orchestrator kills+respawns at the threshold; a ceiling that lives only in a memory file is invisible to the subagent it governs.
- **Fresh agent per review round.** One review round = one fresh wrapper agent — a round needs only the diff range and prompt, never prior rounds' accumulated context. Post-review fixes go to a fresh fixer agent (plan section + unit diff + verdict), never back to the original executor at peak context.
- **Verdict size contract.** Reviewer/codex agents return a structured verdict ≤2,000 chars: counts, one-line findings with file:line, real/regression/test-gap/theoretical tags. Full transcripts stay on disk; the master NEVER Reads challenge-output files.
- **Measuring burn from transcripts: dedupe by requestId/message.id first.** Claude Code writes one JSONL line per content block, each repeating the full request's usage — naive per-line sums overcount 2–3.5×.
