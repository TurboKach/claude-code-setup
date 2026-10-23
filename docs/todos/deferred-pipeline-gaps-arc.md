# Deferred from the pipeline-gaps arc

**What:** nine standalone findings that came up while fixing the analyzer (session dedupe, Bash-write
exclusions, pin-reason cue) and were not fixed there: three doctrine gaps, four analyzer blind spots,
two harness-drift risks. Each can be picked up alone.

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
9. **`--bare` "will become the default for `-p` in a future release"** (`headless.md:71`). Headless
   `claude -p` runs that rely on `~/.claude` (CLAUDE.md, skills, hooks, settings) would then stop
   loading it. Check the changelog on each upgrade; when it lands, pass what those runs need
   explicitly.

**Depends:** nothing. Items 1–3 and 8 are doctrine edits and go through the line test and the review
gates; items 4, 5 and 7 are analyzer changes with tests in `test_analyze.py`.

**Effort:** items 1–3: one short doctrine edit each. Item 8: a half-session design call. Items 4, 5, 7:
about 30 min each, one Sonnet fixer. Items 6 and 9: watch items, minutes to confirm.
