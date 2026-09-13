### `skills/feature-workflow/SKILL.md:17` — mixed dependency graph relies on a derived precondition

Stage 3 now chains a task only where a step consumes an earlier one's output,
so `TaskList` can show a dependent step and an independent step unblocked at
the same time. Codex round 4 argued that an un-isolated `step-executor` could
then run alongside a worktree-isolated `team-executor`.

**Declined, not fixed.** Stage 4 already states the precondition where the
choice is made — `step-executor` is "the only writer in flight" — so two
concurrent writers is not a state that rule permits, and concurrent
independent steps go to the `agent-teams` skill, which owns REVIEW/MERGE via
`team-merger` (codex read this as an ad-hoc `team-executor` spawn with no
merge owner, which the sentence does not say). Fixing it would restate a
condition the sentence already carries. Recorded because a careful reader has
to *derive* the mixed-graph case rather than read it: if it ever bites, the
minimal fix is one clause in stage 4, not a new rule. Round-4 verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/a4bff32a-75bb-4ec0-b24d-7d092e902147/scratchpad/codex-verdict-contract-round4.md`.
