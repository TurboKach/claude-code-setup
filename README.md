# Claude Code setup — agent-teams starter kit

My [Claude Code](https://code.claude.com) setup: an opinionated `CLAUDE.md`, plus
a working **agent-teams** system — a skill that orchestrates parallel multi-agent
work and the role agents it spawns. Clone, run the installer, do four manual
steps, and you have parallel teammates running in iTerm2 split panes.

> Agent teams are an **experimental** Claude Code feature. They use significantly
> more tokens than a single session — use them for parallel research, review, and
> feature work, not routine tasks.

## What's inside

| Path | What it is |
|------|-----------|
| `CLAUDE.md` | Universal principles + workflow (think-before-coding, simplicity, surgical changes, multi-session workflow, the agent-teams trigger) |
| `skills/agent-teams/SKILL.md` | The orchestration playbook — when to fan out, the pipeline, models, worktree/merge flow, the plan-approval gate. Loads on demand. |
| `agents/team-planner.md` | Writes the plan, runs `/autoplan`, surfaces it for **your** approval *(Opus)* |
| `agents/team-prompt-smith.md` | Turns the approved plan into one spawn prompt per executor *(Sonnet)* |
| `agents/team-executor.md` | Implements one unit in its own worktree, as a **teammate** *(Sonnet; Opus for hard units)* |
| `agents/team-reviewer.md` | Adversarially verifies each diff before merge *(Opus)* |
| `agents/team-merger.md` | Merges approved worktrees into the base branch, reports done *(Sonnet)* |
| `settings.example.json` | The two required keys: the feature flag + `teammateMode` |
| `install.sh` | Copies everything into `~/.claude` (with backups) and merges the settings keys |
| `docs/agent-teams-setup.md` | Full macOS + iTerm2 walkthrough |

## How the team works

Only the **lead** (your main session) spawns. Sequential steps run as subagents;
the parallel **execution** step runs as teammates that can message each other:

```
PLAN (planner) → you approve the plan ─┐   ← the only approval gate
PROMPTS (prompt-smith)                 │
EXECUTE (N executor teammates, parallel, in worktrees)  ← coordinate contracts via messaging
REVIEW (reviewer)                      │
MERGE (merger) → reports completion ───┘
```

Models follow a simple rule: **Opus for judgment** (plan, review), **Sonnet for
production work** (prompts, execute, merge), with Opus available per-spawn for
architecturally hard units.

## Quickstart

```bash
git clone https://github.com/TurboKach/claude-code-setup.git
cd claude-code-setup
./install.sh
```

Then four manual steps (the installer prints these too):

1. **it2 CLI:** `uv tool install it2` (or `pip install it2`)
2. **iTerm2 API:** `defaults write com.googlecode.iterm2 EnableAPIServer -bool true`
3. **Restart iTerm2** (Cmd+Q) and approve the one-time API permission dialog.
4. **Restart Claude Code**, then `/config` → Default teammate model → **Sonnet**.

Full details: [`docs/agent-teams-setup.md`](docs/agent-teams-setup.md).

## Requirements

- macOS + iTerm2 (split panes need tmux or iTerm2)
- Claude Code **v2.1.18x or newer** (`claude --version`)
- `uv` or `pip` (for `it2`)
- **gstack** *(optional but recommended)* — the planner runs `/autoplan` and the
  workflow references `/ship`, `/context-save`, etc. Install:
  ```bash
  git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack \
    && cd ~/.claude/skills/gstack && ./setup
  ```
  Without gstack the team still works — substitute plan mode for `/autoplan` and
  plain git/PR commands for the ship steps.

## Notes

- The installer **never overwrites an existing `~/.claude/CLAUDE.md`** and backs
  up any skill/agent files it replaces (under `~/.claude/.backup-<timestamp>`).
  It merges only the two settings keys, with a `settings.json.bak` safety copy.
- `settings.example.json` is intentionally minimal — your real `settings.json`
  is personal; never commit it (it tends to hold emails, tokens, and private
  paths).

## Credits

Workflow and `agent-teams` system by [@TurboKach](https://github.com/TurboKach).
gstack by [Garry Tan](https://github.com/garrytan/gstack). Built for
[Claude Code](https://code.claude.com). MIT licensed.
