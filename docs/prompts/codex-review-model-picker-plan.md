# Plan: user-chosen codex review model for the cross-review gate

## Context

`skills/feature-workflow/scripts/codex-challenge.sh` runs the adversarial `codex exec` that gates every
push. Until commit `11b0941` it passed no model flag, so each run silently inherited the top-level `model`
from the user's `~/.codex/config.toml` — i.e. whatever their interactive Codex TUI was set to. On
2026-09-05, ~2 min after a codex-cli 0.153.4 install, that config flipped `gpt-5.6-sol` → `gpt-6-astra`
and the gate followed it with nobody noticing; no verdict file records a model, so the crossover is
invisible in all ~100 existing verdicts. `11b0941` hardcoded `gpt-6-astra` / `medium` at line 99, which
fixed the drift but left the choice unavailable to anyone whose codex subscription can't afford astra.

This arc makes the model a user choice: the two values move to `settings.json`'s `env` block (which
survives reinstall — `install.sh` does `rm -rf "$DEST/skills/<skill>"` on every run, so anything pinned in
the script is wiped), the install wizard asks which of three models to use, and the retry loop stops
burning 10 minutes of `sleep 300` on a model the API rejects — which becomes the likely *first-run*
experience once users pick their own.

Owner's locked decisions, not re-opened by any step: storage is the `settings.json` `env` block
(`CODEX_REVIEW_MODEL`, `CODEX_REVIEW_EFFORT`); the ladder is exactly three models, all at `medium` effort —
`gpt-6-astra` (recommended, default), `gpt-5.6-sol`, `gpt-5.6-luna`. `gpt-5.3-codex-spark` is not offered
(128k context halves the window for a gate that reads a whole feature range and traces out of the diff;
also `supported_in_api: false`). Because effort is `medium` for all three, **no effort question is asked** —
`CODEX_REVIEW_EFFORT` ships as `"medium"` purely so the key is present and hand-editable.

Verified against the tree at `a8b8609` (clean; `11b0941` is its parent). Line numbers confirmed by the
plan-reviewer: hardcode at `codex-challenge.sh:99`, retry loop 95-105, header 107; `install.sh` settings
merge 229-335, python heredoc 237 passing exactly 8 argv today (read at 239-243, so a ninth as
`sys.argv[9]` is correct), `env` loop head 251 with `setdefault` at 256, `--opus-pin` arg branch 47,
settings-keys header sentence ending at 13; `README.md:34` and `:39`; `INSTALL.md:16` readiness line.

Corrected from the draft: `INSTALL.md` Step 1 items start at **33** (not 35 — item 1 `gstack` at 33,
CLAUDE.md 34-38, Opus 39-47), and the flag-translation bullets are **63-73** (not 60-73; 56-62 is prose
intro). `install.sh` has **zero** `read` calls, as assumed.

### Two findings that shaped this plan

