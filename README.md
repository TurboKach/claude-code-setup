# Claude Code setup — parallel multi-agent starter kit

My [Claude Code](https://code.claude.com) setup: an opinionated `CLAUDE.md`, plus
a working **parallel multi-agent** system — a skill that orchestrates fan-out work
and the role agents it spawns. Clone, run the installer, and you have a
plan → execute → review → merge pipeline that fans out across **background
subagents** (the default — in-process, isolated worktrees only where they write
in parallel, no extra setup).

> The default path uses ordinary background subagents and (optionally) Workflows —
> no experimental flags, no extra setup.
>
> Fan-out uses significantly more tokens than a single session — use it for
> parallel research, review, and feature work, not routine tasks.

## What's inside

| Path | What it is |
|------|-----------|
| `global/CLAUDE.md` | Lean always-on layer: principles (think-before-coding, simplicity, surgical changes), the hard gates (push approval, codex gate, AFK-not-approval), and a pointer to the feature-workflow skill. Lives under `global/` so working sessions in this repo don't load it twice alongside `~/.claude/CLAUDE.md` |
| `global/rules/` | Path-scoped user rules, installed to `~/.claude/rules/` — load only when a matching file is touched, so they don't add to every session's always-on context |
| `skills/feature-workflow/SKILL.md` | The six-stage single-master feature pipeline, the parallel-multi-agent mechanism picker, and the token-discipline rules. Loads on demand when a pipeline or fan-out starts (extracted from CLAUDE.md per 5-gen progressive disclosure). |
| `skills/agent-teams/SKILL.md` | The orchestration playbook — when to fan out, how to pick the mechanism (subagents / Workflows), the pipeline, models, worktree/merge flow, the plan-approval gate. Loads on demand. |
| `agents/team-planner.md` | Explores and **returns** the plan as text (headless, read-only); the lead — in native plan mode — writes it to the plan file *(Fable 5.1 medium — experiment since 2026-09-02)* |
| `agents/explorer.md` | Read-only codebase search on Sonnet at effort medium — the pinned stand-in for built-in `Explore` *(Sonnet)* |
| `agents/team-plan-reviewer.md` | Validates the plan against the code before the lead presents it via `ExitPlanMode` for **your** approval *(Fable 5.1 medium — experiment since 2026-09-02)* |
| `agents/team-executor.md` | Implements one unit of a **parallel** fan-out as a background subagent — carries `isolation: worktree` in its frontmatter, since concurrent writers merge later *(Sonnet high; Opus only when the plan justifies it)* |
| `agents/step-executor.md` | Implements one **sequential** step on the session's own branch — no worktree, nothing to merge; the feature-workflow counterpart to `team-executor` *(Sonnet high; Opus only when the plan justifies it)* |
| `agents/fixer.md` | Fixes one review round's finding set (P0/P1 plus adjacent P2s) on the session's own branch, test-first red-then-green — a bounded task at a known `file:line`, so it runs cheaper than a plan step *(Sonnet medium; Opus only for a same-mechanism structural fix)* |
| `agents/codex-triage.md` | Reads one round's `codex-challenge.sh` output file(s) — all slices of a split round — verifies each finding against `git show <head>:<path>` and `git diff <base> <head>`, and returns the single ≤2k deduped verdict; the run itself is a background Bash in the master, the only context the harness re-wakes on completion *(Sonnet medium)* |
| `agents/spec-reviewer.md` | At the final gate, checks the feature's whole diff against the approved plan file — missing requirements, scope creep, wrong-logic-vs-spec; gaps only, in parallel with the whole-range codex challenge *(Sonnet medium)* |
| `agents/team-reviewer.md` | Adversarially verifies each diff before merge — read-only, no worktree *(Opus)* |
| `agents/team-merger.md` | Merges approved worktrees into the base branch, removes each worktree + branch after landing, reports done *(Sonnet)* |
| `settings.example.json` | The model pin (`ANTHROPIC_DEFAULT_OPUS_MODEL` — see [Model pinning](#model-pinning)), `worktree.baseRef: "head"` so executor worktrees branch from your in-progress branch rather than the remote default, `CLAUDE_CODE_ENABLE_TODO_TOOLS` (the task-list feature), `CLAUDE_CODE_SUBAGENT_MODEL` (the Sonnet floor for unpinned spawns — see [Model pinning](#model-pinning)), and the `SessionStart` update-check hook |
| `hooks/stack-update-check.sh` | Runs once per session start: at most once a day, checks whether this repo's `master` differs from the SHA you installed, and prints one line if so — silent otherwise (no update, no network, disabled, cached) |
| `skills/stack-update/SKILL.md` | Applies a pending update: clones the repo, summarizes what changed, asks for your approval before writing anything, re-runs `install.sh`, and re-stamps |
| `skills/feature-workflow/scripts/codex-challenge.sh` | Range-scoped adversarial `codex exec` on exactly `<base>..<head>`; optional self-removing pinned worktree; `gtimeout 2400`, 3 attempts / 5 min; writes the verdict file and prints its path |
| `install.sh` | Copies everything into `~/.claude` (with backups) and merges the settings keys above |
| `docs/decision-flow.md` | Mermaid map of the gates: who executes each kind of work, in which checkout, reviewed by whom — a reading aid; the authoritative text stays in the files it points at |
| `docs/references.md` | The sources the doctrine is built on — harness docs (version-stamped, authoritative), the model-behavior guides it's tuned against, and cookbook patterns; plus the last Claude Code version the doctrine was validated against |
| `docs/tech-debt.md` | Known gaps deliberately left unfixed, each with the site, the reasoning, and the review that surfaced it |
| `docs/prompts/` | The approved plan files behind each doctrine change, mirrored for history — the "why" behind the Notes below |

## How it works

Only the **lead** (your main session) spawns. Every step delegates to a subagent
except the lead's own plan-mode transcription and gates; the parallel **execution**
step fans out into one background subagent per independent unit, each in its own
worktree (because they write concurrently and merge later):

```
PLAN (lead in plan mode: planner drafts → plan-reviewer validates → ExitPlanMode) → you approve ─┐   ← the only approval gate
EXECUTE (N executor subagents, parallel, in worktrees)  ← contracts baked into each spawn prompt; no cross-talk
REVIEW (reviewer, read-only — no worktree)                 │
MERGE (merger) → removes each worktree+branch, reports completion
CODEX (lead) → one codex-challenge.sh <feature-base>..HEAD ─┘   ← triaged verdict, P0/P1 fixed
```

Pick the fan-out mechanism by need: **background subagents** by default;
**Workflows** for large/deterministic/resumable fan-outs. Worktree isolation
is added **only** where agents write in parallel and merge — read-only
fan-out (review, research) skips it.

Models follow a simple rule: **Fable 5.1 at medium** for the one-pass planning
roles (plan, plan review), **Opus for diff review**, **Sonnet for production
work** (execute, merge), with Opus available per-spawn where the plan
justifies it. Executor spawns are sized to one concern each (roughly ≤100
tool calls; the plan splits anything bigger).

## Install

### Recommended — let Claude Code install it (interactive wizard)

Open Claude Code and paste this:

> Set up the Claude Code parallel-multi-agent kit from https://github.com/TurboKach/claude-code-setup — clone it to a temp directory, read INSTALL.md, and run it as an interactive install wizard. Detect what I already have and only install what's missing.

Claude checks your machine and walks you through it step by step: it offers to
install only what you're missing (gstack), enables the required settings, and
copies the skill + agents with backups. Exactly what it does:
[`INSTALL.md`](INSTALL.md).

### Alternative — non-interactive script

```bash
git clone https://github.com/TurboKach/claude-code-setup.git
cd claude-code-setup
./install.sh    # copies skill+agents+CLAUDE.md and merges settings; installs nothing else
```

The default path (background subagents + Workflows) needs **no manual steps** —
once the files are copied, ask for parallel work and it fans out.

## Staying up to date

A `SessionStart` hook checks once a day whether this repo's `master` differs from the
SHA you installed — one cached `curl` to the GitHub API, silent unless there's news:

```
claude-code-setup: update available (installed abc1234 → remote def5678) — run /stack-update
```

`/stack-update` applies it: clones the repo, summarizes what changed, and **asks for your
approval before writing anything**. Two state stamps track the update, not one — `installed`
(the SHA skills/agents/settings are at) and `claude-md-installed` (the SHA whose `CLAUDE.md`
you actually accepted). They diverge because `install.sh` never overwrites an existing
`~/.claude/CLAUDE.md`, and `/stack-update` lets you decline that merge — so a single stamp
would call the kit up to date while your `CLAUDE.md` sat stale and the change went missing.

Opt out with `touch ~/.claude/.claude-code-setup/disabled`.

## Model pinning

The agent files pin models by **alias** (`model: fable` / `model: opus` /
`model: sonnet`), so they keep their semantic tiers — "heavy role" vs "cheap
role" — while one env var decides which concrete version each alias means.
Claude Code resolves the aliases through `ANTHROPIC_DEFAULT_OPUS_MODEL` /
`ANTHROPIC_DEFAULT_SONNET_MODEL` / `ANTHROPIC_DEFAULT_HAIKU_MODEL` /
`ANTHROPIC_DEFAULT_FABLE_MODEL` everywhere: the main session, agent
frontmatter, and per-spawn model choices. The `fable` alias moved from Fable 5
to Fable 5.1 in 2.1.257 and is deliberately left unpinned.

`settings.example.json` pins Opus to `claude-opus-5` so a new Opus release
never silently changes (or re-prices) your agents:

```json
"env": { "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-5" }
```

Change the value to move to a different version, delete the key to follow the
latest Opus again, or add the `_SONNET_`/`_HAIKU_` variants to pin those tiers
too.

It also sets `CLAUDE_CODE_SUBAGENT_MODEL` to `sonnet` as a **floor**, not an
override: since 2.1.251 an agent definition's `model:` and an explicit per-spawn
model both take precedence over it. The Opus roles keep their frontmatter pins
(`team-planner`, `team-plan-reviewer`, `team-reviewer`), and a per-spawn
`model: "opus"` still wins — the floor only catches a spawn with no pin
anywhere (`general-purpose`, built-in `Explore`, a bare `Agent` call), which
would otherwise inherit whatever tier the master is running. Settings `env` changes are read at session start — restart Claude Code
after editing. (Verified: with the pin set, `--model opus` and `model: opus`
agents run the pinned version; the var works both from the shell and from the
settings `env` block.)

## Requirements

**Default path (background subagents + Workflows):**
- Claude Code **v2.1.186 or newer** (`claude --version`) — use the latest.
  v2.1.186 is the practical floor: from there, background subagents surface
  permission prompts in your session (earlier versions silently auto-denied
  them). Workflows shipped in v2.1.154; no install required.
- That's it — no flags, no extra tools.

**Recommended for the full workflow:**
- **gstack** *(optional)* — the workflow references `/office-hours`, `/ship`,
  `/context-save`, `/browse`, etc. Install:
  ```bash
  git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack \
    && cd ~/.claude/skills/gstack && ./setup
  ```
  Without gstack the team still works — use plain git/PR commands for the ship
  steps. The codex gate needs `codex` (codex-cli) and `gtimeout`
  (`brew install coreutils`), not gstack.

## Notes

- **2026-09-02 `codex-challenge.sh` replaces the gstack codex path (from the 2026-09-01 backend and clipsy session transcripts and 111 verdict files):** the `Skill(codex, "challenge <range>")` path never ran — gstack would have treated the range as a focus area and diffed `origin/<default>`, so each master loaded the 102 KB skill once and then hand-assembled every launch (14 in the backend arc, three parser variants, 13 without the `[codex ran]` audit lines); every recorded run did diff the explicit range anyway. Replaced by the kit-owned `codex-challenge.sh`: one deterministic call, range in the prompt, `--trace` for the audit trail, pin/timeout/retry encoded.
- **2026-09-02 Fable 5.1 read + planning-role migration:** Claude Code 2.1.252→2.1.258 changelog read; Fable 5.1 became the `fable` default (cache reads $0.25/MTok); master and the two planning roles moved to Fable 5.1 at medium as a one-arc experiment (before: Opus 5 high); `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` recorded as never-set; subagents auto-continue after mid-stream cutoffs since 2.1.257; built-in `Explore` now capped at Opus.
- **2026-08-25 per-step review + convergence rule (from the clipsy_ios carousel arcs 2–3 + backend forensics):** the end-of-arc codex loop was the dominant cost — arc-2 ran 12 rounds (~1.0M output tokens, as much as the 11-step build) after round 1 met 14 P1s at once; arc-3's loop was 60% of active time with P1s *regressing* 8→8→10 under instance patches until an Opus structural fixer broke the plateau, and the owner had to invent a stop rule live at hour 6. Changes: a per-step codex challenge (backgrounded, pinned worktree, overlapping the next executor) so steps stop building on unreviewed bugs, while the whole-range challenge stays the only gate; a P0/P1/P2 taxonomy (P0 = crash/data-loss/security/core-flow regression, always blocks ship); the fix loop keyed to convergence, not a round count — a non-decreasing P0/P1 round forces the structural branch, two non-decreasing rounds end the loop; adjacent P2s ride with their P1's fixer; one `codex-triage` spawn per round ingests all slices (the arc-2 master hand-deduped slices twice on its way to ~460k context); a `spec-reviewer` pass checks the final range against the plan (per Anthropic's adversarial-review-against-plan practice); test-first red-then-green (the revert dance becomes the fallback — it cost 2 extra xcodebuild runs per fix); worktrees removed at triage-return with a `df` preflight (an ENOSPC burned a round launch); backgrounded long runs get `gtimeout 3600` + a 3-attempt/5-min retry wrapper (a 529 outage cost 3h17m; an unbounded `xcodebuild test` "ran" 6.4h); wake-after-gap drains the notification queue first (an 8.5h-idle session answered "Not sleeping" and re-ran a suite whose finished result sat unconsumed). No char caps anywhere, per eac1896.
- **2026-08-23 codex run moved into the master (from the clipsy_ios text-as-elements arc, 19 h 53 m):** the `codex-runner` agent lost 3.4 h over two rounds. Its foreground `codex exec` was a compound pipeline with `timeout: 600000`, so the harness *stopped* it at the cap instead of backgrounding it (docs: only simple commands auto-background); its rule then polled a marker file for a run that was already dead, and `ps | grep codex` matched the owner's own interactive `codex` TUI, reading "still alive" for 41 and 103 minutes. A real challenge on the range took 14–22 min, above both the Bash cap and gstack's absolute `gtimeout 600`. Every round that finished ran bare `codex exec` detached. Now the master launches that pipeline as one `run_in_background` Bash on a pinned worktree (the master is the one context re-woken on completion) and spawns `codex-triage` on the notification; the runner agent, its hooks and hook tests are retired. Same session: executors pinned at xhigh ran 514k–627k peak context past a prose budget none obeyed → `effort: high` (Sonnet 5 guide) and `maxTurns` in frontmatter; the plan's full-suite-per-step rule cost 282 `xcodebuild` runs / 207 min → targeted tests per step, full suite once after the last step.
- **2026-08-22 runner wake-up (from the clipsy_ios Media-Photos session):** a Sonnet runner backgrounded `codex exec`, armed a Monitor, and ended its turn; the completion event was enqueued and never dequeued for nine minutes until the owner typed `?`. Docs confirm `TaskOutput` is gone from subagents (and deprecated everywhere), and a timed-out foreground Bash is moved to the background rather than killed. The rule already in `feature-workflow` ("runner runs codex in the foreground") never reached the session because the one-shot path doesn't load the skill — so it now lives in a `codex-runner` agent whose frontmatter hooks enforce it (`agents/codex-runner.md`, `hooks/codex-runner-hooks.sh`).
- **2026-08-21 wall-clock doctrine (from the clipsy_ios playtest-arc forensics):** a 6h20m single-request session measured 29% of wall clock with zero agents in flight, and roughly a quarter of it spent re-fixing its own fixes. Three changes: a gate starts the work that doesn't depend on its answer but still ends the turn and waits when there is none (`global/CLAUDE.md`); a fixer reads the readers before cutting a write path, and treats a briefed fix approach as a hypothesis to trace rather than an instruction (`agents/fixer.md`); a challenge too large for one prompt splits into gapless slices that still count as the single stage-5 gate, and overlapping a review with a writer needs a real `git worktree` pin, because challenge mode has codex compute the diff in the live tree (`skills/feature-workflow/SKILL.md`).
- **2026-08-19 prompt-smith retired:** the lead writes each executor's spawn prompt inline while spawning (contract in `skills/agent-teams/SKILL.md` § "Spawn prompt contract"); a separate prompt-writing agent returned the prompts to the lead anyway, so it only added a serial stage and a second copy of the same text.
- **2026-08-18 two paths + task list:** one-shot (≤3 files, no design/UI choice, reversible — no plan ceremony, but `/codex challenge` still runs on the diff) vs pipeline, with the call stated in one line; every spawn pins `model:` (never `fable`); codebase search uses the kit's `explorer` agent (sonnet, medium) instead of built-in `Explore`, which inherits the session's model and effort; at plan approval the master mirrors the plan into Claude's native task list (`CLAUDE_CODE_ENABLE_TODO_TOOLS=1`, merged by the installer) — one task per step + the fixed tail — and marks tasks done as steps land (no Stop hook, deliberately).
- **2026-08-18 pipeline diet (from the clipsy_ios S1–S4 forensics):** `/codex challenge` runs once per feature (not per step) with P1/P2 priorities and a fix-now / defer-to-tech-debt question for the rest; `/goal` is dropped — plan approval starts the tail; executors and fixers are Sonnet xhigh, Opus only when the plan justifies it. gstack's codex skill needs a local patch on macOS (`mktemp "$TMP_ROOT/codex-err-XXXXXX"` — drop the `.txt` suffix, BSD mktemp rejects it); re-apply after `/gstack-upgrade`.
- **Native plan mode replaced gstack `/autoplan` on 2026-08-18 (experiment).** Stage 2–3 is now `EnterPlanMode` → `team-planner` returns the draft → lead transcribes → `team-plan-reviewer` validates → one AskUserQuestion for taste items → `ExitPlanMode`. To restore `/autoplan`: `git revert autoplan-off && ./install.sh` (tag `autoplan-off` marks the switch commit).
- The installer's default (`--claude-md` unset, i.e. "auto") mode **never
  overwrites an existing `~/.claude/CLAUDE.md`** — a `--claude-md=replace` run
  backs it up and overwrites it. It backs up any skill/agent files it
  replaces (under `~/.claude/.backup-<timestamp>`). It merges only the
  `settings.example.json` keys, with a `settings.json.bak` safety copy — and
  never overwrites a model pin you already set.
- `settings.example.json` is intentionally minimal — your real `settings.json`
  is personal; never commit it (it tends to hold emails, tokens, and private
  paths).

## Credits

Workflow and parallel multi-agent system by [@TurboKach](https://github.com/TurboKach).
gstack by [Garry Tan](https://github.com/garrytan/gstack). Built for
[Claude Code](https://code.claude.com). MIT licensed.
