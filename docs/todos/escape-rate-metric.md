### `skills/analyze-arcs` — no escape-rate metric, so per-step codex rounds can't be judged on value

**What.** For each arc, count bugs found early (per-step rounds) against bugs found late:
stage-5 real P0/P1 findings in code that had already passed its step's tests and per-step
round (an "escape"). Report both numbers per arc and as a trend in the weekly report.

**Why.** Per-step rounds cost wall time and codex quota, and usage limits have already killed
launches mid-arc. If they catch bugs early that would otherwise cause rework in later steps,
they pay off. If stage 5 catches the same bugs anyway, they are cost without value. Today
nobody can tell which case holds. Idea source: the "CI escape rate" in "AI Broke the
Assumptions Behind CI" (https://stack72.dev/ai-broke-the-assumptions-behind-ci/).

**Context.** Method: for each stage-5 real P0/P1 `file:line`, run `git blame` at the stage-5
head to find the commit that introduced the line, then map that commit to the per-step round
whose range contains it. An escape is a finding whose line sat in a reviewed range and was not
flagged there. Data source:
- The verified-head notes (docs/todos/verified-head-record.md) carry each round's range and its
  triaged verdict, so the data survives in git.
- Today the verdicts sit in session scratchpads, which get cleaned, so past arcs are probably
  unrecoverable (hypothesis, not checked). The count would start from the first arc that runs
  with the notes.

**Depends.** docs/todos/verified-head-record.md (the notes are the durable data source).

**Effort.** Half a session in `analyze.py`, plus one row in the weekly report's numbers table.
