# Plan: gate + backlog discipline (global rules) — 2026-08-13

Session forensics of the clipsy_ios pipeline (2026-08-12) found three recurring misses — defect
fixes scoped to the reported trigger instead of the investigated mechanism, oversized `/autoplan`
taste gates (13 items, missing "remove it" options), and visual fixes presented with no render
evidence — plus a monolithic `TODOS.md` problem now solved by an index + detail-file split that
needs durable, cross-project enforcement. All remedies were validated against the Claude 5
context-engineering guidance (keep CLAUDE.md light, procedures in path-scoped rules) and approved by
the owner. gstack skills cannot be edited directly (`/gstack-upgrade` hard-resets to `origin/main`),
so the `/autoplan` fix is an instruction-layer override in CLAUDE.md.

**Stage 3 (`/autoplan`) is skipped**: every taste decision was already made interactively by the
owner via AskUserQuestion — (a) fix the `/autoplan` gate size via a CLAUDE.md override rather than
editing the skill; (b) encode the TODOS convention as a path-scoped **user** rule, not a CLAUDE.md
bullet; (c) place the render-evidence rule in **both** repos (global clause + project section);
(d) the render clause wording and the `/autoplan` cap wording approved as written below;
(e) installed `rules/*.md` follow the skills/agents back-up-then-replace clobber policy;
(f) the new `global/rules/` surface is declared in `README.md` and the `stack-update` skill in this
same step; (g) the index-line format codifies the live clipsy form (bold title + markdown link).

**Parallelism**: the two steps touch disjoint repos and share no files, so they can run
concurrently; each still gets its own `/codex review` gate before its commit is accepted.

**Verified precondition**: user-level `~/.claude/rules/` is real in Claude Code 2.1.229 — the
loader joins the user config dir with `rules` and registers it as type `"User"` through the same
path-conditional loader used for project `.claude/rules/`. Frontmatter `paths:` therefore scopes it.

---

## Step 1 — claude-code-setup repo + live `~/.claude` mirror

**Executor: `step-executor`.** Repo `/Users/turbokach/Dev/claude-code-setup`, branch `master`.

Convention (`docs/prompts/opus-5-migration-handoff.md:24,49`): `global/CLAUDE.md` is the source;
after editing, `cp` it to `~/.claude/CLAUDE.md` and verify with `diff -q`. Both files are currently
byte-identical — keep them that way. Read `global/CLAUDE.md` in full before editing; anchors below
are line numbers as of `c75c76e`.

**1a — mechanism-not-trigger.** `global/CLAUDE.md:24`, last bullet of "### 4. Goal-Driven
Execution". Append to the existing `- Find root causes — no temporary fixes or band-aids.` bullet:

> Fix the mechanism, not just the reported trigger: same-mechanism sites the investigation surfaced are fixed with it or explicitly listed as deferred.

