# Evaluation of the codex-challenge arc (2026-09-02)

Source: `/tmp/codex-arc-verdicts.json` (20 resolved items + critic pass),
`/tmp/codex-arc-evidence.json` (measured facts), and
`docs/prompts/codex-challenge-arc-handoff.md`. Two-stage resolution: 8 Sonnet
readers produced the evidence digest, then 20 items each went through a
judge, three refuters, and a resolver, plus one critic pass over the set.

## (a) Verdict in three lines

Overall: **tune** (confidence 0.74). The 2026-09-02 script + doctrine cut is a
real determinism and audit-trail win over 2026-09-01's hand-assembled
`codex exec` launches, but the win is unproven on the script's own core
safety mechanism — `--pin` never fired once, in this arc or the prior
backend arc.

The installed `~/.claude` kit is stale and the drift is rated critical: the
live-loaded hard gate names the retired gstack `/codex` skill, not
`codex-challenge.sh`, so the pipeline as a thing a fresh session actually
runs is not yet the improved pipeline the repo describes (item E).

Of 20 items: 13 land now (A1–A4, B1, B2 mitigation, B4, C1, C2 rows 1–5 and
7, C3 six cuts, C4 three, C7 two, E), 6 stay deferred pending more evidence
or an owner action (B3, B5, B6, C4 team-reviewer/merger, C5, C6, C2 row 7's
settings-key deletion), 1 is dropped with no record (C7's remaining ~42
residue items), and D (battle test) is go-with-preconditions once E's
`/stack-update` runs.

## (b) Corrections to the handoff

Seven measured corrections, verified against `/tmp/codex-arc-evidence.json`
and applied to `docs/prompts/codex-challenge-arc-handoff.md`:

1. **Context and transcript count.** Master context peak was 566,085 tokens
   (last assistant usage block, `timeline.master_context_peak_tokens`), not
   "roughly 250k" — context grew monotonically through the session's final
   30 minutes with zero compaction events, so no point in the transcript
   reads 250k. The `subagents/` directory holds 19 agent transcripts, not
   39; the audit workflow's 204 agents live separately under
   `subagents/workflows/`.
2. **The pin path was never exercised, in either arc.** All 5
   `codex-challenge.sh` launches this arc ran unpinned — the master's own
   `df` pre-check refused at 7.67 GiB before `--pin` was ever passed
   (`timeline.pin_refusals[0]`). The 2026-09-01 backend arc predates the
   script entirely (it used hand-rolled `git worktree add --detach`, not
   `codex-challenge.sh --pin`), so the script's own pin/liveness code —
   including the wrapper-PID liveness bug B2 documents — has zero runtime
   exercises across both arcs.
3. **Trace sidecars did not survive.** The master read the five `--trace`
   logs in-session, but none of the five `.log` sidecars are present now.
   The one surviving log in the evidence (`script.trace_log_audit`,
   307,574 bytes, base `0bdbf89d`/head `ac1424d`) is plain human-readable
   text, not a `--json` stream — it traces to the fixer's orphaned
   `--out --pin` bug-reproduction run (`timeline.runs[5]`), not to any of
   the 5 official review rounds. "TRACE PASS on every run" is not
   re-verifiable from what remains.
4. **Duration is not size-invariant.** Runs measured 551–1000 s this arc and
   237–1670 s per step on the 2026-09-01 backend arc; launch-to-triaged-
   verdict ran 11.5–18.7 min across the 5 runs
   (`wall_clock_to_triage_verdict_s` / 60); the step-3 dependency-boundary
   wait measured 21.5 min end-to-end (`timeline.boundary_waits[0]`). No
   per-step diff-size (insertions/deletions) figures exist anywhere in the
   evidence to correlate against — the "~10 min regardless of diff size"
   claim was an unverified inference, not a measured fact.
