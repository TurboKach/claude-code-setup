### `agents/codex-triage.md` — must-fix calls vary between two runs of the same round

**What.** Re-running a recorded triage round on the same model can flip which findings are
must-fix (P0/P1 real or regression). Measure that variance cleanly, then decide whether the
triage rules need tighter P1/P2 boundaries.

**Why.** Must-fix decides what the fixer touches this round and what goes to the backlog. If a
third of the must-fix calls flip between runs, whether a bug gets fixed is partly chance.

**Context.** Side finding of the 2026-10-08 Haiku 5.5 replay (30 recorded rounds, 25 with a
P0/P1, re-run headless with `--agent codex-triage --effort medium`). The original Sonnet 5.5
verdict and a same-prompt Sonnet 5.5 re-run disagreed on 31 must-fix rows: each run's must-fix
lines differed from the other's by 32–50% (42 vs 31 must-fix lines). These rows were not settled
against the code. Confounds, so treat the number as a hypothesis: the re-run ran as the main
session agent (not a subagent), with a read-only preamble and a narrowed Bash allowlist, and
read the repo as it is today rather than when the round ran.

**Depends.** Nothing.

**Effort.** One session. Re-run ~20 recorded rounds 3× each in subagent mode from one
headless `claude -p` session (codex output files under the arcs' scratchpads still exist for
recent rounds), and settle each flipping row against `git show <head>:<path>`.
