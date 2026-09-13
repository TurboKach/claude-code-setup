### Deferred from the review-model-picker arc — 2026-09-10

The stage-5 gate was clean at `ec501c9` — round 1 ran on `gpt-5.6-sol` (one P2) and round 2 on
`gpt-6-astra` (zero real, one theoretical) over the identical tree; no code changed between
them, round 2 existed only because a leaked `CODEX_REVIEW_MODEL` env var had overridden the
intended model in round 1. The two defects the per-step round found in the permanent-error bail
were fixed during the arc (`f703d0a`), not deferred: the `^ERROR:` anchor never matched under
`--trace`, and codex pretty-prints the effort-400 body across multiple lines — three of four
failure cases burned ~620s before the fix, all four bail in under 10s after it. Verdicts:
`docs/reviews/codex-review-model-picker/`. Entries 4-5 are session findings with no verdict file.

1. `[P2 conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh:129-131 — the bail's anchor grep and content grep are scoped independently to the attempt's whole log chunk rather than jointly to one event, so a transient turn.failed line co-occurring with unindented 400-keyword text elsewhere in the chunk aborts retries on a real outage → whole-round1 #1, whole-round2 theoretical #1 (both models flagged it)`
2. `[conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh:124 — theoretical: the attempt chunk is captured into a shell variable once per grep; memory pressure only if a single --trace attempt emits a pathological stream before failing → whole-round1 theoretical #1`
3. `[P2 conf:0.6] skills/feature-workflow/scripts/codex-challenge.sh:99 — model is pinned while model_provider is inherited, so an Azure/--oss/custom-provider config sends the pinned model to a provider that does not have it and burns the retry loop; CODEX_REVIEW_MODEL is the only escape → docs/reviews/codex-model-pin/codex-whole-round1.md #1 (raised pre-picker, now reachable by any user who picks a model)`
4. `[P2 conf:0.9] skills/feature-workflow/SKILL.md:18,56 — doctrine: the stage-4/5 call strings name ~/.claude/skills/feature-workflow/scripts/codex-challenge.sh, the INSTALLED copy; when the repo under review IS the kit, every gate reviews the new code using the old script and silently at the old model/effort. This arc's step-1 round ran the pre-pin script and was briefly reported as exercising the pin; only the new verdict-header model field exposed it → session finding`
5. `[conf:0.8] global/CLAUDE.md — doctrine: the planner/plan-reviewer Fable pin has no documented fallback for quota exhaustion (429 "You've reached your Fable limit"). This arc's first team-planner spawn died at launch having emitted 93 chars and zero tool calls; the master substituted Opus 5 by hand, citing the pre-experiment baseline → session finding`