5. **The round-3 P1 was reportable at both earlier heads and missed twice.**
   `stability.f3_new_p1`: the INSTALL.md `gtimeout`-vs-`timeout` line is
   byte-identical at `d692216` (F1's head) and `ac1424d` (F2's head); F1 and
   F2's verdict files contain zero mentions of INSTALL.md. The line was
   readable and true at every round's head but only F3 reported it.
6. **Per-step value is asymmetric between the two arcs.** This arc: 7
   distinct mechanisms were fixed before the first whole-range round, and 0
   of them would plausibly have been caught by a whole-range diff review at
   that head, because the fix commits fall inside the reviewed range and
   cancel the bug out of the diff (`stability.per_step_value`). Backend:
   per-step rounds found 11 real findings total, but whole-range round 1
   still found 3 new P1s and 3 new P2s in the exact two files whose own
   per-step rounds had already passed clean
   (`backend.per_step_vs_whole_range`) — so "whole-range catches nothing
   per-step already caught" is a hypothesis this arc's data doesn't test
   and the backend data contradicts for the reverse direction.
7. **One finding was orphaned, not deferred.** M30 (pin-scratch-dir default
   umask makes the checkout world-readable to other local users) was
   reported once, in F2, then never fixed, never added to
   `docs/tech-debt.md`, and never re-reported in F3 — it simply drops out
   of the record with no documented disposition
   (`stability.mechanisms[M30]`).

## (c) Per-item table

