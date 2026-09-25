### Deferred from the subagent no-background arc — 2026-09-04

The stage-5 gate was clean at `6e90f42` after three rounds (round 1: two P1s — the raw-text
rule-B regex over-matching, fixed; the shell-`&` bypass, reclassified P2 below; round 2: the
same regex mechanism hit again via quoted text, replaced structurally — quoted segments
stripped, loop keyword at a command boundary; round 3: one P1 claiming `BASH_MAX_TIMEOUT_MS`
unset clamps the 15-min default — false, the env-vars docs say the ceiling is the larger of
the two and the binary computes `Math.max`). Verdicts: `docs/reviews/subagent-no-background/`.
The owner deferred every standalone line rather than loop on them.

1. `[P2 conf:0.6] hooks/subagent-no-background.sh:76 — rule A is bypassed by shell &, nohup, setsid, disown; denying & would break the working xcodebuild … & + foreground pgrep-wait pattern → round1 #1, round3 theoretical #1`
2. `[conf:0.4] hooks/subagent-no-background.sh:76 — theoretical: a foreground command auto-backgrounded past the 15-min default bypasses rule A; inherent to a pre-execution hook → round3 theoretical #2`
3. `[P2 conf:0.5] hooks/subagent-no-background.sh:66 — rule B misses marker=… indirection and a loop inside bash -c "…" (quoted text is stripped by design) → round1 #3, round2 #2`
4. `[conf:0.5] hooks/subagent-no-background.sh:66 — test-gap: a loop after then/do (if …; then until [ -f x.output.done ] …) is not at a boundary char and passes → round3 test-gap #1`
5. `[P2 conf:0.4] hooks/subagent-no-background.sh:67 — a project's own *.output.done sentinel poll is denied like the harness marker; no such file exists in any owner repo → round2 #3, round3 test-gap #2`
6. `[P2 conf:0.5] hooks/subagent-no-background.sh:56 — the deny text's pgrep -f wait matches any same-named process system-wide, not the backgrounded task; bracket trick added for the self-match only → round1 #4, round2 #5, round3 #1`
7. `[P2 conf:0.4] install.sh:309 — register_hook treats an existing same-path entry with a wrong type/timeout as installed and never repairs it → round3 #3`
8. `[P2 conf:0.5] skills/feature-workflow/SKILL.md:47 — doctrine: the close-out pgrep -f output.done check is global, not session-scoped → round1 #5 (doctrine, report-only)`

Not deferred, because triage found it false: install.sh:314 "unquoted hook path" (every
hook path is a quoted argv element written via json.dump — dropped in all three rounds).
