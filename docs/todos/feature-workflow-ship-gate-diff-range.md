### `skills/feature-workflow/SKILL.md:18` — the ship gate's diff range is probably ignored

Stage 5 and the `global/CLAUDE.md` ship gate both invoke
`Skill(codex, "challenge <feature-base-sha>..HEAD")`. But gstack's codex skill
parses `/codex challenge <text>` with everything after `challenge` as a **focus
area**, not a scope (`~/.claude/skills/gstack/codex/SKILL.md`, Step 1 mode
detection). The range string is then interpolated into the adversarial prompt as
a focus area, while the prompt itself still tells codex to run
`git diff origin/<base>` against the base branch detected in Step 0. So the gate
likely reviews the branch-vs-base diff rather than the recorded feature range,
and a range narrower or wider than the branch diff is silently not honored.

**Deferred because:** the fix belongs in gstack, not this kit — either a scope
flag on challenge mode, or a documented "challenge takes no range" contract that
stage 5 is then written against. Guessing gstack's intended argument shape from
this side would encode the wrong contract. Surfaced by the round-1 codex
challenge on the 2026-08-21 wall-clock doctrine edits, while verifying an
unrelated claim about challenge-mode diff scoping; not yet reported upstream.

**Resolved 2026-09-02:** measured (2026-09-01 backend and clipsy session
transcripts, 111 verdict files) — no recorded run ever diffed `origin/`;
masters bypassed the gstack path by hand-assembling each launch, which
drifted (three parser variants, 13 of 14 losing the `[codex ran]` audit
lines). `skills/feature-workflow/scripts/codex-challenge.sh` now owns the
invocation: one deterministic `codex exec` call on the explicit range, no
gstack scope-vs-focus-area ambiguity.
