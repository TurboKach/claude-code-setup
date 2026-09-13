# Tech debt

Index of project-level deferred work. Each task's full context lives in its own file
under `docs/todos/` so a session only pays for the entries it touches.

Maintenance rules:

- New TODO = create `docs/todos/<slug>.md` with full context (What/Why/Context/Depends/Effort)
  + add ONE index line here — never inline task bodies in this file.
- Completed TODO = delete its file + its line.

## P2

- **`install.sh:177` — `RETIRED_AGENTS` entries aren't validated as plain basenames** — `RETIRED_AGENTS` array isn't checked for being a bare filename → docs/todos/install-sh-177-retired-agents-basename.md
- **`install.sh:164-168` vs `install.sh:178-185` — no disjointness check between shipped and retired agents** — Copy loop over `agents/*.md` runs before the retirement-prune loop, no disjointness check → docs/todos/install-sh-no-disjointness-check.md
- **`install.sh:116-117` — append idempotency check requires an exact `## Feature workflow` heading** — `--claude-md=append` idempotency check matches only the literal `## Feature workflow` line → docs/todos/install-sh-append-idempotency-check.md
- **`install.sh:113-132` — `elif awk ...` misreads a missing file as "not found," and the scan/backup/append aren't atomic** — `elif awk` misreads a missing CLAUDE.md as heading-not-found; scan/backup/append aren't atomic → docs/todos/install-sh-append-not-atomic.md
- **`INSTALL.md:19` — Step 0 detection hardcodes `~/.claude`, not `CLAUDE_HOME`** — Step 0 detection hardcodes ~/.claude while install.sh honors CLAUDE_HOME → docs/todos/install-md-step0-claude-home.md
- **`skills/feature-workflow/SKILL.md:17` — mixed dependency graph relies on a derived precondition** — Stage 3's mixed dependency graph relies on a derived precondition, not a stated one → docs/todos/feature-workflow-mixed-dependency-graph.md
- **`skills/feature-workflow/SKILL.md:52` — no fallback if real+regression lines alone exceed the cap** — No fallback when real+regression lines alone exceed the verdict size cap → docs/todos/feature-workflow-verdict-cap-fallback.md
- **`global/CLAUDE.md:12` — simplicity mnemonic cut, salience not replaced** — Simplicity mnemonic line was cut from CLAUDE.md, salience cue not replaced → docs/todos/claude-md-simplicity-mnemonic-cut.md
- **Deferred from the codex-challenge arc** — Standalone P2/test-gap/theoretical findings deferred after the stage-5 gate went clean → docs/todos/deferred-codex-challenge-arc.md
- **Deferred from the subagent no-background arc** — Standalone findings deferred after the stage-5 gate went clean across three rounds → docs/todos/deferred-subagent-no-background-arc.md
- **Deferred from the review-model-picker arc** — Standalone findings deferred after the stage-5 gate went clean across two model rounds → docs/todos/deferred-review-model-picker-arc.md
