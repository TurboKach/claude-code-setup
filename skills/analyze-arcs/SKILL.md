---
name: analyze-arcs
description: Measure the Claude Code pipeline sessions since a date — master transcripts, their subagents/*.jsonl, and the codex-challenge logs — and report the numbers plus the mechanical doctrine violations. Invoke on "analyze the sessions", "how did the last arcs go", "evaluate the pipeline", "/analyze-arcs <since-date>", or before any kit change that claims to fix a pipeline problem.
---

# Analyze arcs

Two scripts, both read-only. Times in the report are UTC; transcripts are under
`~/.claude/projects/<project>/<session>.jsonl` with subagent transcripts beside them in
`<session>/subagents/`. The master transcript is a partial record: owner↔subagent messages
and everything a subagent did live only in the subagent files, so never judge an agent from
the master's view of it.

## Procedure

1. **Version diff first** (global rule: optimize starts with a version diff). `claude --version`
   against the stamp in the kit's `docs/references.md`; if they differ, read the changelog
   between them before blaming the doctrine for a harness change.
2. **Run the measurement** into the session scratchpad:
   ```
   python3 ~/.claude/skills/analyze-arcs/scripts/analyze.py --since YYYY-MM-DD --out <scratchpad>/arcs/report.md
   ```
   Per session: span, models, peak context, subagent roster (type, pin, turns, minutes, KB,
   model actually seen), every `codex-challenge.sh` launch with its range, `--out`, run
   minutes and verdict size, every gate with how long it waited, pushes, killed background
   tasks. Then the **flags** — mechanical checks only:
   - unpinned `Agent` spawn, or a pin off the doctrine tier (planner/plan-reviewer `fable`,
     team-reviewer `opus`, executors/fixers/triage `sonnet`) with whether the prompt states a reason
   - named spawn (delivery rerouted to the mailbox)
   - `codex-challenge.sh` run in the foreground; `--out` outside the session scratchpad or `docs/reviews/`
   - master `Edit`/`Write` on a product file after `feature-workflow` loaded — or a Bash command that
     changed one, read from the harness's own changed-file record (`bashEditDiff.changedFiles` on the
     tool result; 2.1.269+, on by default in auto mode, never parsed from the command text). The
     auto-mode prompt steers edits through Bash since at least 2.1.266, so the Edit/Write check alone
     is blind; sessions from before 2.1.269 say "Bash writes: not recorded". Plan files, `docs/prompts/`,
     `docs/reviews/`, `docs/todos/`, handoff docs, the TODO/tech-debt index, `/tmp/` and build artifacts
     are not product files
   - `ExitPlanMode` or `AskUserQuestion` that waited more than an hour, or was never answered
   - `feature-workflow` loaded with no one-shot/pipeline call line before it; product edits with no call line at all
   - subagents that died on an API error before doing work; subagents that hit their turn cap
3. **Read the timelines at the flagged times.** A flag is a place to look, not a verdict:
   ```
   python3 ~/.claude/skills/analyze-arcs/scripts/timeline.py <session>.jsonl <scratchpad>/arcs/<name>.txt
   ```
   works on a master or a subagent file; then `awk`/`grep` the time window. Read the subagent
   transcript for any spawn whose roster row looks off (long, huge, capped, wrong model).
4. **The judgment findings the script cannot make** — check them by hand every time:
   a verification step that proved only the negative path (curl, unit suites) before a deploy;
   a review escape (what codex rounds missed and why); whether a long gate wait was a legitimate
   taste gate or a delegated approval the master should not have blocked on; whether an Opus pin's
   stated reason holds; whether a relaunch or respawn was warranted by the agent's own timestamps.
5. **Report with the numbers**, held vs failed, ranked by cost. Every doctrine change proposed
   from it goes as before/after text through "would removing this line cause mistakes?", and the
   measured evidence goes into a memory note so the next run has a baseline.

## Limits

`--min-kb 150` skips small sessions unless they spawned subagents; lower it to see one-shots.
Codex run minutes come from the log file's birth and modification times, so a run whose
`--out` was reused or deleted reads `?`. Spawn rows are matched to subagent transcripts by
order of start time; a spawn that died before writing a transcript shifts the rows after it —
compare the `model seen` column with the pin when that happens.
