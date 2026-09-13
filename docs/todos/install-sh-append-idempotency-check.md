### `install.sh:116-117` — append idempotency check requires an exact `## Feature workflow` heading

The `--claude-md=append` mode's idempotency check matches only the literal
line `## Feature workflow` (CRLF-tolerant, otherwise exact). A hand-edited
variant — a trailing space, a closing `##`, or any other equivalent heading
syntax — isn't recognized as "already present," so a re-run appends a second,
duplicate section instead of skipping.

**Introduced by this feature** — the `--claude-md=append` mode is new.
**Deferred because:** it needs a deliberate decision about how tolerant the
match should be, and every previous attempt to make this check cleverer
(fence-tracking, etc.) produced new edge cases of its own — round 3
deliberately settled on this exact match as the simple, correct-by-inspection
version. Recorded per the round-3 `/codex challenge` verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/5216f638-c3e8-4e76-a319-5478f71e801f/scratchpad/codex-install-consolidation-round3.md`.
