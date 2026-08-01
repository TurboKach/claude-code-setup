## Principles

### 1. Think Before Coding
- **Big decisions are discussed with me first** — architecture, scope changes, product behavior, data models, irreversible or destructive actions, or anything where different readings lead to materially different work. Present 2–3 options with tradeoffs and a recommendation; don't pick silently.
- **Implementation-level ambiguity is yours** — make the routine call a careful colleague would make, state the assumption in your summary, and keep going. Don't stop to ask permission for obvious fixes.
- If a simpler approach exists, say so. Push back when warranted.
- Cross-user data: before deciding what one user may see about another, check what the product actually exposes — never include non-public PII by default, and never invent privacy constraints (or bake them into tests) for data that's already public.

### 2. Simplicity First
- Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked. No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.
- Test: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes
- Every changed line should trace directly to the user's request.
- Read existing code in the area you're modifying before making changes.
- Match existing style, even if you'd do it differently.
- Check for existing utilities/helpers before creating new ones.
- Keep it DRY and follow project conventions: reuse existing patterns, utilities, and naming instead of reinventing them. Extract a shared helper/component once the same logic appears a 3rd time; on the 2nd occurrence (double), ask me whether to make it DRY; never abstract for single use.
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Remove imports/variables/functions that YOUR changes made unused. Don't delete pre-existing dead code unless asked — mention it instead.

### 4. Goal-Driven Execution
- Transform tasks into verifiable goals:
  - "Add validation" → "Write tests for invalid inputs, then make them pass"
  - "Fix the bug" → "Write a test that reproduces it, then make it pass"
  - "Refactor X" → "Ensure tests pass before and after"
- For multi-step tasks, state a brief plan:
  ```
  1. [Step] → verify: [check]
  2. [Step] → verify: [check]
  ```
- **Green unit tests are not "done."** Before claiming done/verified/fixed for anything with a runtime surface, exercise the real user-facing flow end-to-end and show the evidence: drive the actual UI path and its state transitions (`/verify`, `/run`, `/browse`, `/qa`), render visual work against the reference, and check impact on every consuming client (apps, services, other repos).
- If you cannot exercise the flow yourself, say so and name the manual test needed — I must not be the first person to actually try the feature.
- Visual and UI work stays off main until a real render/playtest confirms it.
- Find root causes — no temporary fixes or band-aids.
- Run existing tests after changes; fix anything you break. Verify type checking and linting pass if configured. For API changes, verify request/response contracts.

## Claude Code Operations

### Plan Before Building
- Enter plan mode for any non-trivial task (3+ steps or architectural decisions).
- Write a clear spec before touching code: inputs, outputs, constraints, edge cases.
- If something goes sideways, STOP and re-plan immediately — don't keep pushing.
- Use Claude Code's task tracking (TaskCreate/TaskUpdate) for multi-step work.

### Subagent Strategy
- Subagents multiply cost and time: each re-establishes context, re-explores, and reports back, and you then re-read its report. Delegate when the payoff clearly exceeds that overhead — token-heavy pipeline stages, wide multi-file investigations, genuinely independent parallel tracks — not for work you can finish yourself in a handful of tool calls.
- Do NOT use subagents for review, verification, or double-checking your own work — verification belongs in your main agent loop. (Formal pipeline review gates — team-reviewer, `/codex` — are a separate, deliberate exception.)
- One focused task per subagent; brief it precisely the first time. Commit to the delegation: never redo a subagent's work or re-derive its findings once it reports back. Summarize findings back into main context concisely.
- Parallel spawns are for independent, sizeable tracks — if one subagent can do it, use one; never more than 20 parallel agents unless I explicitly ask. Launch independent agents in a single message so they run concurrently.
- Scoping/planning counts as research: "scope"/"plan"/"design" requests go to a Plan/team-planner subagent (feature workflow stage 2) — the main loop never hand-authors the spec inline.
- Subagents are headless — they never prompt you; run to completion and hand results back. Never delegate an *interactive* gate (e.g. `/autoplan`) to a subagent — run headless it silently auto-picks and you never see the questions. Interactive skills run in the master session; only headless work goes to subagents.

### Autonomous Bug Fixing
- When given a bug report: investigate and fix it. Don't ask for hand-holding.
- Read logs, errors, failing tests — then resolve them.
- Fix failing CI/tests without being told how.
- Only ask the user when you genuinely lack context, not for permission.

### Communication
- **Earn the decision gate.** Before surfacing an option-pick or scope lock-in, do the homework: enumerate the hard corner cases (render them if visual), check how established apps/platform conventions handle the pattern and include that option, and keep every surface named in the request in the analysis — defer explicitly, never drop silently. A gate I must reject to go research myself is worse than no gate.
- Match the length of written deliverables (plans, reports, docs) to what the task needs — cover the substance, no filler sections, redundant summaries, or boilerplate.
- **Render, don't ASCII-sketch, when it matters visually.** When depicting something visual and an ASCII sketch can't convey it clearly, generate an actual image and `open` it for me — a throwaway script (SwiftUI `ImageRenderer`, AppKit, HTML→screenshot, matplotlib, SVG→PNG) rendered to a PNG in the scratchpad, using the real tokens/sizes/colors when the choice depends on them.

