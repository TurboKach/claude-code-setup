# Subagent no-background arc — handoff (2026-09-04)

Cold-start entry. Plan: `subagent-no-background-plan.md` (same dir). Range `51d3cd9..6e90f42`
plus this close-out commit. Gate clean at `6e90f42` after three codex rounds
(`docs/reviews/subagent-no-background/`). Nine standalone findings deferred to
`docs/tech-debt.md` § "Deferred from the subagent no-background arc". Owner waived the
master-writes-no-code gate for this arc (small diff); the codex gate still ran.

## What shipped

- `hooks/subagent-no-background.sh` + `hooks/tests/` (16 cases): PreToolUse on Bash. Rule A
  denies `run_in_background` inside any subagent (`agent_id` present). Rule B denies an executed
  `until`/`while` loop whose head names a `.output.done` marker, anywhere — quoted text stripped
  first, keyword at a command boundary. Fail-open on anything else.
- `settings.example.json`: `BASH_DEFAULT_TIMEOUT_MS=900000` (ceiling follows), the hook under
  `PreToolUse`/`Bash`. `install.sh`: hook merge generalised (`register_hook(event, matcher, path,
  timeout)`), idempotent, other groups untouched.
- Doctrine: `feature-workflow` no longer claims a subagent's backgrounded call ends at its final
  response (true only for foreground subagents; fork mode makes every spawn background); close-out
  sweeps `pgrep -f 'output\.done'` and `TaskStop`s every listed agent. Agent timeout bullet
  rewritten as facts. `docs/references.md` rows, README note, INSTALL.md clauses.

## Verified

- Hook tests green; installer merge test twice into a seeded `CLAUDE_HOME` (existing PreToolUse and
  matcher-less Stop groups byte-identical, Bash group once, seeded env value kept).
- Live, fresh `claude -p` sessions: a Sonnet subagent's `run_in_background` Bash was denied with
  the hook's reason; the same session's master background call ran; a subagent's 130 s foreground
  `python3` sleep with no `timeout` completed at 2 min 10 s without auto-backgrounding.
- Observed, not in the docs: the hook took effect in the already-running master session right
  after `./install.sh`, no restart or `/hooks` review — the stale installed copy denied a commit
  message mid-arc, which is what surfaced round 1's P1 live. Treat as an observation on 2.1.260.

## What to watch in the next product arc

- Executors/fixers now see the deny reason instead of orphaning a poll; check a transcript for how
  they wait after an auto-backgrounded build (expected: foreground `until ! pgrep -f "[x]codebuild"`
  under a `timeout`, then read the task `.output` file).
- Auto-backgrounding should be rare now: `xcodebuild test` runs 5–9 min under a 15-min default.
  Count "moved to the background" tool results in `subagents/*.jsonl` — before: ~40 across 8
  sessions.
- The two queued `/feedback` drafts about this incident (one in the clipsy session, one here)
  overstate the harness's role; both say the subagent's background command should have been
  stopped, which the docs say is intended for background subagents. Edit before sending.
