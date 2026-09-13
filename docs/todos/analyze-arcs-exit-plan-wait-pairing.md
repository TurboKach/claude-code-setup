# analyze-arcs: ExitPlanMode wait-time flag pairs by time, not call id

**What:** the pre-existing "ExitPlanMode never approved / waited >60 min" flag in
`skills/analyze-arcs/scripts/analyze.py` (`main()`, the `exit_plan` /
`plan_approved` loop) pairs each ExitPlanMode with the next approval by
timestamp. A rejected exit followed later by an approved one is credited with the
approval's wait time; the rejected exit itself is never reported as rejected.

**Why:** codex round 3 of the master-authors-plan arc [P1 conf:0.65]; not in that
range's diff, so deferred. The plan-mode read flag already links approvals to the
call id via `pending_q` — reuse that for this flag.

**Context:** a rejected ExitPlanMode result is `is_error: true` with rejection
text; an approved one carries "User has approved your plan". Both are results of
the same call, matched by `tool_use_id`.

**Depends:** nothing. **Effort:** ~20 min, one Sonnet fixer, test in
`test_analyze.py`.
