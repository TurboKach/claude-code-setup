### `skills/feature-workflow/SKILL.md:52` — no fallback if real+regression lines alone exceed the cap

The verdict size contract now permits truncation to drop only `test-gap` and
`theoretical` lines. Codex round 4 noted there is no fallback when the real
and regression lines alone exceed 2,000 characters.

**Declined, not fixed.** It needs ~22+ real findings on a single diff, and it
cannot produce a wrong decision: clean is defined as zero real and zero
regression, the counts line is never dropped, and a verdict overflowing with
real findings is definitively not clean. Error handling for a case that
cannot change the outcome. Same round-4 verdict file as above.
