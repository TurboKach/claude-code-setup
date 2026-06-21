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

## Multi-session feature workflow

For non-trivial work — anything that would burn through a single session's context (~200–300k tokens), span multiple sittings, or benefit from a formal review cycle. One-shot edits and small fixes skip this entirely.

Six stages, each in its own fresh session. Plan files live in the repo at `docs/prompts/<feature>-plan.md` so they survive across machines and sessions.

1. **Discuss approach** → `/office-hours`. Explore the problem space, surface constraints, decide what's worth building. No code.
2. **Brain-dump rough plan** → plan mode → save as `docs/prompts/<feature>-plan.md`. Rough is fine; the next step polishes.
3. **Review + refine** → `/autoplan`. Runs CEO + Design + Eng + DX review skills sequentially, auto-decides mechanical questions via 6 principles, surfaces only taste decisions at a final approval gate. Updates the plan in place.
4. **Execute, one step per session** → each session: `/context-restore` → do the step → commit → `/context-save` before closing. Hard rule: one step per session, don't batch.
5. **Independent review per step** → `/codex review`. Triage real / regression / test-gap / theoretical. Re-challenge only after substantive fixes.
6. **Ship** → `/ship` (PR) → `/land-and-deploy` (merge + deploy + post-deploy verify).

Rules:
- `/context-save` + `/context-restore` are the cross-session bridge. Don't manually copy "what's landed" summaries between sessions unless those skills are unavailable.
- Make cross-session artifacts cold-start-ready *without being asked*: consolidate everything essential into one standalone root README so a fresh session needs no other file, and attach execution/implementation plans to their task/ticket so a future session finds them by reference — not just as local files.
- Don't use `--continue` or `--resume` for execution sessions. Cold-start each one so context stays bounded.
- Plan reviews used individually (`/plan-eng-review` etc.) run via sub-agents — review token burn doesn't belong in main context.
- If a session can't finish its step, commit `WIP:` and let the next session resume the same step. Don't advance.

## Agent Teams (parallel multi-agent)

Experimental teams are enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`; iTerm2 split panes via `teammateMode: auto`). Use them ONLY for genuinely **parallel, independent** work; sequential pipelines belong to the multi-session workflow above or to plain subagents.

- **When to offer (lead only):** if a task has independent parallel parts (backend+frontend, N independent modules, competing-hypothesis debugging, multi-lens review) AND I haven't told you the approach AND the project's own CLAUDE.md hasn't set a preference (`use teams` / `never teams`) → ask whether to use a team before starting. If you are a teammate, never re-ask — just do your assigned task.
- **How:** invoke the `agent-teams` skill for the full playbook (roles, models, worktree/merge flow, the plan-only approval gate). Don't inline the playbook here.

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
