# analyze-arcs: plan-mode read flag — known tokenizer/window edges

**What:** the "master read product file in plan mode" flag (`bash_read_paths`,
`plan_span_end`, `product_file` in `skills/analyze-arcs/scripts/analyze.py`)
misreads these Bash shapes. All are edges of a measurement heuristic; none affect
doctrine.

- `_segments`: an unmatched quote inside a heredoc body (`don't`) flips the quote
  state and swallows later reads in the same command. [P2 conf:0.55]
- read-command match uses `toks[0]` only: `LC_ALL=C cat f`, `command cat f` are
  invisible. [P2 conf:0.55]
- `cat<file` (no space) is one shlex token and is dropped. [P2 conf:0.5]
- empty operands are dropped before the pattern strip: `grep '' file`,
  `sed '' file` lose the real path. [P2 conf:0.5]
- `#` comments are not stripped; comment words become paths, an embedded `;`
  fabricates a command. [P2 conf:0.45]
- `grep -f patterns.txt` / `rg --file`: the pattern file is a real read but is
  consumed as an option value and discarded. [P2 conf:0.5]
- rg `-r`/`--replace` is missing from the option table, so its value is read as
  an operand. [P2 conf:0.45]
- bare-`rg` fallback (`.`) also fires for `rg --files`, `rg --version`, piped
  stdin. [P2 conf:0.4]
- approval string inside an `is_error` ExitPlanMode result would still count as
  approval. [theoretical conf:0.3]

**Why:** found by the codex whole-range challenge of the master-authors-plan arc
(round 3, `docs/reviews/master-authors-plan/round3.md`, local); deferred because
the flag is a per-arc measurement and these shapes are rare in real transcripts
(the flag count over 90 sessions was unchanged by the last three fixes).

**Context:** `skills/analyze-arcs/scripts/test_analyze.py` has the harness — add
a red case per bullet before fixing. Documented gaps that are *not* on this list
(heredoc bodies, `python3 -` scripts, `$var` paths, `cd dir && cat f`, Shift+Tab
entry) stay as documented.

**Depends:** nothing. **Effort:** ~1 h, one Sonnet fixer.
