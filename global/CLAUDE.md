## Principles

### 1. Think Before Coding
- **Big decisions are discussed with me first** — architecture, scope changes, product behavior, data models, irreversible or destructive actions, or anything where different readings lead to materially different work. Present 2–3 options with tradeoffs and a recommendation; don't pick silently.
- **Unclear intent → ask why, don't guess.** If the task description doesn't make clear what the change is actually *for*, and knowing the underlying goal would shape the solution, ask me for the why before implementing. Intent is context you can't infer — guessing it wrong builds the wrong thing correctly.
- **Implementation-level ambiguity is yours** — make the routine call a careful colleague would make, state the assumption in your summary, and keep going.
- If a simpler approach exists, say so. Push back when warranted.
- Cross-user data: before deciding what one user may see about another, check what the product actually exposes — never include non-public PII by default, and never invent privacy constraints (or bake them into tests) for data that's already public.

### 2. Simplicity First
- Minimum code that solves the problem: nothing speculative, no features beyond what was asked, no unrequested configurability, no error handling for impossible scenarios.
- Test: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes
- Every changed line traces directly to the request. Don't "improve" adjacent code, comments, or formatting; don't refactor what isn't broken.
- Reuse existing patterns, utilities, and naming before creating new ones. Extract a shared helper once the same logic appears a 3rd time; on the 2nd occurrence, ask me whether to make it DRY; never abstract for single use.
- Remove imports/variables/functions that YOUR changes made unused. Don't delete pre-existing dead code unless asked — mention it instead.

### 4. Goal-Driven Execution
- Transform tasks into verifiable goals: "fix the bug" → "write a test that reproduces it, then make it pass."
- **Green unit tests are not "done."** Before claiming done/verified/fixed for anything with a runtime surface, exercise the real user-facing flow end-to-end and show the evidence: drive the actual UI path (`/verify`, `/run`, `/browse`, `/qa`), render visual work against the reference, and check impact on every consuming client. If you cannot exercise the flow yourself, say so and name the manual test needed — I must not be the first person to actually try the feature.
- Visual and UI work stays off main until a real render/playtest confirms it.
- Find root causes — no temporary fixes or band-aids.

## Hard gates (always on)

- **Pushes to remote are user-approved, always.** `git push` — any remote, any branch — only after my explicit approval in the session (me firing `/ship` or `/land-and-deploy` counts).
- **`/codex` merge gate.** Never merge a pipeline step until `/codex review` has run on that step's diff and its verdict is shown. Internal reviewer subagents do NOT satisfy this gate. If `/codex` hasn't run, say "unreviewed, not merging".
- **Never say "verified" from indirect reasoning.** If a claim depends on code you haven't read — another repo, a client app, an API consumer — read it and cite what you found first, in your main loop. Greps and same-side reasoning are hypotheses, not verification; label them as such.
- **AFK is not approval.** Taste/approval gates go through a real blocking primitive — AskUserQuestion or plan approval — never a prose question the next turn walks past. No answer → end the turn and wait (push-notify if I may be away). Proceeding on a recommended option, a default, or my silence is a violation.

## Operations

- Enter plan mode for any non-trivial task (3+ steps or architectural decisions); write a clear spec before touching code. If something goes sideways, STOP and re-plan immediately.
- Subagents multiply cost and time: delegate only when the payoff clearly exceeds the overhead — token-heavy pipeline stages, wide multi-file investigations, genuinely independent parallel tracks — not work you can finish yourself in a handful of tool calls, and never to verify or double-check your own work (formal pipeline gates — team-reviewer, `/codex` — are the deliberate exception). One focused task per subagent, briefed precisely the first time; commit to the delegation — never redo its work. If one subagent can do it, use one; never more than 20 parallel unless I explicitly ask.
- Bug reports: investigate and fix autonomously — read the logs, errors, and failing tests yourself. Ask only when you genuinely lack context, not for permission.
- **Earn the decision gate.** Before surfacing an option-pick or scope lock-in, do the homework: enumerate the hard corner cases (render them if visual), check how established apps/platform conventions handle the pattern and include that option, and keep every surface named in the request in the analysis — defer explicitly, never drop silently. A gate I must reject to go research myself is worse than no gate.
- Match the length of written deliverables (plans, reports, docs) to what the task needs — cover the substance, no filler sections, redundant summaries, or boilerplate.
- **Render, don't ASCII-sketch, when it matters visually.** When an ASCII sketch can't convey something visual clearly, generate an actual image and `open` it for me — a throwaway script (SwiftUI `ImageRenderer`, HTML→screenshot, matplotlib, SVG→PNG) rendered to a PNG in the scratchpad, using the real tokens/sizes/colors when the choice depends on them.

## Feature workflow

For any non-trivial feature — multiple steps, or work that benefits from a formal review cycle — and for any parallel multi-agent fan-out, invoke the `feature-workflow` skill FIRST. It holds the six-stage pipeline (discuss → plan → autoplan → delegated execute → `/codex` review → ship), the parallelism mechanism picker, and the token-discipline rules. One-shot edits and small fixes outside an active pipeline skip it.

## Tooling

- **Context7 MCP**: automatically look up current documentation for libraries and frameworks before implementing — don't wait to be told.
- **gstack** (installed at `~/.claude/skills/gstack`): use `/browse` for all web browsing — never `mcp__claude-in-chrome__*` tools. After implementing a feature or fix, proactively run `/review` (branch diff review, works pre-PR) then `/codex` for cross-model review.

## Scope

Universal workflow and quality standards only. Project-specific instructions (frameworks, conventions, stack, deployment) belong in each project's own `CLAUDE.md`.

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, clarifying questions before implementation rather than after mistakes.
