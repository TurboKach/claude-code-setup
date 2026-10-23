# Deferred from the pipeline-gaps arc

**What:** twelve standalone findings that came up in the arc (the analyzer fixes: session dedupe,
Bash-write exclusions, pin-reason cue; the stage-5 rounds; the docs re-check) and were not fixed there:
four doctrine gaps, six analyzer blind spots or limits, two harness-drift risks. Each can be picked up
alone.

**Why:** the analyzer step was scoped to the false flags. Nothing below blocks it; each item needs its
own decision or its own test.

**Context:**

Doctrine (`skills/feature-workflow/SKILL.md`, `global/CLAUDE.md`):

1. **The contract gate's *ship as-is* option conflicts with the P0 rule.** Stage 5 defines P0 as "fixed
   immediately, and always blocks ship", while the structural-fix contract gate offers *defer to its
   own arc* ("a P0 blocks ship until that arc lands") or *ship as-is*. A P0 taken as-is would ship.
   The conflict predates this arc. Fix: state in the gate text, in the one place that owns it, that
   *ship as-is* is not available for a P0.
2. **A clean verdict was followed by a dirty one in 13 of 147 cases since 2026-09-15** (measured
   2026-10-23). Evidence for `docs/todos/codex-triage-must-fix-variance.md`: add it there when that
   item is picked up.
3. **One-shot sessions never load the skill.** The one-shot path in `global/CLAUDE.md` runs its
   cross-review "under stage-5 rules", which reach a one-shot session only as that pointer. The
   check-in on a long loop that stage 5 gains does not reach it. Decide whether `global/CLAUDE.md`
   (loaded every session) should carry the loop's exit rule for the one-shot path, or accept the gap.

Analyzer (`skills/analyze-arcs/scripts/analyze.py`, `timeline.py`):

4. **`NON_PRODUCT` matches `'/.claude'` anywhere in a path**, so product files under a repo's
   `.claude/worktrees/<name>/` count as non-product: master edits and Bash writes inside a worktree,
   and plan-mode reads of its files, are never flagged. Fix: exempt only the harness's own `.claude`
   directories, not worktrees.
5. **Sessions that run `codex-challenge.sh` under a project skill without loading `feature-workflow`**
   (41d1045b, fa189a8d, 20fa3ac1) are never checked for master writes, because that flag needs the
   skill load. Option: treat a `codex-challenge.sh` launch as the pipeline marker too.
6. **`timeline.py` opens transcripts as strict UTF-8; `records()` uses `errors='ignore'`.** Hypothesis,
   not triggered: a transcript line with invalid UTF-8 would make `timeline.py` raise where the
   analyzer skips it. Reproduce with a crafted file before changing either.
7. **Writes by other sessions in the same checkout stay counted.** The overlap exclusion matches only
   same-session subagent writes, and the harness's `shared` mark says a concurrent Bash call ran, not
   whose. To drop them, match the path against writes in every transcript of the same project over the
   same window.

Harness drift:

8. **`skills/feature-workflow/SKILL.md` (~37 KB) is far past the 5,000 tokens that compaction
   re-attaches per invoked skill** (`skills.md:613`). A master that auto-compacts keeps the first
   stages and loses Token discipline. Options: move the rules that must survive into the first 5,000
   tokens or into `global/CLAUDE.md`, or shorten the skill.
   The stage-5 round-5 check-in is part of this item. Its sentence starts about 17 KB into the ~37 KB
   file (bytes/4 gives about 4.4k tokens against the 5,000 kept; an estimate, not a tokenizer count),
   close to the cut, and "Truncation keeps the start of the file, so put the most important
   instructions near the top of `SKILL.md`" (`context-window.md`). A compacted master that lost it
   would run the loop with no instruction to ask at round 5. Options: also state the check-in in
   `global/CLAUDE.md` (loaded every session; the same decision as item 3), or move the loop rules up.