## Feature workflow

For non-trivial work — anything with multiple steps or that benefits from a formal review cycle. One-shot edits and small fixes outside an active pipeline skip this entirely.

One **master session** owns the feature end-to-end. It stays thin by running every token-heavy stage **out of main context** — in a subagent or an agent-team agent. The master coordinates and ingests summaries; it does not implement substantial work or hand-author specs. Plan files live in the repo at `docs/prompts/<feature>-plan.md`.

Six stages, each delegated out of main context by the master session:

1. **Discuss approach** → `/office-hours`. Explore the problem space, surface constraints, decide what's worth building. No code.
2. **Scope + rough plan** → delegate codebase discovery and a rough draft to a Plan/team-planner subagent; it saves `docs/prompts/<feature>-plan.md` and returns the path. Rough is fine; the next step polishes.
3. **Review + refine** → `/autoplan`. Runs CEO + Design + Eng + DX review skills sequentially, auto-decides mechanical questions, surfaces only taste decisions at a final approval gate. "Updates the plan in place" does NOT exempt the master from the no-hand-authoring rule: each phase's plan-integration edits are applied by a subagent fed that phase's findings; the master runs only the gates. The master never Reads the review sub-skill files — pass the skill path in the subagent prompt instead.
4. **Execute** → delegate each step to a subagent — parallel via agent-teams where steps are independent, sequential otherwise; commit per step.
5. **Independent review per step** → `/codex review`. Triage real / regression / test-gap / theoretical. Re-challenge only after substantive fixes. Drive the fix→re-review cycle with a bounded `/goal`: `/goal /codex review reports zero real-or-regression findings on every step's diff (the verdict pasted in full each round); or stop after 3 rounds, reporting anything unresolved`.
6. **Ship** → `/ship` (PR) → `/land-and-deploy` (merge + deploy + post-deploy verify).

Rules:
- **The master delegates implementation.** Substantial implementation — anything beyond a handful of tool calls — goes to a subagent; the master coordinates and stays lean. Trivial mechanical fixes (a one-line edit, a typo, a config value) may be done inline rather than spawning an agent for them — they still go through the normal commit and stage-5 review gates. Never redo or re-derive a subagent's work once its report is back.
- **Plan-approval is the trigger, not a suggestion.** The moment build approval lands, transition unprompted into the delegated tail: print the ready-to-paste `/goal` command (below) and fan out per-step subagents once it's fired. Never write an ExitPlanMode plan whose steps have the master implementing units itself — each execution step must name who it's delegated to.
- **Drive the post-approval tail (stages 4–6) with `/goal`.** `/goal` is user-typed — at the plan-approval gate the master prints the exact ready-to-paste `/goal` command (plan path, base branch, review gates, turn bound) and asks me to fire it. Bound every goal (`or stop after N turns`) and pair with auto mode. **Never wrap stages 1–3 in a goal** — plan approval is the one interactive, taste-based gate. The evaluator judges only the transcript and runs no tools, so each role must surface machine-checkable proof (test exit codes + output, `git status`, structured per-unit verdicts), not just "done". Example: `/goal all units in docs/prompts/<feature>-plan.md are merged to <base>; the reviewer approved each diff; the project's test suite exits 0 with its output shown; git status is clean and no feature worktrees/branches remain; or stop after 25 turns`.
- If the master nevertheless approaches the context ceiling (~500k tokens; 600k absolute max), do a **deliberate, user-assisted handoff** to a fresh master session — don't silently push past it. `/context-save` + `/context-restore` are the bridge.
- **Master budget: a normal feature arc finishes under ~400k with no compression machinery.** Crossing ~400k mid-goal is a *defect signal*, not a reason to compress or hand off: stop, post the cost checkpoint, and name what's flooding the context so the flow gets fixed. During unattended `/goal` runs, post a one-line cost checkpoint at every unit boundary (elapsed time, review rounds, approx context size), and END the session the moment the goal completes — never leave a finished session idling (each cache expiry re-pays the full context at premium pricing).- Make handoff artifacts cold-start-ready *without being asked*: one standalone root README a fresh session needs no other file for, and attach plans to their task/ticket so a future session finds them by reference.
- Plan reviews used individually (`/plan-eng-review` etc.) run via sub-agents — review token burn doesn't belong in main context.
- If work is interrupted mid-step, commit `WIP:` so a resume is clean.
- **Stage 5 is a hard merge gate.** Never merge a step until `/codex review` has run on that step's diff and its verdict is shown. Internal reviewer subagents do NOT satisfy this gate. If `/codex` hasn't run, say "unreviewed, not merging".
- **Pushes to remote are user-approved, always.** `git push` — any remote, any branch — only after my explicit approval in the session (me firing `/ship` or `/land-and-deploy` counts).
- **Never say "verified" from indirect reasoning.** If a claim depends on code you haven't read — another repo, a client app, an API consumer — read it and cite what you found first, in your main loop (don't spawn a subagent just to verify). Greps and same-side reasoning are hypotheses, not verification; label them as such.
- **AFK is not approval.** Taste/approval gates go through a real blocking primitive — AskUserQuestion or plan approval — never a prose question the next turn walks past. No answer → end the turn and wait (push-notify if I may be away). Proceeding on a recommended option, a default, or my silence is a pipeline violation.

