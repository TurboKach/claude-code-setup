### `skills/feature-workflow/scripts/codex-challenge.sh` — elapsed-line accuracy gaps

Standalone findings deferred after the elapsed-time arc's fix loop went clean
(0 real, 0 regression on `2346374..468d7f5`). Both concern what the stderr
timing line measures, never whether the review gate runs or what it reports.

1. `[conf:0.5] :176 — test-gap` — every setup exit (bad range, `base` not an
   ancestor, missing `gtimeout`/`codex`, under 2 GB free, worktree add failure;
   lines 10–64) returns before the printf, so a run that dies in setup prints no
   timing line at all. The exit codes (64/65/66/67) already distinguish those
   cases, and none of them is slow — the timing only matters for a run that
   reached codex.

2. `[conf:0.4] :166 — theoretical` — `secs` is computed before the `--pin` EXIT
   trap runs its DerivedData sweep and `worktree remove`, so a pinned run's
   reported elapsed excludes cleanup while the comment above `start` claims
   whole-run coverage. Either move the printf into the trap or reword the
   comment; the reported figure is otherwise correct for everything the caller
   waits on.

**Depends:** nothing. **Effort:** minutes each.

Not deferred from the same rounds, and deliberately not acted on: the
single-attempt capacity bail (the chosen design), wall-clock non-monotonicity
under an NTP step, and a codex output-format change missing the capacity branch
— that last one degrades to the pre-existing retry ladder, which is the safe
direction.