9. **`--bare` "will become the default for `-p` in a future release"** (`headless.md:71`). Headless
   `claude -p` runs that rely on `~/.claude` (CLAUDE.md, skills, hooks, settings) would then stop
   loading it. Check the changelog on each upgrade; when it lands, pass what those runs need
   explicitly.

Deferred at the arc's close (the stage-5 rounds and the docs re-check):

10. **Analyzer: a shell-expanded option passes `cannot_write`** (codex P2, conf 0.6). The check
    judges the command text, not what the shell makes of it. `_substitutions` replaces each `$(…)` or
    backtick with `_`, so `git diff $(printf '%s' '--output=f')` is judged as `git diff _`, and the
    inner `printf` passes on its own; the shell then runs `git diff --output=f` and writes `f`. A
    `$VAR` option passes the same way when the variable comes from the environment (`git diff $OPT`;
    `OPT=--output=f; git diff $OPT` is counted, because an assignment-only segment is not on the list).
    The class is wider than those two forms: `git diff --out$(printf put)=f`, `--output{=f,}`,
    `$'--output=f'`, `--output$IFS=f` and `sort $OPT in` all pass today. Fix options: keep a `git`, `sort`
    or `rg` segment counted when an argument holds `$`, a backtick or `{` (safe, but it stops excluding
    ``git log `git rev-parse HEAD` ``, which passes today and is a `cannot write` case in
    `test_analyze.py`), or allow expansion only where an option cannot form. First count how many of the
    records dropped today the stricter rule would count again. `_substitutions` would also need a marker
    that cannot be mistaken for a literal `_`.
11. **Analyzer: three limits that are by design.** Each is a choice the dedupe and exclusion steps
    made; change one only with a measured case.
    - A subagent Bash record that lists a path in an overlapping window drops the master's entry for it
      (`exclude_bash_writes`), though the master wrote it. The record lists what changed under the
      repository while the command ran, whoever changed it, so a subagent command that wrote nothing
      itself (a test run, `git status`) still lists a path the master's concurrent command wrote.
    - The largest copy of a session id wins with no containment check (`find_masters`). A shorter copy
      is assumed to be an older snapshot of the same transcript; two diverged copies would drop the
      shorter one's records unseen. It held on the data measured (618 identical pairs, 4 prefix pairs).
    - Subagents are read only from the winning copy's dir (`<proj>/<id>/subagents/`). A sibling copy's
      dir with more subagent transcripts is never read, so the roster and the overlap exclusion can miss
      them.
12. **Doctrine: in auto mode the push ask is model behavior only.** Auto mode runs a push to the working
    repository without a prompt (`permission-modes.md`: "Pushing to any branch of the repository you're
    working in … run without a prompt", unless the push falls under the classifier's blocked list), so
    "Pushes to remote are user-approved, always" (`global/CLAUDE.md`, hard gates) holds only while the
    model asks. The page names the lever: "add `permissions.ask` rules". A `Bash(git push *)` ask rule
    makes every such push prompt, auto mode included, and is lighter than the push hook in
    `docs/todos/verified-head-record.md`. It is also weaker: a rule matches the command text as
    written, so `git -C . push`, `git -c … push` and `git 'push'` are not stopped (`permissions.md`,
    "What a Bash rule doesn't match"), and it cannot compare the pushed HEAD with the verified one.
    Choose the rule, the hook or both when that arc is picked up.

**Depends:** nothing. Items 1–3, 8 and 12 are doctrine edits and go through the line test and the
review gates (item 12 also changes a settings file, and belongs with `docs/todos/verified-head-record.md`);
items 4, 5, 7 and 10 are analyzer changes with tests in `test_analyze.py`.

**Effort:** items 1–3: one short doctrine edit each. Item 8: a half-session design call. Items 4, 5, 7:
about 30 min each, one Sonnet fixer. Item 10: the same, plus the count of records the stricter rule
would count again. Items 6 and 9: watch items, minutes to confirm. Item 11: a design record, no work
until a case shows up. Item 12: one settings line if the rule alone is enough; otherwise the
verified-head arc.