**(a) `install.sh` is not where a human answers questions.** `INSTALL.md` is an agent-facing wizard
(line 1: "You are Claude Code, running this install for the user"): it asks via `AskUserQuestion` and
translates answers into `install.sh` flags (`--opus-pin=`, `--claude-md=`). The Opus-version question —
structurally identical to this one (ask only if the key isn't already in `env`, never clobber) — already
lives there. So the existing pattern for "user picks a value that lands in `settings.json.env`" is
*wizard question + install.sh flag*, not a `read` in the installer. That keeps `install.sh` at zero `read`
calls, so there is no TTY gate and no scripted-install risk at all. See OPEN DECISION 1.

**(b) Measured, load-bearing.** Under `set -o pipefail` (this script's mode), `cmd | grep -q pattern`
**silently reports no-match on a large matching input** — `grep -q` exits at the first match, `tail`/`cat`
dies of SIGPIPE (141), pipefail propagates 141, the `if` goes false. Verified on a 200k-line input:
`grep -q` → `q-MISSED`, `grep -E … >/dev/null` → `noq-match`. The bail-out grep must therefore be
`grep -E … >/dev/null`, never `grep -q`.

---

## Step 1 — `codex-challenge.sh`: env-var pin + permanent-error bail

**Executor: `step-executor` (Sonnet).** Single file, ~4 hunks.

**1a. Resolve the values.** Insert immediately before line 95 (`start=$(date +%s); rc=1`):

```bash
# Model + effort come from the environment — settings.json's `env` block, installed by install.sh —
# not from this file: install.sh does `rm -rf "$DEST/skills/<skill>"` on every run, so anything pinned
# here is wiped by the next reinstall. Leaving them unset inherited ~/.codex/config.toml's interactive
# TUI model, which silently flipped gpt-5.6-sol -> gpt-6-astra on 2026-09-05 after a codex-cli upgrade.
# `${VAR:-default}` is safe under `set -u`; a bare `$VAR` is not.
model=${CODEX_REVIEW_MODEL:-gpt-6-astra}
effort=${CODEX_REVIEW_EFFORT:-medium}
```

**1b. Line 99 — exact replacement.** Substitute the two single-quoted `-c` arguments

```
-c 'model="gpt-6-astra"' -c 'model_reasoning_effort="medium"'
```

with (double quotes so the shell expands, backslash-escaped inner quotes so the TOML string survives):

```
-c "model=\"$model\"" -c "model_reasoning_effort=\"$effort\""
```

Nothing else on line 99 changes.

**1c. Bail out of the retry loop on a permanent API error.** Add a byte mark just before the codex
invocation (inside the loop, after `echo "=== attempt $attempt ==="`):

```bash
  mark=$(wc -c <"$out.log" 2>/dev/null || echo 0)
```

and replace line 104 (`echo "attempt $attempt exit $rc" >>"$out.log"; [ "$attempt" -lt 3 ] && sleep 300`)
with:

```bash
  echo "attempt $attempt exit $rc" >>"$out.log"
  # A model/effort the API rejects is an immediate HTTP 400, not an outage: retrying it costs 10 min of
  # silence and still returns no review. codex exec's exit code does not distinguish 400 from a network
  # failure, so match the error line codex itself prints. Scoped to this attempt's chunk of the log and
  # anchored on codex's `ERROR:` prefix, because the reviewer's own findings text can contain these words
  # verbatim (this repo reviews this very script). `grep -E ... >/dev/null`, never `grep -q`: under
  # `set -o pipefail` a -q match kills the writer with SIGPIPE and the pipeline reports 141 == no match.
  if tail -c +$((mark + 1)) "$out.log" | grep -E '^ERROR:.*("status": ?400|invalid_request_error|invalid_enum_value|not supported when using Codex)' >/dev/null; then
    echo "permanent API error on attempt $attempt (bad CODEX_REVIEW_MODEL/EFFORT?) — not retrying; see $out.log" | tee -a "$out.log" >&2
    break
  fi
  [ "$attempt" -lt 3 ] && sleep 300
```

Pattern justification against the two real strings measured this session: the bogus-model error is
`ERROR: {"type":"error","status":400,…,"message":"The 'gpt-9-nonexistent' model is not supported when using Codex with a ChatGPT account."}`
→ matched by `"status": ?400` and by `not supported when using Codex`; the bogus-effort error is a 400
carrying `[invalid_enum_value]` → matched by `invalid_enum_value` (and by `"status": ?400` if the JSON
envelope is present there too). Two independent alternatives cover each case, so one wording change
upstream does not silently disable the bail.

**Honest caveat the executor must resolve, not assume:** **the entire pattern is unverified, not just the
anchor** (plan-reviewer). No log from this session's bogus runs survives on disk (checked — only the
round-1 verdict/`.log`/`.msg` for a *successful* run exist under `docs/reviews/codex-model-pin/`), so both
the `^ERROR:` anchor and every branch of the alternation rest on error text quoted from a terminal, not
from a file. Two distinct failure modes the executor must handle in Step 3, reporting whichever it hits:
- `ERROR:` is not at start-of-line → drop `^`, keep the alternation.
- **The pattern misses entirely.** Particularly likely for the effort case: `-c model_reasoning_effort="bogustier"`
  may be rejected by codex's own TOML/enum deserializer *locally*, before any request, in which case no
  `"status": ?400` or `invalid_enum_value` text appears anywhere and the bail never fires. If so, report the
  actual local-rejection text and what exit code it produced — do not widen the pattern to something that
  could match a reviewer's prose just to make the test pass. The loop already skips the sleep after the final attempt
(`[ "$attempt" -lt 3 ]`), so no change is needed for that case. Verified that this AND-list does not trip
`set -e` when attempt=3.

**1d. Record the pin in the verdict header** (line 107) so a run is auditable after the fact —
`--ephemeral` writes no session file and codex's `--json` stream echoes neither model nor effort, so our
side is the only place this can be recorded, and an unnoticed model change is exactly the 2026-09-05
failure. Append to the existing header line:

```
# codex challenge — range $base..$head — checkout $dir — model $model/$effort — exit $rc — …s
```

(See OPEN DECISION 2 if the owner prefers no header change.)

**Acceptance:** `bash -n` clean; `shellcheck` no new findings (run it if installed, report if not);
`grep -c '^model=' codex-challenge.sh` == 1 — i.e. exactly one *assignment* of the default.
**Do not use `grep -c 'gpt-6-astra'` (plan-reviewer, blocking):** 1a's comment mentions `gpt-6-astra` in
its own text, so that count is 2, and an executor driving it to 1 would delete the explanatory comment to
satisfy the criterion. A dry echo of the built argv (e.g.
temporarily `echo` in place of `"$codex_bin"`, reverted) shows `model="gpt-5.6-luna"` when
`CODEX_REVIEW_MODEL=gpt-5.6-luna` is exported and `model="gpt-6-astra"` when it is unset. Real-API proof
is Step 3.

---

## Step 2 — Settings key, installer flag, wizard question, docs

**Executor: `step-executor` (Sonnet).** Four files, no overlap with Step 1.

**2a. `settings.example.json`** — add to the `env` block (after `BASH_DEFAULT_TIMEOUT_MS`; JSON has no
comments, the explanation goes in README):

```json
"CODEX_REVIEW_MODEL": "gpt-6-astra",
"CODEX_REVIEW_EFFORT": "medium"
```

This is all the storage work that is strictly required: `install.sh`'s python merge already loops
`for k, v in ex["env"].items(): env.setdefault(k, v)` (line ~252), so both keys get installed on a fresh
install, are never clobbered on reinstall, and survive `rm -rf $DEST/skills/*`. **Verified: the existing
merge expresses this cleanly — no second mechanism, no `jq`, no hand-rolled merge.** `merged_desc`
("env + worktree.baseRef") stays accurate, unchanged.

**2b. `install.sh` — one flag, mirroring `--opus-pin` exactly.** No `read`, no TTY gate, installer stays
non-interactive:

- `usage()` gains `--codex-model=MODEL_ID    Setdefault CODEX_REVIEW_MODEL to MODEL_ID instead of the repo default (never clobbers an existing value).`
- arg loop (line **47**): `--codex-model=*) CODEX_MODEL="${arg#--codex-model=}"; CODEX_MODEL_SET=1 ;;`.
  **Two** variables are initialized beside `OPUS_PIN`/`OPUS_PIN_SET` at 40-47: `CODEX_MODEL=""` and
  `CODEX_MODEL_SET=0`. The empty-value rejection must be gated on the `_SET` flag, exactly as `--opus-pin`
  does at 72-75: `if [ "$CODEX_MODEL_SET" = 1 ] && [ -z "$CODEX_MODEL" ]; then` → exit 1.
  **This is load-bearing (plan-reviewer, blocking):** a single-variable shape whose post-loop check is a
  bare `[ -z "$CODEX_MODEL" ]` fires on *every flagless install* — the kit's own default path and Step 3c's
  `./install.sh </dev/null` — so the "reject empty the same way `--opus-pin` does" instruction is only
  implementable with the second variable.
- pass `"$CODEX_MODEL"` as a ninth argv to the python heredoc (line 237), read it as
  `codex_model = sys.argv[9]`, and inside the existing `for k, v in ex["env"].items()` loop add one branch
  beside the Opus one:

```python
    elif k == "CODEX_REVIEW_MODEL" and codex_model:
        v = codex_model
```

`env.setdefault` then does the never-clobber part for free. No validation of the model string (the API is
the validator; Step 1 now fails fast and loud on a bad one). The header comment block (lines 7-14) gains
one clause naming the two new keys.

**2c. `INSTALL.md`** — two minimal edits:

- Step 1, new item 4 (after the Opus question), only asked when `CODEX_REVIEW_MODEL` is absent from the
  user's settings `env`: *which model the codex cross-review gate uses*, with the three options and the
  one-line reason each — `gpt-6-astra` *(recommended, repo default; most capable, 272k context)* /
  `gpt-5.6-sol` *(reliable everyday workhorse, 272k)* / `gpt-5.6-luna` *(fast and affordable, 272k)*. One
  sentence: all three run at `medium` effort, and the gate reads a whole feature range, which is why the
  128k `codex-spark` tier is not offered.
- Step 2 flag translation: **every answer passes an explicit flag** — `gpt-6-astra` →
  `--codex-model=gpt-6-astra`, `gpt-5.6-sol` → `--codex-model=gpt-5.6-sol`, `gpt-5.6-luna` →
  `--codex-model=gpt-5.6-luna`. There is deliberately **no** "recommended → pass no flag" branch (owner's
  decision, 2026-09-10): an answer that passes no flag would silently depend on the repo default still
  being astra, so a future default change would redirect someone who explicitly chose astra, and the
  install command line would carry no record of the choice. Only a *skipped* question (key already present
  in the user's `env`) passes no flag. Mechanically free: the `elif k == "CODEX_REVIEW_MODEL" and
  codex_model` branch accepts any value and `env.setdefault` still never clobbers.

**2d. `README.md`** — two surgical row edits, no new section:

- line 34 (`settings.example.json` row): add `, CODEX_REVIEW_MODEL + CODEX_REVIEW_EFFORT (which codex
  model and reasoning effort the cross-review gate uses — set here, not in the script, because install.sh
  replaces the skill directory on every run)`.
- line 39 (`codex-challenge.sh` row): change `gtimeout 2400, 3 attempts / 5 min` to `gtimeout 2400,
  3 attempts / 5 min (a 400 from a rejected model stops retrying immediately)` and add `model + effort
  from CODEX_REVIEW_MODEL / CODEX_REVIEW_EFFORT (default gpt-6-astra / medium), recorded in the verdict
  header`. Include the plain-terminal corollary from 3e in one clause: the keys arrive via the Claude Code
  session's environment, so a run started from a bare terminal falls back to the default.

No `Notes` entry (that section records measured arc retrospectives; this is a config change). Nothing to
remove from `docs/tech-debt.md` — checked, the round-1 finding in
`docs/reviews/codex-model-pin/codex-whole-round1.md` was never indexed as deferred debt; Step 2 report
should note that this arc resolves that finding ("the script offers no override").

**Acceptance:** `bash -n install.sh`;
`python3 -c 'import json;json.load(open("settings.example.json"))'`; `./install.sh --help` lists the new
flag; `./install.sh --codex-model=` exits non-zero with a clear message;
`./install.sh --opus-pin=x --codex-model=y --claude-md=leave` parses. Functional install proof is Step 3.

---

## Step 3 — Verification against the real client (codex API + a real install)

**Executor: `step-executor` (Sonnet).** Runs after Steps 1-2; no product edits except the fallback
allowed in 1c.

**3a. Positive path — a real gate run on this arc's own range.** With the two keys *absent* from the
environment, run `skills/feature-workflow/scripts/codex-challenge.sh a8b8609..HEAD --out
<scratchpad>/codex-verify.md` (background Bash, ~2-4 min). Expect exit 0, a verdict file, and a header
line reading `model gpt-6-astra/medium`. Then repeat once with
`CODEX_REVIEW_EFFORT=low CODEX_REVIEW_MODEL=gpt-5.6-luna` exported and expect exit 0 with the header
showing that pair — proof a *non-default* value is accepted end to end, not just echoed.

**3b. Falsification — prove the value reaches the request** (this is the only proof that the `-c` is not
silently dropped). `CODEX_REVIEW_MODEL=gpt-9-nonexistent codex-challenge.sh <small range>`: expect a
non-zero exit, a `permanent API error on attempt 1 … — not retrying` line, and the 400 text in `….log`.
Repeat with `CODEX_REVIEW_EFFORT=bogustier` for the second error shape.

**The criterion for "the sleeps were skipped" is the log, not the clock** (plan-reviewer): the
`not retrying` line is present **and** `=== attempt 2 ===` is absent. Wall clock (`time`) is supporting
evidence only — the script spends up to 30 s before the first attempt on `codex mcp list`
(`codex-challenge.sh:83`, `-k 10 30`) plus git/worktree work, so a slow-but-correct run can drift toward a
60 s threshold, while a run that genuinely slept is unmistakable at 300 s+.

While the log is in hand, **confirm the bail pattern matches the actual failure text** and apply whichever
1c fallback applies (anchor wrong, or pattern misses entirely) — reporting what the log really said.

**3c. Non-interactive install still works, and a reinstall does not clobber.** Into a throwaway home:
`CLAUDE_HOME=$(mktemp -d) ./install.sh </dev/null` — expect exit 0 and `CODEX_REVIEW_MODEL: "gpt-6-astra"`
in that tree's `settings.json`. Then `CLAUDE_HOME=<same> ./install.sh --codex-model=gpt-5.6-sol
</dev/null` and confirm the value is **still** `gpt-6-astra` (setdefault never clobbers), while a *fresh*
`CLAUDE_HOME` with `--codex-model=gpt-5.6-sol` yields `gpt-5.6-sol`. `</dev/null` on every invocation is
the proof that no step blocks on stdin. Also confirm the installed
`$CLAUDE_HOME/skills/feature-workflow/scripts/codex-challenge.sh` contains no literal model pin other than
the default, i.e. the chosen value lives only in `settings.json`.

**3d. Full suite.** `bash hooks/tests/subagent-no-background.test.sh` (the repo's only test suite —
untouched by this arc, run as the regression gate). Report executed/passed/failed counts.

**3e. The actual delivery path, cited not re-tested** (plan-reviewer advisory). 3a exports the vars in a
shell and 3c only greps the installed `settings.json` text — neither proves `settings.json`'s `env` block
reaches a script the Claude Code Bash tool launches. That path is already verified in this session's own
Bash environment, where `ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-5`, `CLAUDE_CODE_SUBAGENT_MODEL=sonnet`
and `BASH_DEFAULT_TIMEOUT_MS=900000` are all present from the kit's `env` block. Cite that evidence in the
report (`env | grep` from inside the executor is sufficient) rather than leaving the claim unexercised.
**Corollary for the README edit in 2d:** a gate run launched from a plain terminal *outside* a Claude Code
session does not see the settings value and silently falls back to `gpt-6-astra`.

**Acceptance:** every expectation above met, with the measured wall-clock times and the two header lines
quoted verbatim in the report. Any miss is reported, not worked around.

---

## Edge cases covered by the above

- Empty-string `CODEX_REVIEW_MODEL=""` in the environment → `${VAR:-default}` falls back to `gpt-6-astra`
  (`:-` fires on empty as well as unset). Intentional, no extra guard.
- A user's own `CODEX_REVIEW_MODEL` already in `settings.json` → `env.setdefault` leaves it, and the
  wizard skips the question.
- A model name containing shell metacharacters → it is passed as one argv word inside `"…"`, so no
  word-splitting or globbing. **Do not claim it "fails fast via 3b's path" (plan-reviewer): that is wrong
  for a name containing a double quote.** Measured: `CODEX_REVIEW_MODEL='a b"c'` yields the single argv word
  `model="a b"c"` — malformed TOML, which codex rejects at *config-parse* time rather than with a 400, so
  the bail grep misses and the run burns both `sleep 300`s. Unreachable except by a user typing a quote
  into the value; no guard is added, the claim is simply dropped.
- The bail grep firing on the reviewer's own prose: prevented by the per-attempt byte window plus the line
  anchor; Step 3a's real runs (whose findings text discusses this very grep) double as the false-positive
  test — they must exit 0.
- `python3` absent → install.sh already prints "add the keys from settings.example.json by hand"; that
  message now covers the two new keys with no change.

## Close-out (master, not a step)

Mirror this approved plan file into `docs/prompts/codex-review-model-picker-plan.md` and commit it with the
feature. `README.md:44` describes `docs/prompts/` as holding the approved plan behind each change, and ten
prior arcs' plan files are there — the draft assigned this to nobody (plan-reviewer advisory).

## No Opus step

Every step is mechanical, single-file-scoped, and verified by running the real thing. No cross-file
algorithmic invariant, concurrency, or layout math — all three steps are Sonnet `step-executor`.

---

## DECISIONS RESOLVED (owner, 2026-09-10)

**1. Where the user answers the model question → install wizard + `--codex-model=` flag.** Step 2b/2c as
written, reusing the exact `--opus-pin` pattern: `install.sh` stays at zero `read` calls, no TTY gate,
scripted installs unaffected. The TTY-gated `read` variant and the "ship the keys only, no question"
variant were both considered and rejected.

**1a. Amendment — every answer passes an explicit flag**, including the recommended one (see Step 2c). No
"recommended → pass no flag" branch.

**2. Record `model $model/$effort` in the verdict header → yes.** Step 1d stands. It is the only place the
pin is observable after a run (`--ephemeral` writes no session file and the `--json` stream echoes neither
value), and an unnoticed model change is the failure that started this arc.

Note: `team-plan-reviewer` read the plan before amendment 1a landed. Its item-4 check (INSTALL.md
flag-translation format) covers the section this amendment edits by one bullet; the master re-checks that
one point against the reviewer's findings rather than assuming.