| Item | Verdict | Conf. | Change | Status |
|---|---|---|---|---|
| O. Overall | tune | 0.74 | Handoff numbers corrected (see (b)); pin-path exercise and installed-kit drift named as the material gaps. | applied 2026-09-02 |
| A1. "waiting costs a step-sized run" | tune | 0.74 | Replace the placeholder with the measured 21.5 min boundary-wait figure; note it supersedes the handoff's rougher ~14 min for the same event. | applied 2026-09-02 |
| A2. Convergence rule | tune | 0.74 | Key the structural-branch trigger on repeat findings of the *same mechanism*, not any non-decreasing P0/P1 count; a new unrelated P0/P1 takes one ordinary patch round. | applied 2026-09-02 |
| A3. `--trace` default | tune (doctrine edit, not script flip) | 0.8 | Add `--trace` to the two verbatim `codex-challenge.sh` call strings in `SKILL.md`, not a script-level default flip. | applied 2026-09-02 |
| A4. 10 GB pin threshold | tune | 0.8 | Lower to 2 GB (measured tracked-checkout size, not whole-directory `du`; largest sampled repo is ~81 MB); park exit 66 with no unpinned fallback. | applied 2026-09-02 |
| B1. Symlink at `--out` | do | 0.78 | `rm -f "$out"` before the final redirect, mirroring the existing `.msg`/`.log` idiom; renumber tech-debt item 1 out. | applied 2026-09-02 |
| B2. Wrapper-PID liveness | defer, reprioritized | 0.78 | Tech-debt entry widened: covers both PID-reuse *and* the more severe SIGKILL-orphans-a-foregrounded-child force-delete path; priority raised P2→P1. No code change — 0/5 runtime exercises. | applied 2026-09-02 (mitigation: tech-debt text only) |
| B3. Worktree add outside timeout | defer | 0.75 | No edit — item 11 stays filed as-is; trigger (LFS/smudge hang) is structurally absent in both product repos today. | deferred |
| B4. `--ephemeral` flag | do | 0.6 | Add `--ephemeral` to the `codex exec` line for disk hygiene (2.1 GB / 4485 files, no cleanup policy). Lowest-confidence "do" in the set — flag semantics are source-only, unverified across codex-cli versions. | applied 2026-09-02 |
| B5. Committed self-test | defer (was: drop) | 0.68 | Not built now; tracked instead of dropped — the owner's decline predates the near-miss it was said to answer by >2h, and the real repeat-exposure (MCP egress, not just `$out`) is larger than originally framed. | deferred |
| B6. MCP servers live during read-only review | defer | 0.85 | No change — no official review round's trace log has actually been audited for MCP activity (the only OAuth-error hit traces to the orphaned fixer run, not a real round); absence-of-exploitation is an evidence gap, not a clean negative. | deferred |
| C1. Seven factual defects | do | 0.83 | 6 doc corrections across `docs/references.md`, `global/CLAUDE.md`, `README.md` (Explore cap 2.1.257→2.1.198, Fable-guide attribution trims, "Opus roles"→pinned-roles wording). | applied 2026-09-02 |
| C2. Six cross-file contradictions | do | 0.76 | Rows 1–5 (maxTurns/respawn wording, agent-teams prose budget, decision-flow Gate 0, CLAUDE.md one-shot/pipeline split, team-executor's missing Bash-timeout bullet) and row 7's doctrine correction land; row 7's actual `~/.claude/settings.json` key deletion needs the owner. | applied 2026-09-02 (rows 1–5 and 7's doc correction); row 7's settings-key deletion deferred |
| C3. Agent/skill-body duplication of CLAUDE.md | do (6 of 7) | 0.7 | 6 cuts (#8, #33 + companion fixer.md header fix, #59 narrower, #65, #66, #67); #64 stays deferred — no concrete before/after, wrong duplication target. | applied 2026-09-02 |
| C4. Missing `maxTurns` on five agents | split | 0.74 | 3 applied now (team-planner:100, team-plan-reviewer:60, explorer:60 — single-pass, convention-matching, low risk); team-reviewer and team-merger deferred — both are O(units) workloads a flat cap could truncate. | applied 2026-09-02 (three); deferred (two) |
| C5. Push-approval PreToolUse hook | defer, do not build | 0.74 | Hook not built (marker-only enforcement false-positives on plain-chat approval); add a `docs/tech-debt.md` entry recording the considered-and-rejected mechanism instead of no record. | deferred |
| C6. Move skill-body "why" narration | defer (was: do) | 0.72 | Not applied — all 5 hunks point at `docs/feature-workflow-forensics.md#<anchor>`, a file that doesn't exist; landing as scoped leaves dangling links. | deferred |
| C7. Audit residue (45 items) | do (2) / drop (rest) | 0.8 | 2 do-now: README.md's Explore-floor exception wording, agent-teams SKILL.md's orphaned CODEX step fenced correctly. Item 1 (decision-flow.md:45) reverts to report-only — a prior arc decision already left it unfixed on purpose. Remaining ~42 items stay dropped, no record. | applied 2026-09-02 (two); dropped (~42, one reverted to report-only) |
| D. Battle test on a product repo | go-with-preconditions | 0.87 | Preconditions: (a) free disk — owner judgment call on a 460 GB volume at 99% full; (b1) mechanical — bare `install.sh` restores the missing `skills/feature-workflow/scripts/`; (b2) owner judgment — the stale gate line needs `--claude-md=replace` or `/stack-update`'s three-way diff, not a bare install. Repo choice (backend) and what-to-measure guidance unchanged. | go-with-preconditions |
| E. Installed-kit drift | do | 0.88 | `~/.claude` is 14 commits stale (`60ad075`); live gate names the retired gstack skill; `install.sh`'s default "auto" mode and its append-mode idempotency check (matches on `## Feature workflow`, already present) both leave the stale `CLAUDE.md` untouched. Recommended fix: `/stack-update`'s existing three-way diff, not a raw `--claude-md=replace`. | applied 2026-09-02 (documented as handoff item E) |

### Before/after (applied items)

### A1
`skills/feature-workflow/SKILL.md:17`
```diff
- a step blocked by nothing pending spawns immediately, and its round launches in the same turn — waiting costs a step-sized codex run (per-step rounds were already step-scoped in practice; the 14–22 min figure is whole-range), and concurrent read-only runs are fine, each pinned at its own head.
+ a step blocked by nothing pending spawns immediately, and its round launches in the same turn — waiting at a real dependency boundary costs about 21.5 min end-to-end (2026-09-02 kit arc, step2→step3: round 694s + two serialized fixers; supersedes the arc handoff's rougher ~14 min estimate for the same boundary), and concurrent read-only runs are fine, each pinned at its own head.
```

### A2
`skills/feature-workflow/SKILL.md:18`
```diff
- **Convergence decides the loop, not a round count:** a round whose P0/P1 count does not strictly decrease forces the structural branch — an Opus mechanism-fixer under the same-mechanism clause (Token discipline), or AskUserQuestion when the structural fix exceeds the plan's design contract — never another patch round. Exit at zero P0/P1, or after two consecutive non-decreasing rounds: stop, defer the remainder, report.
+ **Convergence decides the loop, not a round count:** a round whose P0/P1 findings hit the mechanism an earlier round already patched (the same-mechanism clause, Token discipline) forces the structural branch — an Opus mechanism-fixer, or AskUserQuestion when the structural fix exceeds the plan's design contract — never another patch round. A round whose count merely fails to decrease because of a new, unrelated P0/P1 is not a repeat: it takes one more ordinary patch round like any other P0/P1, no gate. Exit at zero P0/P1, or after two consecutive rounds hitting the same mechanism: stop, defer the remainder, report.
```

### A3
`skills/feature-workflow/SKILL.md:17`
```diff
- Verbatim call: `~/.claude/skills/feature-workflow/scripts/codex-challenge.sh <base>..<head> --pin --out <scratchpad>/codex-step<N>.md`
+ Verbatim call: `~/.claude/skills/feature-workflow/scripts/codex-challenge.sh <base>..<head> --pin --trace --out <scratchpad>/codex-step<N>.md`
```
`skills/feature-workflow/SKILL.md:18`
```diff
- The master launches `~/.claude/skills/feature-workflow/scripts/codex-challenge.sh <feature-base-sha>..HEAD --out <file>` as one `run_in_background` Bash
+ The master launches `~/.claude/skills/feature-workflow/scripts/codex-challenge.sh <feature-base-sha>..HEAD --trace --out <file>` as one `run_in_background` Bash
```

### A4
`skills/feature-workflow/scripts/codex-challenge.sh:45`
```diff
- [ "$(df -k "$scratch" | awk 'NR==2{print $4}')" -ge $((10*1024*1024)) ] || { echo "under 10 GB free on $scratch; refusing to pin" >&2; exit 66; }
+ [ "$(df -k "$scratch" | awk 'NR==2{print $4}')" -ge $((2*1024*1024)) ] || { echo "under 2 GB free on $scratch; refusing to pin" >&2; exit 66; }
```

### B1
`skills/feature-workflow/scripts/codex-challenge.sh:67`
```diff
- { echo "# codex challenge — range $base..$head — checkout $dir — exit $rc — $(( $(date +%s) - start ))s"
-   cat "$out.msg" 2>/dev/null || echo "(no final message; see $out.log)"; } >"$out"
+ rm -f "$out"
+ { echo "# codex challenge — range $base..$head — checkout $dir — exit $rc — $(( $(date +%s) - start ))s"
+   cat "$out.msg" 2>/dev/null || echo "(no final message; see $out.log)"; } >"$out"
```

### B2
`docs/tech-debt.md:173`
```diff
- 3. `[P2 conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh:41 — pin liveness keys on the wrapper shell PID, not the codex child; PID reuse can read a dead run as live → F1 #7`
+ 3. `[P1 conf:0.6] skills/feature-workflow/scripts/codex-challenge.sh:38-48 — pin liveness keys on the wrapper shell PID ($$), not the codex/gtimeout child, in BOTH directions: (a) PID reuse can misread a dead run as live, leaking a stale worktree past the 10GB preflight; (b) independent of reuse — codex exec runs in the FOREGROUND (line 60), so a wrapper killed via SIGKILL (bypassing the EXIT trap, line 48) leaves its child running as an orphan while the *next* --pin invocation correctly sees the wrapper as dead and force-removes the worktree out from under the still-live child, corrupting/truncating that review mid-read → F1 #7, codex-final-round1.md:16, codex-final-round3.md:18. Untriggered this arc: all 5 codex-challenge.sh runs were unpinned (pinned:false), so this code path never executed.`
```

### B4
`skills/feature-workflow/scripts/codex-challenge.sh:60`
```diff
- "$to" -k 60 2400 codex exec "$prompt" -C "$dir" -s read-only -c 'model_reasoning_effort="high"' -c 'web_search="cached"' -c 'project_doc_max_bytes=0' ${trace[@]+"${trace[@]}"} -o "$out.msg" </dev/null >>"$out.log" 2>&1
+ "$to" -k 60 2400 codex exec "$prompt" -C "$dir" -s read-only --ephemeral -c 'model_reasoning_effort="high"' -c 'web_search="cached"' -c 'project_doc_max_bytes=0' ${trace[@]+"${trace[@]}"} -o "$out.msg" </dev/null >>"$out.log" 2>&1
```

### C1
`docs/references.md:36`
```diff
- | Built-in `Explore` runs on the session model capped at Opus | 2.1.257 | `agents/explorer.md`, `skills/agent-teams/SKILL.md` |
+ | Built-in `Explore` runs on the session model capped at Opus | 2.1.198 | `global/CLAUDE.md` |
```
`global/CLAUDE.md:38`
```diff
- instead of the built-in `Explore`, which runs on the session's model capped at Opus (2.1.257);
+ instead of the built-in `Explore`, which runs on the session's model capped at Opus (2.1.198);
```

### C2
`global/CLAUDE.md:38`
```diff
- An agent that stopped at its `maxTurns` cap is a different case: since 2.1.246 it returns its output marked partial, so continue it with `SendMessage` instead of respawning.
+ An agent that stopped at its `maxTurns` cap is a different case: read its transcript, commit its `WIP:` yourself, and respawn a fresh agent for only the remainder — it never raises the cap (feature-workflow's token-discipline rule); use `SendMessage` to continue in place only when the remainder is a handful of turns.
```

### C3
`agents/fixer.md:33`
```diff
- Hard rules (self-contained — do not assume any other instruction file reached
- your context):
+ Hard rules:
```

### C4
`agents/team-planner.md:6`
```diff
- effort: medium
- ---
+ effort: medium
+ maxTurns: 100
+ ---
```
`agents/team-plan-reviewer.md:6`
```diff
- effort: medium
- ---
+ effort: medium
+ maxTurns: 60
+ ---
```
`agents/explorer.md:6`
```diff
- effort: medium
- ---
+ effort: medium
+ maxTurns: 60
+ ---
```

### C7
`README.md:139`
```diff
- anywhere (`general-purpose`, built-in `Explore`, a bare `Agent` call), which
- would otherwise inherit whatever tier the master is running.
+ anywhere (`general-purpose`, a bare `Agent` call — built-in `Explore` is the
+ exception, always capped at Opus regardless of this floor), which would
+ otherwise inherit whatever tier the master is running.
```
`skills/agent-teams/SKILL.md:176`
````diff
- 5. CODEX     (lead launches `codex-challenge.sh` as one background Bash; `codex-triage` agent triages)
-    → ONE `~/.claude/skills/feature-workflow/scripts/codex-challenge.sh <feature-base-sha>..HEAD`
-      on the merged feature diff — full output to a file, triaged verdict shown; P0/P1 (plus
-      adjacent P2s) → fresh Sonnet fixer on the base branch → re-challenge until
-      convergence (feature-workflow stage 5 rules: a non-decreasing P0/P1 round
-      forces the structural branch, two non-decreasing rounds end the loop;
-      standalone-P2/test-gap/theoretical → one fix-now / defer-to-tech-debt
-      question). No further user gates before that.
+ ```
+ 5. CODEX     (lead launches `codex-challenge.sh` as one background Bash; `codex-triage` agent triages)
+    → ONE `~/.claude/skills/feature-workflow/scripts/codex-challenge.sh <feature-base-sha>..HEAD`
+      on the merged feature diff — full output to a file, triaged verdict shown; P0/P1 (plus
+      adjacent P2s) → fresh Sonnet fixer on the base branch → re-challenge until
+      convergence (feature-workflow stage 5 rules: a non-decreasing P0/P1 round
+      forces the structural branch, two non-decreasing rounds end the loop;
+      standalone-P2/test-gap/theoretical → one fix-now / defer-to-tech-debt
+      question). No further user gates before that.
+ ```
````

## (d) Cross-item dependencies (from the critic pass)

- **A4 ↔ B2.** A4 lowers the pin free-space floor to 2 GB, which sits below
  the owner's measured disk range (7.65–8.70 GB) — landing A4 makes `--pin`
  start firing routinely on this machine for the first time. B2 documents a
  live corruption path in that same pin/liveness code (a SIGKILLed wrapper
  orphans its foregrounded codex child; the next `--pin` invocation
  force-removes the worktree out from under it) and stays deferred with "0
  runtime exercises" as part of its own rationale. Landing A4 without also
  resolving B2 exercises a code path both items independently flag as
  unvalidated.
- **A3 + B4, same line.** A3 (doctrine: add `--trace` to the two SKILL.md
  verbatim call strings) and B4 (script: hardcode `--ephemeral` into
  `codex-challenge.sh`'s own `codex exec` line) both land on the same
  invocation once shipped. No verdict checked `--ephemeral`'s semantics
  (read from codex-rs source, undocumented) against `--trace`'s `--json`
  stdout capture path for interaction effects.
- **`docs/tech-debt.md` renumbering.** B1 removes item 1 (symlink, line
  171) and instructs "renumber the remaining list." B2's replacement text
  for item 3 (line 173) and B5's new item 15 (appended after item 14, line
  185) both cite pre-renumbering item/line numbers. Applying B1 first
  shifts item 3→2 and leaves no item-15 slot reserved before B2/B5 land;
  applying B2/B5 first leaves B1's removal targeting stale numbers. None of
  the three verdicts names this ordering dependency, even though all three
  touch the same 14-line list.

## (e) Method and cost

Phase 1 — evidence digest: 8 Sonnet readers, 881k tokens, 13.5 min wall
clock, producing `/tmp/codex-arc-evidence.json`.

Phase 2 — resolution: 20 items × (1 judge + 3 refuters + 1 resolver) + 1
critic pass = 101 agents, 5.15M tokens, 23.5 min wall clock, all on the
session model.

Primary-source checks were done by the master directly, not delegated:
`sub-agents.md` (Explore's 2.1.198 model-inheritance behavior and Explore's
CLAUDE.md-skip, cited by C1 and the O correction); `codex exec --help`
(confirming `--ephemeral` exists and characterizing `--json`'s stream
format, cited by A3 and B4); and the surviving trace log's own format (read
directly to determine it is plain text, not `--json`, cited by the
handoff's TRACE PASS correction and A3).

## Checks

Five numbers spot-checked against `/tmp/codex-arc-evidence.json`:

1. `timeline.master_context_peak_tokens` = 566085 — matches "566k" used in
   the handoff correction and section (b).
2. `timeline.boundary_waits[0].wait_min` = 21.52 — matches "21.5 min" used
   in A1 and section (b).
3. `backend.runs` durations (1670, 247, 411, 354, 237, ...) — min 237,
   max 1670 — matches "237–1670 s per step" used in section (b) and the
   handoff.
4. `stability.f3_new_p1.reported_in_f1` = false, `reported_in_f2` = false,
   `present_at_d692216` = true — matches "present at both earlier heads and
   missed twice" in section (b).
5. `cost.handoff_discrepancies[0]` states 19 agent-*.jsonl pairs exist
   under `subagents/` (not 39) — matches "19 agent transcripts" used in the
   handoff correction and section (b).
