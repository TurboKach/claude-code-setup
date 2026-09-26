# fixer at effort high: measure the trial, then keep or revert

**What:** `agents/fixer.md` moved from `effort: medium` to `high` on 2026-09-26.
Decide keep or revert from measured arcs, not from the article alone.

**Why:** claude.dev "Using Claude Code: Spending your effort" (2026-09-25): a
brownfield bug fix is the high-effort case, where effort buys reproducing before
editing and the adjacent edge cases the next review round would otherwise find.
The pain it targets is the non-convergent stage-5 loop.

**Context:** baseline before the change, Opus-medium fixer runs since 2026-09-23:
n=21, median 25 turns, 84k peak context; the last measured arc had whole-range
rounds 1/1/2 and fixers at 95 min against executors at 263 min. Compare with
`analyze-arcs --since 2026-09-26`: whole-range rounds per feature, P0/P1 per
round, fixer turns and minutes per round. The article predicts per-round fixer
time up about 1.5x and fewer rounds.

**Depends:** 2–3 pipeline arcs after 2026-09-26. **Effort:** one analyze-arcs
run, then either delete this file and its index line, or revert the one
frontmatter line.
