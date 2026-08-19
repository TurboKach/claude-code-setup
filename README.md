# Claude Code setup — parallel multi-agent starter kit

My [Claude Code](https://code.claude.com) setup: an opinionated `CLAUDE.md`, plus
a working **parallel multi-agent** system — a skill that orchestrates fan-out work
and the role agents it spawns. Clone, run the installer, and you have a
plan → execute → review → merge pipeline that fans out across **background
subagents** (the default — in-process, isolated worktrees only where they write
in parallel, no extra setup).

> The default path uses ordinary background subagents and (optionally) Workflows —
> no experimental flags, no iTerm2. **Named teammates in iTerm2 split panes** are
> an **experimental** extra that's **almost never needed** — only to dialogue live
> with a delegated agent running in parallel; that's the only part that needs the
> feature flag + iTerm2 setup.
>
> Fan-out uses significantly more tokens than a single session — use it for
> parallel research, review, and feature work, not routine tasks.

## What's inside

| Path | What it is |
|------|-----------|
| `global/CLAUDE.md` | Lean always-on layer: principles (think-before-coding, simplicity, surgical changes), the hard gates (push approval, `/codex` merge gate, AFK-not-approval), and a pointer to the feature-workflow skill. Lives under `global/` so working sessions in this repo don't load it twice alongside `~/.claude/CLAUDE.md` |
| `global/rules/` | Path-scoped user rules, installed to `~/.claude/rules/` — load only when a matching file is touched, so they don't add to every session's always-on context |
| `skills/feature-workflow/SKILL.md` | The six-stage single-master feature pipeline, the parallel-multi-agent mechanism picker, and the token-discipline rules. Loads on demand when a pipeline or fan-out starts (extracted from CLAUDE.md per 5-gen progressive disclosure). |
| `skills/agent-teams/SKILL.md` | The orchestration playbook — when to fan out, how to pick the mechanism (subagents / Workflows / teammates), the pipeline, models, worktree/merge flow, the plan-approval gate. Loads on demand. |
| `agents/team-planner.md` | Explores and **returns** the plan as text (headless, read-only); the lead — in native plan mode — writes it to the plan file *(Opus)* |
| `agents/explorer.md` | Read-only codebase search on Sonnet at effort medium — the pinned stand-in for built-in `Explore` *(Sonnet)* |
| `agents/team-plan-reviewer.md` | Validates the plan against the code before the lead presents it via `ExitPlanMode` for **your** approval *(Opus)* |
| `agents/team-executor.md` | Implements one unit of a **parallel** fan-out as a background subagent — carries `isolation: worktree` in its frontmatter, since concurrent writers merge later *(Sonnet xhigh; Opus only when the plan justifies it)* |
| `agents/step-executor.md` | Implements one **sequential** step on the session's own branch — no worktree, nothing to merge; the feature-workflow counterpart to `team-executor` *(Sonnet xhigh; Opus only when the plan justifies it)* |
| `agents/team-reviewer.md` | Adversarially verifies each diff before merge — read-only, no worktree *(Opus)* |
| `agents/team-merger.md` | Merges approved worktrees into the base branch, removes each worktree + branch after landing, reports done *(Sonnet)* |
| `settings.example.json` | The teammate-feature keys (the flag + `teammateMode`, defaults to `in-process` — teammates in the status bar, **no panes**; set to `"iterm2"` to opt into split panes), the model pin (`ANTHROPIC_DEFAULT_OPUS_MODEL` — see [Model pinning](#model-pinning)), `worktree.baseRef: "head"` so executor worktrees branch from your in-progress branch rather than the remote default, and the `SessionStart` update-check hook |
| `hooks/stack-update-check.sh` | Runs once per session start: at most once a day, checks whether this repo's `master` differs from the SHA you installed, and prints one line if so — silent otherwise (no update, no network, disabled, cached) |
| `skills/stack-update/SKILL.md` | Applies a pending update: clones the repo, summarizes what changed, asks for your approval before writing anything, re-runs `install.sh`, and re-stamps |
| `install.sh` | Copies everything into `~/.claude` (with backups) and merges the settings keys above |
| `docs/agent-teams-setup.md` | macOS + iTerm2 walkthrough — only needed for the optional named-teammate path |

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
CODEX (lead) → one Skill(codex, "challenge <feature-base>..HEAD") ─┘   ← triaged verdict, P1/P2 fixed
```

Pick the fan-out mechanism by need: **background subagents** by default;
**Workflows** for large/deterministic/resumable fan-outs; **named teammates**
almost never (only to dialogue live with a delegated parallel agent — the
experimental iTerm2 path). Worktree isolation is added **only** where agents
write in parallel and merge — read-only fan-out (review, research) skips it.

Models follow a simple rule: **Opus for judgment** (plan, review), **Sonnet for
production work** (execute, merge), with Opus available per-spawn for
architecturally hard units. Executor spawns are sized to one concern each
(roughly ≤100 tool calls; the plan splits anything bigger).

## Install

### Recommended — let Claude Code install it (interactive wizard)

Open Claude Code and paste this:

> Set up the Claude Code parallel-multi-agent kit from https://github.com/TurboKach/claude-code-setup — clone it to a temp directory, read INSTALL.md, and run it as an interactive install wizard. Detect what I already have and only install what's missing.

Claude checks your machine and walks you through it step by step: it offers to
install only what you're missing (iTerm2, `it2`, gstack), enables the required
settings, and copies the skill + agents with backups. Exactly what it does:
[`INSTALL.md`](INSTALL.md).

### Alternative — non-interactive script

```bash
git clone https://github.com/TurboKach/claude-code-setup.git
cd claude-code-setup
./install.sh    # copies skill+agents+CLAUDE.md and merges settings; installs nothing else
```

The default path (background subagents + Workflows) needs **no manual steps** —
once the files are copied, ask for parallel work and it fans out.

### Manual steps — only for the optional named-teammate path

Skip these unless you want the experimental iTerm2 split-pane teammates. (The
installer sets `teammateMode: "in-process"` — status-bar teammates, no panes; step 1
opts into panes. Panes don't self-close: `Cmd-W` a pane's tab to close it.)

1. **Enable panes:** set `"teammateMode": "iterm2"` in `~/.claude/settings.json`.
2. **Restart iTerm2** (Cmd+Q, reopen) and approve the one-time API permission dialog.
3. **Restart Claude Code** — cold start, inside iTerm2 (the mode is read at startup).
4. **`/config` → Default teammate model → Sonnet.**

Full walkthrough: [`docs/agent-teams-setup.md`](docs/agent-teams-setup.md).

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

The agent files pin models by **alias** (`model: opus` / `model: sonnet`), so
they keep their semantic tiers — "heavy role" vs "cheap role" — while one env
var decides which concrete version each alias means. Claude Code resolves the
aliases through `ANTHROPIC_DEFAULT_OPUS_MODEL` / `ANTHROPIC_DEFAULT_SONNET_MODEL` /
`ANTHROPIC_DEFAULT_HAIKU_MODEL` everywhere: the main session, agent frontmatter,
and per-spawn model choices.

`settings.example.json` pins Opus to `claude-opus-5` so a new Opus release
never silently changes (or re-prices) your agents:

```json
"env": { "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-5" }
```

Change the value to move to a different version, delete the key to follow the
latest Opus again, or add the `_SONNET_`/`_HAIKU_` variants to pin those tiers
too. Settings `env` changes are read at session start — restart Claude Code
after editing. (Verified: with the pin set, `--model opus` and `model: opus`
agents run the pinned version; the var works both from the shell and from the
settings `env` block.)

## Requirements

**Default path (background subagents + Workflows):**
- Claude Code **v2.1.186 or newer** (`claude --version`) — use the latest.
  v2.1.186 is the practical floor: from there, background subagents surface
  permission prompts in your session (earlier versions silently auto-denied
  them). Workflows shipped in v2.1.154; no install required.
- That's it — no flags, no iTerm2.

**Optional named-teammate (iTerm2 split-pane) path adds:**
- macOS + iTerm2 (split panes need tmux or iTerm2)
- `uv` or `pip` (for `it2`)
- the teammate keys from `settings.example.json` (the installer merges them)

**Recommended for the full workflow:**
- **gstack** *(optional)* — the workflow references `/office-hours`, `/codex`,
  `/ship`, `/context-save`, etc. Install:
  ```bash
  git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack \
    && cd ~/.claude/skills/gstack && ./setup
  ```
  Without gstack the team still works — skip the codex gate (say so) and use
  plain git/PR commands for the ship steps.

## Notes

- **2026-08-19 prompt-smith retired:** the lead writes each executor's spawn prompt inline while spawning (contract in `skills/agent-teams/SKILL.md` § "Spawn prompt contract"); a separate prompt-writing agent returned the prompts to the lead anyway, so it only added a serial stage and a second copy of the same text.
- **2026-08-18 two paths + task list:** one-shot (≤3 files, no design/UI choice, reversible — no plan ceremony, but `/codex challenge` still runs on the diff) vs pipeline, with the call stated in one line; every spawn pins `model:` (never `fable`); codebase search uses the kit's `explorer` agent (sonnet, medium) instead of built-in `Explore`, which inherits the session's model and effort; at plan approval the master mirrors the plan into Claude's native task list (`CLAUDE_CODE_ENABLE_TODO_TOOLS=1`, merged by the installer) — one task per step + the fixed tail — and marks tasks done as steps land (no Stop hook, deliberately).
- **2026-08-18 pipeline diet (from the clipsy_ios S1–S4 forensics):** `/codex challenge` runs once per feature (not per step) with P1/P2 priorities and a fix-now / defer-to-tech-debt question for the rest; `/goal` is dropped — plan approval starts the tail; executors and fixers are Sonnet xhigh, Opus only when the plan justifies it. gstack's codex skill needs a local patch on macOS (`mktemp "$TMP_ROOT/codex-err-XXXXXX"` — drop the `.txt` suffix, BSD mktemp rejects it); re-apply after `/gstack-upgrade`.
- **Native plan mode replaced gstack `/autoplan` on 2026-08-18 (experiment).** Stage 2–3 is now `EnterPlanMode` → `team-planner` returns the draft → lead transcribes → `team-plan-reviewer` validates → one AskUserQuestion for taste items → `ExitPlanMode`. To restore `/autoplan`: `git revert autoplan-off && ./install.sh` (tag `autoplan-off` marks the switch commit).
- The installer **never overwrites an existing `~/.claude/CLAUDE.md`** and backs
  up any skill/agent files it replaces (under `~/.claude/.backup-<timestamp>`).
  It merges only the `settings.example.json` keys, with a `settings.json.bak`
  safety copy — and never overwrites a model pin you already set.
- `settings.example.json` is intentionally minimal — your real `settings.json`
  is personal; never commit it (it tends to hold emails, tokens, and private
  paths).

## Credits

Workflow and parallel multi-agent system by [@TurboKach](https://github.com/TurboKach).
gstack by [Garry Tan](https://github.com/garrytan/gstack). Built for
[Claude Code](https://code.claude.com). MIT licensed.
