## Principles

### 1. Think Before Coding
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.
- Ask about *ambiguity*, not for *permission*. Obvious fixes don't need clarifying questions — just do them.

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
- Never mark a task complete without proving it works. Run tests, check logs, demonstrate correctness.
- Find root causes — no temporary fixes or band-aids.
- Run existing tests after changes; fix anything you break. Verify type checking and linting pass if configured. For API changes, verify request/response contracts.

## Claude Code Operations

### Plan Before Building
- Enter plan mode for any non-trivial task (3+ steps or architectural decisions).
- Write a clear spec before touching code: inputs, outputs, constraints, edge cases.
- If something goes sideways, STOP and re-plan immediately — don't keep pushing.
- Use Claude Code's task tracking (TaskCreate/TaskUpdate) for multi-step work.

### Subagent Strategy
- Use subagents to keep main context window clean.
- Offload research, exploration, and parallel analysis to subagents.
- One focused task per subagent.
- Summarize subagent findings back into main context concisely.
- Scoping/planning counts as research. When asked to "scope", "plan", or
  "design" a non-trivial unit, delegate BOTH the codebase discovery and the
  plan drafting to a Plan/team-planner subagent; return only the conclusion +
  the saved `docs/prompts/<feature>-plan.md` path. The main loop keeps the
  brain-dump rough and runs /autoplan to refine — it does not hand-author the
  spec inline.
- Subagents are headless — they never prompt you; they run to completion and
  hand results back. Never delegate an *interactive* gate (e.g. `/autoplan`,
  which surfaces option-picks) to a subagent — run headless it silently
  auto-picks the recommended option and you never see the questions. Interactive
  skills run in the master session; only headless work goes to subagents.

### Autonomous Bug Fixing
- When given a bug report: investigate and fix it. Don't ask for hand-holding.
- Read logs, errors, failing tests — then resolve them.
- Fix failing CI/tests without being told how.
- Only ask the user when you genuinely lack context, not for permission.

### Self-Improvement Loop
- After ANY correction from the user: update auto-memory with the lesson.
- Write concrete, actionable rules that prevent the same mistake.

### Communication
- For architectural decisions: present 2–3 options with tradeoffs, then recommend one.
- Keep summaries concise: what changed, why, and what to verify.
- When blocked or uncertain, say so clearly rather than guessing.

## Feature workflow

For non-trivial work — anything with multiple steps or that benefits from a formal review cycle. One-shot edits and small fixes skip this entirely.

One **master session** owns the feature end-to-end. It stays thin by running every token-heavy stage **out of main context** — in a subagent or an agent-team agent — so in practice it never fills up. The master coordinates and ingests summaries; it does not implement or hand-author specs. Plan files live in the repo at `docs/prompts/<feature>-plan.md` so they survive across machines and sessions.

Six stages, each delegated out of main context by the master session:

1. **Discuss approach** → `/office-hours`. Explore the problem space, surface constraints, decide what's worth building. No code.
2. **Scope + rough plan** → delegate codebase discovery and a rough draft to a Plan/team-planner subagent; it saves `docs/prompts/<feature>-plan.md` and returns the path. Rough is fine; the next step polishes. The master does not hand-author the spec inline.
3. **Review + refine** → `/autoplan`. Runs CEO + Design + Eng + DX review skills sequentially, auto-decides mechanical questions via 6 principles, surfaces only taste decisions at a final approval gate. Updates the plan in place.
4. **Execute** → delegate each step to a subagent — parallel via agent-teams where steps are independent, sequential otherwise; commit per step. Token-heavy implementation stays out of main context.
5. **Independent review per step** → `/codex review`. Triage real / regression / test-gap / theoretical. Re-challenge only after substantive fixes.
6. **Ship** → `/ship` (PR) → `/land-and-deploy` (merge + deploy + post-deploy verify).

Rules:
- Keeping the master thin via delegation is what lets one session run e2e. If it nevertheless approaches the context ceiling (~500k tokens), do a **deliberate, user-assisted handoff** to a fresh master session — don't silently push past it. `/context-save` + `/context-restore` are the handoff bridge.
- Make handoff artifacts cold-start-ready *without being asked*: consolidate everything essential into one standalone root README so a fresh session needs no other file, and attach execution/implementation plans to their task/ticket so a future session finds them by reference — not just as local files.
- Plan reviews used individually (`/plan-eng-review` etc.) run via sub-agents — review token burn doesn't belong in main context.
- If work is interrupted mid-step, commit `WIP:` so the master (or a handoff session) can resume cleanly.

## Parallel multi-agent

For genuinely **parallel, independent** work only; sequential pipelines belong to the feature workflow above. Pick the mechanism by need:

- **Background subagents (DEFAULT):** independent units, contracts known up front. Add `isolation: worktree` **only** when they write files in parallel and merge later; read-only fan-out (review, research) needs no worktree. In-process, no setup, no teardown.
- **Workflows:** large (10s+), deterministic/repeatable/resumable fan-outs with cross-checking.
- **Named teammates (experimental, almost never needed):** only to dialogue *live* with a delegated agent running in parallel, off the master tab, AND a shared tree is acceptable — teammates are NOT worktree-isolated. A planning gate does not qualify (`/autoplan` runs in the master; subagent input bubbles up there). Needs `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` + `teammateMode: auto` + iTerm2.

- **When to offer (lead only):** if a task has independent parallel parts (backend+frontend, N independent modules, competing-hypothesis debugging, multi-lens review) AND I haven't told you the approach AND the project's own CLAUDE.md hasn't set a preference → ask whether to fan out before starting. If you are a worker, never re-ask — just do your assigned task.
- **How:** invoke the `agent-teams` skill for the full playbook (mechanism choice, roles, models, worktree/merge flow, the plan-only approval gate). Don't inline the playbook here.

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