**1b — gate sizing.** `global/CLAUDE.md:41`, the `- **Earn the decision gate.**` bullet in
`## Operations`. Append after the existing final sentence ("A gate I must reject to go research
myself is worse than no gate."):

> Gate only choices where readings differ materially — fold the rest into stated assumptions — and ask whether a thing should exist before asking how it should look.

**1c — render evidence.** `global/CLAUDE.md:22`, the `- **Green unit tests are not "done."**`
bullet. Add one clause in that bullet's existing voice (second person, em-dash asides) carrying:
when a project's declared final gate is the owner's own device pass, visual changes still require a
cheap isolated render (component screenshot, `ImageRenderer` harness, or simple HTML mock) as
evidence before being presented; the owner's device checklist covers only what hardware alone can
show (multi-touch, feel, performance). Do not restate the adjacent `:23` "stays off main" bullet or
the `:43` "Render, don't ASCII-sketch" bullet.

**1d — `/autoplan` gate cap.** `global/CLAUDE.md`, `## Tooling` (`:51-54`). Add a new bullet after
the **gstack** bullet at `:54`, verbatim:

> - **/autoplan gate cap**: at the final approval gate, surface only the materially-divergent taste items (target ≤5); every surfaced item's options include the simplest choice (often "remove it entirely" / "do nothing"). This intentionally overrides the skill's "surface all taste decisions" instruction.

**1e — TODOS backlog rule (new file).** Create `global/rules/todos-backlog.md`, then
`mkdir -p ~/.claude/rules && cp` it to `~/.claude/rules/todos-backlog.md`. Frontmatter scopes it to
`TODOS.md`, `**/TODOS.md`, `docs/todos/**` (block-style YAML list, matching the existing convention
in `/Users/turbokach/Dev/clipsy_ios/.claude/rules/*.md`). Body states the convention:

- `TODOS.md` is a pure index — one line per task, `- **<Title>** — <≤120-char hook> → [docs/todos/<slug>.md](docs/todos/<slug>.md)` — grouped Gates(P1)/P2/P3/Unprioritized, deploy-blocking gates marked.
- Every new TODO = one detail file at `docs/todos/<slug>.md` (What/Why/Context/Depends/Effort) plus one index line — never an inline body in `TODOS.md`.
- Completing a task = delete its detail file and its index line. Git history is the archive — no `done/` directory.
- On finding a monolithic `TODOS.md` with inline bodies, offer to split it to this pattern (verify by byte-identical reassembly).

Working reference for the executor (do not copy prose from it, do not edit it):
`/Users/turbokach/Dev/clipsy_ios/TODOS.md` already implements this shape.

**1f — installers.** Two installers exist (per `1191c60` "which both installers missed"):
`install.sh` and `INSTALL.md` (the guided/agent path). Neither copies `global/` wholesale — both
enumerate surfaces explicitly:

- `install.sh:45-59` loops skills then `agents/*.md`; `install.sh:22` does the `mkdir -p`. Add a `global/rules/*.md` → `$DEST/rules/` copy alongside, using the file's existing `backup()` helper.
- `INSTALL.md:65-93` ("Step 2 — Execute", **Core kit** block) mirrors the same copies inline. Add the equivalent lines there so the guided path installs the rules too.

Clobber policy (decided): `install.sh` never clobbers `CLAUDE.md` (`:38`), but `rules/*.md` follow
the **skills/agents pattern — back up via `backup()`, then replace**. Say so in the commit message.

**1g — surface listings.** The same class of miss as `1191c60` (a new surface installed but not
declared), so fix it in this step:

- `README.md:23` — add a table row for `global/rules/` describing it as the path-scoped user rules installed to `~/.claude/rules/`, in the voice of the existing `global/CLAUDE.md` row.
- `skills/stack-update/SKILL.md:55-61` — the "Group bullets by the surfaces the user actually has installed" list. Add a `global/rules/*` bullet alongside `skills/*` (`:58`) and `agents/*` (`:59`), in the same user-facing voice, so `/stack-update` reports changes to the rule file. That list is the only surface enumeration in the skill; `docs/prompts/auto-update-plan.md:87` names the same surfaces but is a historical plan record — **do not edit it**.
- Mirror the SKILL.md edit to `~/.claude/skills/stack-update/SKILL.md` (`cp`, per the mirroring rule in `docs/prompts/opus-5-migration-handoff.md:49`) and verify with `diff -q`.

**Acceptance**
- `diff -q global/CLAUDE.md ~/.claude/CLAUDE.md` → identical.
- `global/rules/todos-backlog.md` and `~/.claude/rules/todos-backlog.md` both exist and are identical.
- `bash -n install.sh` passes; the INSTALL.md core-kit block covers `global/rules/`.
- `diff -q skills/stack-update/SKILL.md ~/.claude/skills/stack-update/SKILL.md` → identical.
- `git diff` shows only 1a–1g — no reflowed lines, no adjacent-bullet edits.
- Commit on `master` with a message naming the forensics origin. No push.
- `/codex review` on this step's diff before the commit is accepted (gate).

---

## Step 2 — clipsy_ios project CLAUDE.md

**Executor: `step-executor`.** Repo `/Users/turbokach/Dev/clipsy_ios`, current branch `dev`
(confirm with `git status` first; `dev` is 1 ahead of `origin/dev`).

Read `/Users/turbokach/Dev/clipsy_ios/CLAUDE.md`. Add a short **"Visual verification"** subsection
under `## Workflow rules` (`:71`), placed after the "Apple best-practices first" subsection
(`:79-81`) and before "### Other path-scoped rules" (`:83`). Match that file's style: `###` heading,
3–5 tight bullets or one short paragraph, no preamble. Content:

- Visual/UI fixes are presented with an isolated render as evidence — SwiftUI `ImageRenderer` or a snapshot-harness screenshot (the repo already has `ClipsySnapshotTests/`), the cheap kind, not a full simulator drive.
- The owner's on-device pass remains the pipeline's final gate, and covers only what hardware alone shows: multi-touch gestures, feel, performance.
- Ambiguous geometry/layout requests get a rendered mock at the plan gate, before execution.

Touch no other section — in particular leave `### /codex challenge fix-loop`, `### Other
path-scoped rules`, and `## Skill routing` untouched.

**Acceptance**
- `git diff --stat` in that repo shows `CLAUDE.md` only (the untracked `docs/prompts/sentry-crash-reporting-plan.md` stays untracked and uncommitted).
- Committed on the current branch. **Nothing pushed.**
- `/codex review` on this step's diff before the commit is accepted (gate).
