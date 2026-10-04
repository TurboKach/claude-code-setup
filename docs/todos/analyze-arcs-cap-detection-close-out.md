### analyze-arcs turn-cap detection — review close-out, 2026-10-04

Codex gate on 18ee899..dfab752, two rounds (the stage-5 limit). Round 1 found one real P2 — a cap
the master recorded vanished when its subagent file was pruned — fixed in dfab752 (`cap_flags()`).
Round 2 confirmed that fix and left the items below; the owner chose to record them and push.

1. `[P2 conf:0.5] skills/analyze-arcs/scripts/analyze.py:411` — `main()` skips a master under
   `--min-kb` (default 150) that has no subagent files, so if cleanup deleted all of a small
   master's subagent files, its cap notifications never reach the missing-file fallback. Fix: scan
   small masters for `CAP_NOTE`, or skip the size filter when the master mentions a cap.
2. `[P2 conf:0.4] skills/analyze-arcs/scripts/analyze.py:30` — `CAP_NOTE` matches
   `<summary>[^<]*stopped at…`; a `<` in the summary before the marker (an agent description such as
   `fix x < y`) blocks the match and the cap drops out silently. Fix: read the whole `<summary>`
   (`(?:(?!</summary>).)*?`) and add a test with a `<` in the description.
3. `[conf:0.5] analyze.py:254` — theoretical: a user message that quotes the full notification
   markup fakes a cap (fabricated agent id, inflated count). Needs a pasted notification; no
   provenance check exists for user records.
4. Round-1 theoreticals, verbatim: `[conf:0.4] analyze.py:30` — CAP_NOTE is quadratic on many
   repeated `<task-id>` tags with no summary (pathological multi-100KB message, local tool);
   `[conf:0.4] analyze.py:266` — a foreground agent result that quotes another agent's "stopped at
   its N-turn limit before finishing" text is marked capped.

Both P2s are edge cases in a local report tool; neither affects a pipeline run.
