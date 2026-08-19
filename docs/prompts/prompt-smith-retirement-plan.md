# Plan: retire `team-prompt-smith`; the lead writes spawn prompts inline

## Context

The kit's agent-teams pipeline has a dedicated stage (step 2, PROMPTS) where a
`team-prompt-smith` subagent turns the approved plan into one self-contained
spawn prompt per execution unit. Fresh Anthropic guidance read this session says
that stage should not exist:

- The official Opus 5 prompting guide: *"Do not delegate work you can finish
  yourself in a handful of tool calls... If one subagent can complete the task,
  use one rather than several, and keep spawn counts low."* Turning an approved
  plan file into N spawn prompts is exactly that shape of work.
- Anthropic's own multi-agent research system has the lead agent write the
  subagent task descriptions itself; there is no prompt-authoring agent anywhere
  in that architecture.
- The stated benefit — keeping the lead thin — does not hold as wired.
  `agents/team-prompt-smith.md` returns the prompts *to the lead*, so the text
  enters the lead's context anyway and is then re-emitted in the spawn calls. It
  buys a second copy of the same words and a serial stage before fan-out.

The **artifact** is still mandatory: background subagents inherit no context, so
each spawn prompt must stand alone. This change deletes the role and moves its
contract into `skills/agent-teams/SKILL.md` as something the lead applies inline
while spawning.

Bundled adjacent fix: three doctrine sites hardcode the master's tier as
"Fable". The master's tier is the owner's per-session choice (Opus is a normal
pick), and the sentence's only load-bearing point is that an unpinned subagent
silently inherits *whatever* the master is running. The wording becomes
model-agnostic rather than swapping one model name for another.

## Verification notes (confirmed against HEAD before planning)

- `~/.claude/CLAUDE.md` is **byte-identical** to the in-repo
  `global/CLAUDE.md` (`diff -q` clean), as are `skills/agent-teams/SKILL.md`,
  `skills/feature-workflow/SKILL.md`, and `agents/team-prompt-smith.md` against
  their `~/.claude/` copies. So the CLAUDE.md fix is **not** an out-of-repo-only
  edit: the source of truth is `global/CLAUDE.md` (in the diff), plus a mirror
  copy to `~/.claude/CLAUDE.md` (not in the diff).
- `install.sh` enumerates agents by glob (`for f in "$SRC"/agents/*.md`) — **no
  by-name reference to remove**. But glob-copy never deletes, so the stale
  `~/.claude/agents/team-prompt-smith.md` (present, 2159 B) must be removed by
  hand. Same for `INSTALL.md` and `skills/stack-update/SKILL.md`: no mention.
- `docs/prompts/codex-gate-goal-granularity-plan.md` is a **historical record** —
  dated 2026-08-17, past tense, and its own acceptance criteria say *"Historical
  plans under `docs/prompts/` are not edited and are excluded"*. **Leave it.**
- Sites the original brief did not list, found by grep and folded in:
  `skills/agent-teams/SKILL.md:3` (frontmatter description says
  `plan → prompts → parallel execute → review → merge`), `README.md:64`
  (`Sonnet for production work (prompts, execute, merge)`), and the three
  `Fable` sites.
- `docs/decision-flow.md` references `agent-teams` **§2/§3 headings**, not
  pipeline step numbers — unaffected. The `## N.` headings are NOT renumbered by
  this change; only the numbered list inside `## The pipeline`.

## Shape

Doc-only change, 5 files, all mechanical text edits with one authored insert.
**One `step-executor` spawn does all of it** — splitting it across spawns would
cost more context re-establishment than the work itself (well under 100 tool
calls). The master writes only the plan file and the commit.

---

## Step 1 — all edits + mirror refresh · `step-executor` (`model: sonnet`)

### 1a. Delete the agent

- `git rm agents/team-prompt-smith.md`
- `rm ~/.claude/agents/team-prompt-smith.md` (the installer's glob-copy never
  deletes; nothing else reclaims it)
- No `install.sh` / `INSTALL.md` change — the installer enumerates `agents/*.md`
  by glob.

### 1b. `skills/agent-teams/SKILL.md` — remove the role

1. **Frontmatter line 3**: `Covers the lead's pipeline (plan → prompts → parallel
   execute → review → merge)` → `Covers the lead's pipeline (plan → parallel
   execute → review → merge)`.
