# codex challenge — range 83c9b33cbfcc0871e5558a652ef6df55c72e1223..5acce42c48aab212e20b2404ce17614dbefde9c2 — checkout /Users/turbokach/Dev/claude-code-setup — exit 0 — 1000s
global/CLAUDE.md:49 — One-shot edits need not be committed, so `<pre-change-sha>..HEAD` remains empty and the mandatory review exits 64, deadlocking normal uncommitted fixes.

global/CLAUDE.md:27 — The gate hard-codes `~/.claude`, while `install.sh` supports `CLAUDE_HOME`; custom installations copy the script elsewhere and every gate invocation fails.

skills/feature-workflow/SKILL.md:18 — Removing `--pin` without requiring a clean worktree lets uncommitted fixes hide defects present at the reviewed head; repo-backed output also creates `.log`/`.msg` inside the live checkout during review.

skills/feature-workflow/SKILL.md:22 — A large squashed commit cannot be split into commit subranges, so two timeouts leave the mandatory ship gate with no executable fallback.

skills/feature-workflow/scripts/codex-challenge.sh:52 — Exact-range coverage exists only as a natural-language request; normal runs neither supply the diff nor verify trace evidence, so Codex can inspect the wrong range or skip it and still return success.

skills/feature-workflow/scripts/codex-challenge.sh:60 — `-s read-only` neither confines reads to the checkout nor disables configured MCP tools; prompt-injected repository content can expose host secrets or trigger external connector side effects.

skills/feature-workflow/scripts/codex-challenge.sh:68 — An empty final-message file makes `cat` succeed and produces an exit-0 header with no verdict, allowing a failed review to appear successful.

skills/feature-workflow/scripts/codex-challenge.sh:68 — The final redirect follows a repository-planted symlink at `--out`, allowing a normal review invocation to overwrite arbitrary files writable by the user.

skills/feature-workflow/scripts/codex-challenge.sh:41 — Cleanup tracks the wrapper PID rather than the Codex child; killing the wrapper can leave a live child whose checkout the next run force-removes, while PID reuse preserves stale directories and can block worktree creation.

skills/feature-workflow/scripts/codex-challenge.sh:47 — `git worktree add` is outside the timeout and runs smudge/filter processes, so a hung Git-LFS or custom filter stalls forever without producing a verdict.

skills/feature-workflow/scripts/codex-challenge.sh:45 — The fixed 10-GiB check ignores checkout size and Git-LFS storage on the repository volume, so a large pin can pass preflight and exhaust either disk mid-checkout.

skills/feature-workflow/scripts/codex-challenge.sh:60 — Omitting `--ephemeral` persists every per-step run and retry in Codex session storage, causing unbounded disk growth across long pipelines.

skills/feature-workflow/scripts/codex-challenge.sh:65 — Every permanent error, including missing Codex, invalid configuration, and expired authentication, is retried twice with five-minute sleeps before the gate parks.

INSTALL.md:16 — Readiness checks only executable presence and therefore reports incompatible or unauthenticated Codex installations as ready, deferring failure until the mandatory ship gate.

INSTALL.md:16 — The wizard rejects Linux systems that provide GNU `timeout` but not `gtimeout`, even though the script explicitly supports `timeout` as its fallback.