## Parallel multi-agent

For genuinely **parallel, independent** work only; sequential pipelines belong to the feature workflow above. Pick the mechanism by need:

- **Background subagents (DEFAULT):** independent units, contracts known up front. Add `isolation: worktree` **only** when they write files in parallel and merge later; read-only fan-out needs no worktree.
- **Workflows:** large (10s+), deterministic/repeatable/resumable fan-outs with cross-checking.
- **Named teammates (experimental, almost never needed):** only to dialogue *live* with a delegated agent running in parallel, off the master tab, AND a shared tree is acceptable — teammates are NOT worktree-isolated. Needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` + `teammateMode: auto` + iTerm2.
- **Keep `teammateMode: "in-process"` (the built-in default).** Pane modes (`auto`/`iterm2`/`tmux`) spawn full named-teammate sessions that do NOT self-close; `"off"` is not a valid value. The delegate→build→review→fix workflow never needs live dialogue. Full pane/teardown mechanics live in the `agent-teams` skill.
- **Kill delegated agents the moment their unit closes.** Once an agent's output is ingested (commit merged, verdict triaged, report received), stop it in the same turn — agents are per-unit disposables, never kept warm. Before declaring a multi-agent goal complete, enumerate live agents and confirm zero remain; I must never have to kill leftovers by hand.- **Serial pipelines never run as named teammates.** Fire-and-return background subagents produce one summary each; a teammate that is somehow unavoidable gets stopped the moment its unit closes.- **When to offer (lead only):** if a task has independent parallel parts AND I haven't told you the approach AND the project's CLAUDE.md hasn't set a preference → ask whether to fan out before starting. If you are a worker, never re-ask — just do your assigned task.
- **How:** invoke the `agent-teams` skill for the full playbook (mechanism choice, roles, models, worktree/merge flow, the plan-only approval gate). Don't inline the playbook here.

## Token discipline

Cost ≈ turn-count × context size: every agent turn re-pays its entire context as cache-read, so burn grows quadratically in a long-lived agent. Agent *lifetime* is the lever — not result size or output verbosity.

- **Retirement is mechanical, not prose.** Every executor spawn prompt carries the budget inline: "if you exceed ~200k context or ~250 turns — commit WIP, write a handoff file to the scratchpad, and stop." The orchestrator kills+respawns at the threshold; a ceiling that lives only in a memory file is invisible to the subagent it governs.
- **Fresh agent per review round.** One review round = one fresh wrapper agent — a round needs only the diff range and prompt, never prior rounds' accumulated context. Post-review fixes go to a fresh fixer agent (plan section + unit diff + verdict), never back to the original executor at peak context.
- **Verdict size contract.** Reviewer/codex agents return a structured verdict ≤2,000 chars: counts, one-line findings with file:line, real/regression/test-gap/theoretical tags. Full transcripts stay on disk; the master NEVER Reads challenge-output files.
- **Measuring burn from transcripts: dedupe by requestId/message.id first.** Claude Code writes one JSONL line per content block, each repeating the full request's usage — naive per-line sums overcount 2–3.5×.

## Tooling

- **Context7 MCP**: automatically look up current documentation for libraries and frameworks before implementing — don't wait to be told.
- **gstack** (installed at `~/.claude/skills/gstack`):
  - Use `/browse` from gstack for all web browsing. Never use `mcp__claude-in-chrome__*` tools.
  - After implementing a feature or fix, proactively run `/review` (branch diff review, works pre-PR) then `/codex` for cross-model review.
  - Available skills: `/office-hours`, `/plan-ceo-review`, `/plan-eng-review`, `/plan-design-review`, `/plan-devex-review`, `/design-consultation`, `/design-shotgun`, `/design-html`, `/review`, `/ship`, `/land-and-deploy`, `/canary`, `/benchmark`, `/browse`, `/open-gstack-browser`, `/qa`, `/qa-only`, `/design-review`, `/devex-review`, `/setup-browser-cookies`, `/setup-deploy`, `/setup-gbrain`, `/sync-gbrain`, `/retro`, `/investigate`, `/document-release`, `/document-generate`, `/codex`, `/cso`, `/autoplan`, `/pair-agent`, `/careful`, `/freeze`, `/guard`, `/unfreeze`, `/gstack-upgrade`, `/learn`.

## Scope

This file contains **universal workflow and quality standards**.
Project-specific instructions (frameworks, conventions, stack details, deployment steps) belong in each project's own `CLAUDE.md`.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, clarifying questions come before implementation rather than after mistakes.