2. **Pipeline block (inside the fence, lines 148–175)**: delete both lines of
   step 2:
   ```
   2. PROMPTS   (subagent: team-prompt-smith, sonnet)
      → turns the approved plan into one self-contained spawn prompt per unit
   ```
   Renumber: `3. EXECUTE` → `2.`, `4. REVIEW` → `3.`, `5. MERGE` → `4.`, and
   **line 202** `6. CODEX` → `5. CODEX`. Do **not** renumber the `## 1.` /
   `## 2.` / `## 3.` section headings — `docs/decision-flow.md:58-59` cites those
   as §2/§3.
3. **Cross-references to the renumbered steps**:
   - line 178: `step 3 is the only fan-out` → `step 2 is the only fan-out`
   - line 191: `step 3's agents are teammates instead` → `step 2's agents are
     teammates instead`
   - lines 188 and 196 say `step 1` — unchanged and still correct.
4. **Role table, line 230**: delete the row
   `| team-prompt-smith | subagent | Sonnet | medium | structured prompt writing |`.
5. **Fan-out recipe, lines 254–255**: `Give each the prompt-smith's
   self-contained spawn prompt (the cross-unit contract is baked in, so they
   don't message each other).` → `Give each a self-contained spawn prompt per the
   contract above (the cross-unit contract is baked in, so they don't message
   each other).`
6. **Teammate recipe, line 301**: `Give each the prompt-smith's spawn prompt.` →
   `Give each its self-contained spawn prompt.`

### 1c. `skills/agent-teams/SKILL.md` — add the spawn prompt contract

