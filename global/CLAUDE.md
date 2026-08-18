## Principles

### 1. Think Before Coding
- **Big decisions are discussed with me first** — architecture, scope changes, product behavior, data models, irreversible or destructive actions, or anything where different readings lead to materially different work. Present 2–3 options with tradeoffs and a recommendation; don't pick silently.
- **Research → combined summary → discussion.** When a task needs research, bring me one combined summary of all threads and discuss before any decision gate, plan, or code.
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
- **Green unit tests are not "done."** Before claiming done/verified/fixed for anything with a runtime surface, exercise the real user-facing flow end-to-end and show the evidence: drive the actual UI path (`/verify`, `/run`, `/browse`, `/qa`), render visual work against the reference, and check impact on every consuming client. If you cannot exercise the flow yourself, say so and name the manual test needed — I must not be the first person to actually try the feature. Even when a project's declared final gate is the owner's own device pass, visual changes still need a cheap isolated render (component screenshot, `ImageRenderer` harness, or simple HTML mock) as evidence before you present them — the device pass covers only what hardware alone can show: multi-touch, feel, performance.
- Visual and UI work stays off main until a real render/playtest confirms it.
- Find root causes — no temporary fixes or band-aids. Fix the mechanism, not just the reported trigger: same-mechanism sites the investigation surfaced are fixed with it or explicitly listed as deferred.

## Hard gates (always on)

- **Pushes to remote are user-approved, always.** `git push` — any remote, any branch — only after my explicit approval in the session (me firing `/ship` or `/land-and-deploy` counts).
- **`/codex` merge gate.** Never merge a pipeline step until gstack's `/codex` skill has run in **challenge** mode on that step's accumulated diff — `Skill(codex, "challenge <step-base-sha>..HEAD")`, in the master or in a fresh `general-purpose` runner that invokes that Skill — and its triaged verdict is shown. Internal reviewer subagents do NOT satisfy this gate. If `/codex` hasn't run, say "unreviewed, not merging".
- **Never say "verified" from indirect reasoning.** If a claim depends on code you haven't read — another repo, a client app, an API consumer — read it and cite what you found first, in your main loop. Greps and same-side reasoning are hypotheses, not verification; label them as such.
- **AFK is not approval.** Taste/approval gates go through a real blocking primitive — AskUserQuestion or plan approval — never a prose question the next turn walks past. No answer → end the turn and wait (push-notify if I may be away). Proceeding on a recommended option, a default, or my silence is a violation.
- **Inside a pipeline, the master session writes zero product code.** A pipeline is active the moment a plan file exists, plan mode is approved, or `feature-workflow` has loaded. From then on every product-file change — however tiny, however "faster to just do it" — goes to a subagent; the master coordinates, gates, and commits. The "small fixes skip the workflow" exemption covers standalone one-shot requests only, never work inside an active pipeline.
- **A plan's steps name who executes them.** Never write an ExitPlanMode plan or plan file whose steps have the master implementing units itself — each execution step names the subagent it's delegated to.

## Operations

- Enter plan mode for any non-trivial task (3+ steps or architectural decisions); write a clear spec before touching code. If something goes sideways, STOP and re-plan immediately.
- **Inside a pipeline, delegation is the default** — implementation, token-heavy stages, wide multi-file investigations, and independent parallel tracks all go to subagents. Outside a pipeline, weigh the overhead: a subagent re-establishes context and reports back, so don't spawn one for work you'd finish in a handful of tool calls, and never to verify or double-check your own work (formal gates — team-reviewer, `/codex` — are the deliberate exception). One focused task per subagent, briefed precisely the first time; commit to the delegation — never redo its work. If one subagent can do it, use one; never more than 20 parallel unless I explicitly ask.
- **Delegates spawn unnamed.** Passing `name:` turns a subagent into a mailbox teammate whose report reaches the master only if it remembers to SendMessage; unnamed spawns auto-deliver their final report (inline when foreground, task-notification when background). Names are only for parallel teams that need live coordination. And silence is not progress: past an agent's expected window — or when its result is an API error — read its transcript under the session's `subagents/` dir, salvage what finished, respawn a fresh agent for only the remainder. But measure the window from the agent's own spawn timestamp and last transcript write, never from how long *you* have been waiting or a goal check-in's "deferred N min" — a runner spawned 20 s ago is not stalled; killing a healthy agent costs a full re-run.
- Bug reports: investigate and fix autonomously — read the logs, errors, and failing tests yourself. Ask only when you genuinely lack context, not for permission.
- **Earn the decision gate.** Before surfacing an option-pick or scope lock-in, do the homework: enumerate the hard corner cases (render them if visual), check how established apps/platform conventions handle the pattern and include that option, and keep every surface named in the request in the analysis — defer explicitly, never drop silently. A gate I must reject to go research myself is worse than no gate. Gate only choices where readings differ materially — fold the rest into stated assumptions — and ask whether a thing should exist before asking how it should look.
- Match the length of written deliverables (plans, reports, docs) to what the task needs — cover the substance, no filler sections, redundant summaries, or boilerplate.
- **Render, don't ASCII-sketch, when it matters visually.** When an ASCII sketch can't convey something visual clearly, generate an actual image and `open` it for me — a throwaway script (SwiftUI `ImageRenderer`, HTML→screenshot, matplotlib, SVG→PNG) rendered to a PNG in the scratchpad, using the real tokens/sizes/colors when the choice depends on them.

## Feature workflow

**Trigger — mechanical, not a judgment call.** Before your first edit, load the `feature-workflow` skill if ANY of these holds: the work touches 2+ files, has 2+ steps, a plan file exists or is being written, or it's a parallel/multi-agent fan-out. In doubt, load it — loading costs one tool call, skipping it costs the pipeline. I never ask for it by name; recognizing the work is big enough is your job.

It holds the six-stage pipeline (discuss → plan in native plan mode → validate + approve → delegated execute → `/codex` challenge → ship), the parallelism mechanism picker, and the token-discipline rules. Genuine one-shot edits outside an active pipeline skip it.

## Tooling

- **Context7 MCP**: automatically look up current documentation for libraries and frameworks before implementing — don't wait to be told.
- **gstack** (installed at `~/.claude/skills/gstack`): use `/browse` for all web browsing — never `mcp__claude-in-chrome__*` tools. After implementing a feature or fix, proactively run `/review` (branch diff review, works pre-PR) then `/codex challenge` for cross-model review.
- **Plan gate cap**: before `ExitPlanMode`, surface only the materially-divergent taste items (target ≤5) in one AskUserQuestion; every surfaced item's options include the simplest choice (often "remove it entirely" / "do nothing").

## Scope

Universal workflow and quality standards only. Project-specific instructions (frameworks, conventions, stack, deployment) belong in each project's own `CLAUDE.md`.

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, clarifying questions before implementation rather than after mistakes.
