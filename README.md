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
| `skills/feature-workflow/SKILL.md` | The six-stage single-master feature pipeline, the parallel-multi-agent mechanism picker, and the token-discipline rules. Loads on demand when a pipeline or fan-out starts. |
| `skills/agent-teams/SKILL.md` | The orchestration playbook — when to fan out, how to pick the mechanism (subagents / Workflows), the pipeline, models, worktree/merge flow, the plan-approval gate. Loads on demand. |
| `agents/explorer.md` | Read-only codebase search on Sonnet at effort medium — the pinned stand-in for built-in `Explore` *(Sonnet)* |
| `agents/team-plan-reviewer.md` | Validates the plan against the code before the lead presents it via `ExitPlanMode` for **your** approval *(the session's model and effort)* |
| `agents/team-executor.md` | **Parallel fan-out only.** Implements one unit of the fan-out as a background subagent — carries `isolation: worktree` in its frontmatter, since concurrent writers merge later *(Opus medium)* |
| `agents/step-executor.md` | Implements one **sequential** step on the session's own branch — no worktree, nothing to merge; the feature-workflow counterpart to `team-executor` *(Opus medium)* |
| `agents/fixer.md` | Fixes one review round's finding set (P0/P1 plus adjacent P2s) on the session's own branch, test-first red-then-green — a bounded task at a known `file:line`, so it runs cheaper than a plan step *(Opus medium)* |
| `agents/codex-triage.md` | Reads one round's `codex-challenge.sh` output file(s) — all slices of a split round — verifies each finding against `git show <head>:<path>` and `git diff <base> <head>`, and returns the single ≤2k deduped verdict; the run itself is a background Bash in the master, the only context the harness re-wakes on completion *(Sonnet medium)* |
| `agents/spec-reviewer.md` | At the final gate, checks the feature's whole diff against the approved plan file — missing requirements, scope creep, wrong-logic-vs-spec; gaps only, in parallel with the whole-range codex challenge *(Sonnet medium)* |
| `agents/team-reviewer.md` | **Parallel fan-out only.** Adversarially verifies each unit's diff before merge — read-only, no worktree *(Opus)* |
| `agents/team-merger.md` | **Parallel fan-out only.** Merges the worktrees the lead names into the base branch, removes each worktree + branch after landing, reports done *(Sonnet)* |
| `settings.example.json` | `model: "opus"` + `modelSettings.claude-opus-5-5.effortLevel: "xhigh"` (the recommended master — the session you open — the latest Opus at xhigh; the install wizard and `/stack-update` ask: recommended / keep current / don't ask again / another model, and `install.sh --master=recommended` applies it), `worktree.baseRef: "head"` so executor worktrees branch from your in-progress branch rather than the remote default, `CLAUDE_CODE_ENABLE_TODO_TOOLS` (the task-list feature), `CLAUDE_CODE_SUBAGENT_MODEL` (the Sonnet floor for unpinned spawns — see [Model pinning](#model-pinning)), `BASH_DEFAULT_TIMEOUT_MS: 900000` (a build or test run with no explicit timeout is no longer auto-backgrounded at 2 minutes; this is also the ceiling), `CODEX_REVIEW_MODEL` + `CODEX_REVIEW_EFFORT` (which codex model and reasoning effort the cross-review gate uses — set here, not in the script, because install.sh replaces the skill directory on every run; reinstalling never overrides an existing value, so change it by editing `settings.json`), `bashOutputMaxChars: 30000` (a valid command result over 30k characters arrives as a file path plus a 2k preview instead of flooding the context), `bashEditDiffEnabled: true` (the transcript records which files each Bash command changed — `/analyze-arcs` reads that instead of parsing commands; on by default only in auto mode, so it is pinned for every mode; never shown to the model), the `SessionStart` update-check and session-name hooks, and the `PreToolUse` subagent-no-background hook |
| `hooks/subagent-no-background.sh` | PreToolUse on Bash: denies `run_in_background` inside any subagent (with fork mode on every spawn is a background subagent, whose background commands keep running past its final report — nobody stops them) and any `until`/`while` poll on a `.output.done` marker (the harness never writes one). Fail-open on anything it does not understand; tests in `hooks/tests/` |
| `hooks/session-name.sh` | SessionStart: names the session from a `Session name: <slug>` line in the repo's `CLAUDE.md` (or `.claude/CLAUDE.md`), so sessions in sibling repos of one project find each other in `ListAgents` and the name survives a plan's acceptance; never overwrites a name set with `--name` or `/rename`, silent when the line is absent; tests in `hooks/tests/` |
| `hooks/stack-update-check.sh` | Runs once per session start: at most once a day, checks whether this repo's `master` differs from the SHA you installed, and whether the running Claude Code differs from the version the doctrine was last validated against (`docs/references.md`, stamped by `install.sh`) — one line each if so, silent otherwise (no update, no network, disabled). A known update — with how many commits you are behind — is shown to you at every session start, from the cached poll, until you install it; tests in `hooks/tests/` |
| `skills/stack-update/SKILL.md` | Applies a pending update: clones the repo, summarizes what changed, asks for your approval before writing anything, re-runs `install.sh`, and re-stamps |
| `skills/analyze-arcs/` | `/analyze-arcs <since-date>`: scans every Claude Code session and subagent transcript since a date plus the codex-challenge logs, and writes a report with the measured numbers (subagent roster and pins, codex rounds, gates and their wait times, peak context) and the mechanical doctrine violations (unpinned spawns, wrong-tier pins, `--out` outside the scratchpad, master product edits inside a pipeline, overnight `ExitPlanMode` waits, missing path-call line); judgment findings stay with the reader |
| `skills/feature-workflow/scripts/codex-challenge.sh` | Range-scoped adversarial `codex exec` on exactly `<base>..<head>`; optional self-removing pinned worktree; `gtimeout 900`, 3 attempts / 5 min (a 400 from a rejected model stops retrying immediately); model + effort from `CODEX_REVIEW_MODEL` / `CODEX_REVIEW_EFFORT` (default `gpt-6-sol` / `medium`), recorded in the verdict header — these keys arrive via the Claude Code session's environment, so a run started from a bare terminal outside a session falls back to the default; writes the verdict file, prints its path on stdout and the elapsed wall-clock time on stderr |
| `install.sh` | Copies everything into `~/.claude` (with backups) and merges the settings keys above |
| `docs/decision-flow.md` | Mermaid map of the gates: who executes each kind of work, in which checkout, reviewed by whom — a reading aid; the authoritative text stays in the files it points at |
| `docs/references.md` | The sources the doctrine is built on — harness docs (version-stamped, authoritative), the model-behavior guides it's tuned against, and cookbook patterns; plus the last Claude Code version the doctrine was validated against |
| `docs/tech-debt.md` | Known gaps deliberately left unfixed, each with the site, the reasoning, and the review that surfaced it |

## How it works

Only the **lead** (your main session) spawns. Every step delegates to a subagent
except the lead's own plan-mode authoring and gates; the parallel **execution**
step fans out into one background subagent per independent unit, each in its own
worktree (because they write concurrently and merge later):

```
PLAN (lead in plan mode: lead authors → plan-reviewer validates → ExitPlanMode) → you approve ─┐   ← the only approval gate
EXECUTE (N executor subagents, parallel, in worktrees)  ← contracts baked into each spawn prompt; no cross-talk
REVIEW (reviewer, read-only — no worktree)                 │
MERGE (merger) → removes each worktree+branch, reports completion
CODEX (lead) → one codex-challenge.sh <feature-base>..HEAD ─┘   ← triaged verdict, P0/P1 fixed
```

Pick the fan-out mechanism by need: **background subagents** by default;
**Workflows** for large/deterministic/resumable fan-outs. Worktree isolation
is added **only** where agents write in parallel and merge — read-only
fan-out (review, research) skips it. Inside the feature pipeline, each plan
weighs whether two long, independent steps run as a pair — at most two
executors at once, each in its own worktree, landed by the merger; every other
step runs one at a time.

### Recommended models

Opus plans and writes code, and Sonnet handles lookups and mechanical work. The
planner runs deeper than the executors: same model, higher effort.

| Role | Model | Effort | Set by |
|------|-------|--------|--------|
| Master — the session you open; plans, coordinates, gates | Opus 5.5 | xhigh | `settings.json` `model` + `modelSettings` — the wizard and `/stack-update` ask (recommended / keep / don't ask again / other); `install.sh --master=recommended` applies it |
| `team-plan-reviewer` | Opus 5.5 (the master's) | xhigh (the master's) | `model: inherit`, no `effort:` key — follows the session |
| `step-executor`; `team-executor` *(parallel fan-out only)* | Opus 5.5 | medium | agent frontmatter |
| `fixer` | Opus 5.5 | medium | agent frontmatter |
| `team-reviewer` *(parallel fan-out only)* — reviews each unit's diff before merge | Opus 5.5 | medium | agent frontmatter |
| `explorer`, `codex-triage`, `spec-reviewer`; `team-merger` *(parallel fan-out only)* | Sonnet 5 | medium | agent frontmatter |
| Unpinned spawns (`general-purpose`, a bare `Agent` call) | Sonnet 5 | the master's | `CLAUDE_CODE_SUBAGENT_MODEL` floor |

"Opus 5.5" is what the unpinned `opus` alias resolves to today — see [Model
pinning](#model-pinning). Executor spawns are sized to one concern each
(roughly ≤100 tool calls; the plan splits anything bigger).

## Install

### Recommended — let Claude Code install it (interactive wizard)

Open Claude Code and paste this:

> Set up the Claude Code parallel-multi-agent kit from https://github.com/TurboKach/claude-code-setup — clone it to a temp directory, read INSTALL.md, and run it as an interactive install wizard. Detect what I already have and only install what's missing.

Claude checks your machine and walks you through it step by step: it offers to
install what you're missing (gstack), asks how to handle an existing
`CLAUDE.md`, which Opus version to pin, and which codex model the cross-review
gate should use — then enables the required settings and copies the skill +
agents with backups. Exactly what it does: [`INSTALL.md`](INSTALL.md).

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
SHA you installed — one cached `curl` to the GitHub API (a second for the count when
there's news), silent otherwise, and shown at every session start until you install it:

```
claude-code-setup: 3 new changes (installed abc1234 → remote def5678) — run /stack-update
```

If you edit the kit itself: commit first, then `./install.sh` — the stamp is the checkout's HEAD at install time, so installing before the commit leaves it one behind and the hook reports your own push as an update. `/stack-update` applies it: clones the repo, summarizes what changed, and **asks for your
approval before writing anything**. Two state stamps track the update, not one — `installed`
(the SHA skills/agents/settings are at) and `claude-md-installed` (the SHA whose `CLAUDE.md`
you actually accepted). They diverge because `install.sh` never overwrites an existing
`~/.claude/CLAUDE.md`, and `/stack-update` lets you decline that merge — so a single stamp
would call the kit up to date while your `CLAUDE.md` sat stale and the change went missing.

Opt out with `touch ~/.claude/.claude-code-setup/disabled`.

## Model pinning

The agent files pin models by **alias** (`model: opus` / `model: sonnet`; the
plan reviewer uses `model: inherit`), so they keep their semantic tiers — "heavy role" vs "cheap
role" — while one env var decides which concrete version each alias means.
Claude Code resolves the aliases through `ANTHROPIC_DEFAULT_OPUS_MODEL` /
`ANTHROPIC_DEFAULT_SONNET_MODEL` / `ANTHROPIC_DEFAULT_HAIKU_MODEL` /
`ANTHROPIC_DEFAULT_FABLE_MODEL` everywhere: the main session, agent
frontmatter, and per-spawn model choices. The `fable` alias is deliberately
left unpinned.

The kit leaves `opus` unpinned, so it follows the latest Opus. To hold a
version (a new Opus release then won't change or re-price your agents), install
with `--opus-pin=<model id>` or set it yourself:

```json
"env": { "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-5-5" }
```

`install.sh` removes the kit's earlier `claude-opus-5` pin and leaves any other
value alone. The `_SONNET_`/`_HAIKU_` variants pin those tiers the same way.

It also sets `CLAUDE_CODE_SUBAGENT_MODEL` to `sonnet` as a **floor**, not an
override: an agent definition's `model:` and an explicit per-spawn model both
take precedence over it. The pinned roles keep their frontmatter
pins (`team-reviewer`, the executors and `fixer` on `opus`; `team-plan-reviewer`'s `inherit` also
outranks the floor and follows the session's model), and a per-spawn `model: "opus"` still wins — the floor only catches
a spawn with no pin anywhere (`general-purpose`, a bare `Agent` call — built-in
`Explore` is the exception, always capped at Opus regardless of this floor),
which would otherwise inherit whatever tier the master is running. Settings
`env` changes are read at session start — restart Claude Code after editing.

## Requirements

**Default path (background subagents + Workflows):**
- Claude Code, current version — it auto-updates; `claude --version` if in doubt.
- That's it for the pipeline itself — no flags, no extra tools. The
  always-on codex gate (hard gate in global CLAUDE.md) is separate: it needs
  `codex` (codex-cli with `--ephemeral` support), `gtimeout`
  (`brew install coreutils`), and `pgrep` installed before your first push —
  the non-interactive installer installs none of them.

**Recommended for the full workflow:**
- **gstack** *(optional)* — the workflow's browser verification uses its
  `/browse`. Install:
  ```bash
  git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack \
    && cd ~/.claude/skills/gstack && ./setup
  ```
  Without gstack the team still works — verify web flows with another browser
  tool. The codex gate needs `codex` (codex-cli) and `gtimeout`
  (`brew install coreutils`), not gstack.

## Notes

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
