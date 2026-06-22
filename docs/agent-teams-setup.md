# Named-teammate path setup (macOS + iTerm2)

> **You only need this for the optional named-teammate path.** The kit's default
> — background subagents + Workflows — needs none of this (no feature flag, no
> iTerm2, no `it2`). Set this up only when you specifically want agents that talk
> to each other *live* in iTerm2 split panes; see the "Pick the mechanism" and
> "Named-teammate path" sections of the `agent-teams` skill.

This walks through enabling [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams)
with iTerm2 split panes, end to end. Agent teams are **experimental** and off by
default.

## Requirements

- **macOS** with **iTerm2** (split panes need tmux or iTerm2; this guide uses iTerm2).
- **Claude Code v2.1.18x or newer** — check with `claude --version`.
- **uv** (or pip) to install the `it2` CLI.
- *(Optional)* **gstack** — the planner role runs `/autoplan` and the workflow
  references `/ship`, `/context-save`, etc. Without gstack those steps fall back
  to plain plan mode / manual git. See [the gstack note](#gstack-optional).

## 1. Enable the feature flag + split-pane mode

Add to `~/.claude/settings.json` (the installer merges these for you):

```json
{
  "env": { "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1" },
  "teammateMode": "auto"
}
```

- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` turns the feature on. Without it, no
  team is set up and Claude won't spawn or propose teammates.
- `teammateMode: "auto"` uses split panes when you're in iTerm2 or tmux, and
  falls back to in-process (single terminal) otherwise. Other values: `"tmux"`
  (force split panes) and `"in-process"` (never split).

## 2. Install the it2 CLI

iTerm2 split panes are driven through the [`it2` CLI](https://github.com/mkusaka/it2):

```bash
uv tool install it2      # recommended
# or
pip install it2
```

Confirm it's on your PATH: `which it2`.

## 3. Enable the iTerm2 Python API

```bash
defaults write com.googlecode.iterm2 EnableAPIServer -bool true
```

Then **fully quit iTerm2 (Cmd+Q) and reopen it** — the setting only applies on
restart. On the first API connection, iTerm2 shows a **one-time permission
dialog**; click **Allow** (optionally "always allow for this tool").

> GUI equivalent: iTerm2 → Settings → General → Magic → **Enable Python API**.

## 4. Pick the default teammate model

Teammates do **not** inherit your `/model`. Set a token-efficient floor:

- `/config` → **Default teammate model** → **Sonnet**

Per-role models are baked into the `team-*` agent definitions (Opus for the
judgment-heavy planner/reviewer, Sonnet for execution/merge), so they override
this default where it matters.

## 5. Restart Claude Code

Launch a fresh `claude` **inside iTerm2** so the env var, `teammateMode`, the
skill, and the agent files all load. (Split panes need iTerm2/tmux — VS Code's
integrated terminal, Windows Terminal, and Ghostty fall back to in-process.)

## Verify

In a project, ask for genuinely parallel work, e.g.:

```
Spawn 3 teammates to review this PR — one on security, one on performance,
one on test coverage. Have them report findings.
```

Teammates should appear as split panes (or in the agent panel in-process; use
↑/↓ + Enter to view one, Ctrl+T to toggle the task list).

## gstack (optional)

The full workflow leans on [gstack](https://github.com/garrytan/gstack) skills
(`/autoplan`, `/office-hours`, `/context-save`, `/codex`, `/ship`,
`/land-and-deploy`). Install it with:

```bash
git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack \
  && cd ~/.claude/skills/gstack && ./setup
```

Without gstack, the team still works — just substitute plan mode for `/autoplan`
and use plain git/PR commands for the ship steps.

## Notes & limitations

- **One team per session; the lead is fixed.** Only the lead spawns — teammates
  can't spawn teammates (no nested teams).
- **Layout is automatic** — each teammate gets its own pane; there's no per-role
  tab grouping. Name your teammates so you can address them by name.
- **`/resume` and `/rewind` don't restore in-process teammates.** If the lead
  messages a teammate that no longer exists, tell it to spawn fresh ones.
- Agent teams use **significantly more tokens** than a single session — use them
  for parallel research/review/feature work, not routine tasks.
