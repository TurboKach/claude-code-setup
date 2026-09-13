### Deferred from the codex-challenge arc — 2026-09-02

The stage-5 gate was clean at `ac1424d`; these are the standalone P2/test-gap/theoretical
lines the owner deferred rather than looped on. Round 3 at `5acce42` (exit 0, 1000s) found
one new P1 in INSTALL.md's readiness line, fixed in the commit that recorded this entry,
after round 2 had been clean.

1. `[P2 conf:0.5] global/CLAUDE.md:27 — gate hard-codes ~/.claude/… while install.sh honours CLAUDE_HOME (same mismatch as the INSTALL.md Step 0 entry above) → F2 #2`
2. `[P1 conf:0.6] skills/feature-workflow/scripts/codex-challenge.sh:38-48 — pin liveness is keyed on the wrapper shell PID ($$), not the codex/gtimeout child, in both directions: PID reuse can misread a dead run as live; independently, a wrapper killed via SIGKILL (bypassing the EXIT trap) leaves its codex/gtimeout child running while the next --pin invocation sees the wrapper as dead and force-removes the checkout out from under it — observed 2026-09-02 11:29Z, a fixer's 3-second timeout killed the wrapper and codex ran on for six minutes before the sweep deleted its dir. Mitigated: the sweep now also treats the dir as live when any process has its path in argv (`pgrep -f`), closing the killed-wrapper direction; PID reuse remains open → F1 #7, codex-final-round1.md:16, codex-final-round3.md:18.`
3. `[P2 conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh:60 — -s read-only bounds shell writes, not MCP/connector side effects reachable from reviewed content → F1 #6`
4. `[conf:0.5] skills/feature-workflow/scripts/codex-challenge.sh:52 — test-gap: no self-check that codex actually ran the range diff; the --trace log is the only evidence → S1 test-gap #1`
5. `[conf:0.5] skills/feature-workflow/scripts/codex-challenge.sh:71 — test-gap: exit 0 with an empty .msg reports success; the stage-5 parking rule covers it only at the doctrine level → S1 test-gap #2`
6. `[conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh:65 — theoretical: every non-zero exit retries, including permanent auth/config errors (two 5-min sleeps) → S1 (dropped-for-cap line)`
7. `[conf:0.4] skills/feature-workflow/SKILL.md:18 — theoretical: the unpinned stage-5 launch reads stray uncommitted working-tree state as final code → S2 theoretical #2`
8. `[conf:0.3] skills/feature-workflow/SKILL.md:22 — theoretical: unpinned slices read the final tree while triage verifies against git show <head>; consistent only while stage 5 has no writer → S2 theoretical #3`

9. `[P2 conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh:47 — the pin's worktree add runs outside the gtimeout wrapper; a hung LFS/smudge filter blocks --pin with no verdict → F3 #2`
10. `[P2 conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh:47 — the fixed 2 GiB preflight ignores actual checkout and LFS size → F3 #3`
11. `[P2 conf:0.3] INSTALL.md:16 — readiness checks that codex exists, not that it is authenticated; an unauthenticated codex reads "ready" until the gate fails → F3 #4`
12. `[conf:0.3] global/CLAUDE.md:49 — theoretical: the one-shot path does not say to commit before gating; an uncommitted one-shot makes <pre-change-sha>..HEAD collapse and the script exits 64 (loud, not silent) → F3 theoretical #1`
13. `[conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh — no committed self-test; fixers rebuild throwaway stubs each arc, and one accidentally started a real codex invocation → B5`
14. `[P2 conf:0.3] skills/feature-workflow/scripts/codex-challenge.sh:33,49 — the pin scratch directory and worktree are created under the default umask, world-readable on a shared machine → F2 (never triaged)`
15. `global/CLAUDE.md:26 — push-approval gate is prose-only, no PreToolUse hook. Considered and rejected: no push-without-approval incident is recorded; gstack's question-preference hook shows marker-based gating is feasible if one ever occurs → C5`
16. `[P2 conf:0.4] codex-challenge.sh:69 — rm -f "$out" then >"$out" leaves a symlink TOCTOU window for a local attacker sharing the directory → evaluation round 1`
17. `[conf:0.5] SKILL.md:18 — theoretical: convergence keys on mechanism identity across rounds, but triage spawns see one round and verdicts carry no stable mechanism id; the master matches by text → evaluation round 1`

Not deferred, because triage itself found it did not reproduce or was already documented: the
oversized single commit (fallback sentence added in `ac1424d`), "one background Bash" vs split
provision (reconciled in the skill), the unpinned live-tree tradeoff (documented in Token
discipline), the split-slice verification premise, verdict-commit-postdates-range (inherent),
and the stage-5 `--pin` premise mismatch.