**Placement:** a new `##` section inserted **between the end of
`## Models + effort per role` (after line 240) and `## Spawn recipes`
(line 242)**. It sits immediately above the recipes that now point to it ("per
the contract above") and directly below the model table it references — no
forward references.

Insert verbatim:

```markdown
## Spawn prompt contract (the lead writes these inline)

Each executor is a background subagent with **no inherited context** — it never
sees this conversation, the plan file's surrounding discussion, or its siblings.
So each spawn prompt must stand alone. Write it yourself as you spawn: it's a
handful of tool calls' worth of text per unit, and routing it through a separate
prompt-writing agent only puts the same words through another context on the way
back to you.

State the unit's **goal and its boundaries**, then stop — don't enumerate
procedure. Sonnet 5 takes an explicit scope statement literally, which is what
earns it its place; step-by-step instructions written for prior models reduce
quality on current ones.

Every prompt carries:
- **Scope + ownership** — what the unit is for, the files it owns, and the files
  it must not touch. Ownership is disjoint across units by construction; a hub
  file belongs to exactly one unit.
- **The full cross-unit contract** it must honor (API shapes, types, names),
  baked in. Background subagents can't message each other, so anything it needs
  from a sibling has to be in the text.
- **Acceptance criteria and how to verify them** — the tests or commands that
  prove the unit is done. State them once; no "re-verify" or "double-check"
  rituals.
- **The worktree/branch** it works in, and the retirement budget verbatim: "if
  you exceed ~200k context or ~250 turns — commit WIP, write a handoff file to
  the scratchpad, and stop".
- **The model pin** from the table above (`sonnet`, or `opus` only where the
  approved plan marks that unit Opus with a reason).

One concern per prompt, sized so the executor finishes in roughly ≤100 tool
calls — a unit bigger than that was planned too large; split it. A fixer prompt
carries exactly one finding set, never several. Nothing in a prompt goes beyond
the approved plan.
```

### 1d. `README.md`

1. **Delete line 30** (the `agents/team-prompt-smith.md` table row).
2. **Line 50** — delete the `PROMPTS (prompt-smith)` line from the ASCII pipeline
   and fold its surviving annotation into EXECUTE (line 51):
   ```
   EXECUTE (N executor subagents, parallel, in worktrees)  ← contracts baked into each spawn prompt; no cross-talk
   ```
   **On alignment:** the diagram is a loose sketch, not an aligned box —
   measured character columns today are `─┐` at col 97 (PLAN), `│` at col 59
   (PROMPTS), `│` at col 59 (REVIEW), `─┘` at col 67 (CODEX). The three column
   positions already disagree. Deleting line 50 removes one of the two `│` and
   leaves the chain `┐ … │ … ┘` intact and no more ragged than before. **Do not
   re-align the remaining characters** — that's an unrequested edit to lines this
   change doesn't touch.
3. **Line 64**: `**Sonnet for production work** (prompts, execute, merge)` →
   `**Sonnet for production work** (execute, merge)`.
4. **`## Notes`** — add one dated bullet at the top of the list (matching the
   existing pattern from commits `9465de0`/`b58f549`):
   `- **2026-08-19 prompt-smith retired:** the lead writes each executor's spawn
   prompt inline while spawning (contract in `skills/agent-teams/SKILL.md`
   § "Spawn prompt contract"); a separate prompt-writing agent returned the
   prompts to the lead anyway, so it only added a serial stage and a second copy
   of the same text.`
   Leave the older dated Notes entries untouched — they're a historical record.

### 1e. The "Fable" phrase — model-agnostic in all three doctrine sites

The master's tier varies by session (the owner picks it); the sentence's only
point is that an unpinned subagent silently inherits *whatever* the master is
running. Drop the model name rather than swapping it.

- `global/CLAUDE.md:39`: `an unpinned subagent inherits the master's tier (Fable)
  silently` → `an unpinned subagent silently inherits whatever tier the master is
  running`
- `skills/agent-teams/SKILL.md:236`: `Pin `model:` on every spawn (unpinned =
  inherits the lead's Fable tier; ...` → `Pin `model:` on every spawn (unpinned =
  inherits whatever tier the lead is running; ...`
- `skills/feature-workflow/SKILL.md:17`: `never leave it unset (the subagent would
  inherit the master's Fable tier) and never `fable`` → `never leave it unset (the
  subagent inherits whatever tier the master is running) and never `fable``

Keep every `` `fable` never in a subagent `` clause — that's a separate, still-valid
rule. Do **not** touch `README.md:172` or
`docs/prompts/codex-gate-goal-granularity-plan.md:21` — both are dated historical
records.

### 1f. Mirror to `~/.claude` (outside the repo — will not appear in the diff)

Plain copies, not `./install.sh`: the installer would also re-run the
`settings.json` merge and rewrite backups, which this change has no business
doing (and it would skip `CLAUDE.md` entirely, since it never clobbers an
existing one).

```
cp global/CLAUDE.md                     ~/.claude/CLAUDE.md
cp skills/agent-teams/SKILL.md          ~/.claude/skills/agent-teams/SKILL.md
cp skills/feature-workflow/SKILL.md     ~/.claude/skills/feature-workflow/SKILL.md
rm -f ~/.claude/agents/team-prompt-smith.md
```

### Acceptance criteria for Step 1 (all checkable by reading files)

- `grep -rn "prompt-smith" . --exclude-dir=.git` → exactly one hit:
  `docs/prompts/codex-gate-goal-granularity-plan.md:142` (historical). *(If the
  approved plan file has already been copied into `docs/prompts/`, its own hits
  are also expected and fine.)*
- `grep -rn "PROMPTS" README.md skills agents global` → zero hits.
- `ls ~/.claude/agents/team-prompt-smith.md` → "No such file"; `git status` shows
  `agents/team-prompt-smith.md` deleted.
- `grep -rn "Fable" global skills agents README.md` → zero hits.
  ``grep -rn '`fable`' global skills`` → the three unchanged "never `fable`"
  clauses still present.
- In `skills/agent-teams/SKILL.md`: the fenced pipeline reads
  `1. PLAN / 2. EXECUTE / 3. REVIEW / 4. MERGE`, line ~202 reads `5. CODEX`, the
  prose says "step 2 is the only fan-out" and "step 2's agents are teammates",
  and the `## 1.`/`## 2.`/`## 3.` headings are unchanged. The role table has 7
  rows (planner, plan-reviewer, executor, reviewer, merger, explorer, plus the
  lead row). The new `## Spawn prompt contract` section sits between
  `## Models + effort per role` and `## Spawn recipes`, and both spawn recipes
  reference it instead of a prompt-smith.
- In `README.md`: the "What's inside" table has no prompt-smith row; the fenced
  diagram has 5 lines (PLAN/EXECUTE/REVIEW/MERGE/CODEX) with unchanged column
  positions on the lines that weren't edited; line ~63 reads "(execute, merge)";
  one new dated Notes bullet.
- `diff -q` clean for each pair: `global/CLAUDE.md` ↔ `~/.claude/CLAUDE.md`,
  `skills/agent-teams/SKILL.md` ↔ `~/.claude/skills/agent-teams/SKILL.md`,
  `skills/feature-workflow/SKILL.md` ↔
  `~/.claude/skills/feature-workflow/SKILL.md`.
- `git diff --stat` shows exactly: `README.md`, `global/CLAUDE.md`,
  `skills/agent-teams/SKILL.md`, `skills/feature-workflow/SKILL.md`, and the
  deletion of `agents/team-prompt-smith.md`. Nothing else.

**No Opus needed** — mechanical text edits against a fully specified target; the
one authored block is supplied verbatim above.

---

## Step 2 — verification + commit · master (read-only checks; no product-file writes)

The master re-runs the greps and `diff -q` pairs from Step 1's acceptance
criteria against the executor's result, reads the changed hunks of
`skills/agent-teams/SKILL.md` and `README.md` in full (numbering consistency and
the diagram are the only things a grep can't judge), then commits on `master`.
**No push.**

---

## Step 3 — ship gate · `/codex challenge` (master, or one `general-purpose` runner, `model: sonnet`)

`Skill(codex, "challenge <feature-base-sha>..HEAD")` once on the whole diff,
triaged verdict shown, feature-workflow stage-5 rules (P1/P2 → fresh Sonnet fixer
→ re-challenge, round N of 3). Doctrine-only diff, so expect a thin verdict — but
per the owner's standing note the gate is not skipped unilaterally. Push only on
the owner's explicit approval.

---

## Edge cases

- **The installed mirror is invisible to review.** `~/.claude/` changes don't
  appear in `git diff` or in the codex challenge. The `diff -q` pairs in the
  acceptance criteria are the only proof they landed.
- **`docs/prompts/` is excluded by that directory's own convention** — a future
  grep for `prompt-smith` will keep hitting the 2026-08-17 plan record. Expected,
  not a miss.
- **Renumber vs. heading numbers.** The `## 2.` / `## 3.` section headings share
  the digits with the pipeline steps; `docs/decision-flow.md` cites the headings.
  Only the fenced list renumbers.

**Stated assumption (not gated):** the mirror refresh uses plain `cp`/`rm` rather
than `./install.sh`, so the `settings.json` merge and backup churn don't ride
along on a doc-only change.

**Files touched:** `agents/team-prompt-smith.md` (deleted),
`skills/agent-teams/SKILL.md`, `README.md`, `global/CLAUDE.md`,
`skills/feature-workflow/SKILL.md`, plus the mirrors under `~/.claude/`.

---

## Plan-reviewer findings (0 blocking · 6 advisory) and resolutions

The reviewer confirmed against HEAD: every cited line number and quoted
before-text matches; the renumber sweep is complete (the only other `step N`
hits are SKILL.md:188,196 `step 1`, correctly left); `docs/decision-flow.md`'s
mermaid flow has no PROMPTS node, so leaving the `## N.` headings un-renumbered
creates no contradiction; `PROMPTS` has exactly 2 hits, both edited; capital
`Fable` has exactly 3 hits, all three in §1e (`README.md:172` is lowercase
`` `fable` ``, so the criterion holds); all four `diff -q` mirror pairs are
byte-identical and no other installed file mirrors a touched repo file;
`install.sh:62` is a glob.

All six advisories are folded into the executor's brief — none change the
approach:

1. **§1b.5 (SKILL 254–255)** — the plan's after-text is reflowed and drops the
   `> ` blockquote prefixes and the trailing "Notify me when each completes."
   Pasted literally it breaks the recipe blockquote. The executor re-wraps with
   `> ` and keeps that last sentence.
2. **§1d.3 (README 64)** — the quoted string spans lines 63–64 (`**Sonnet for`
   ends 63), so a literal Edit on the one-line quote fails. The executor matches
   the real two-line span.
3. **§1d.2 (diagram)** — measured columns are `│` at 60, `┐` at 98, `┘` at 68
   (plan said 59/97/67). Conclusion unchanged: the sketch is already misaligned
   and deleting one line leaves it no worse. Still do not re-align.
4. **§1c (new section)** — the plan's block drops the retired agent's
   named-teammate carve-out and reads "can't message each other" flatly, which
   contradicts `SKILL.md:302` on the teammate path. The executor restores the
   carve-out using the retired agent's own wording: only flag a sibling to
   coordinate with if the lead is using the named-teammate path.
5. **Step 1 criteria** — `git diff --stat` won't show the `git rm`'d file once
   staged; verification uses `git status --short` / `git diff HEAD --stat`.
6. **§1d.4 (Notes bullet)** — existing Notes entries are single unwrapped lines;
   the new bullet is written on one line to match.

**Reviewer observation, not created by this change:** `6. CODEX` at
`SKILL.md:202` sits outside the fence that closes at 175. Renumbering it to `5.`
preserves that pre-existing oddity.

## Stated assumptions (not gated)

- **The orphaned CODEX block stays where it is.** It's a pre-existing formatting
  break in a line this change happens to touch; per the surgical-changes
  principle it gets mentioned, not fixed, in the same diff.
- **The README diagram's "contracts baked into each prompt" annotation is folded
  into the EXECUTE line** rather than dropped — it's the reason the contract
  survives the retirement.
- **The dated Notes bullet is added**, following the convention every doctrine
  change since 2026-08-18 has used.
- **The mirror refresh uses plain `cp`/`rm`, not `./install.sh`**, so the
  `settings.json` merge and backup churn don't ride along on a doc-only change.
