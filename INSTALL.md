# Install wizard (agent-facing)

> **You are Claude Code, running this install for the user.** Follow these steps
> as an **interactive wizard**. Detect what's already present, ask before
> installing anything optional or heavy, never overwrite without a backup, and
> keep questions to a minimum — skip anything already satisfied. `SRC` below is
> the directory you cloned this repo into.

## Step 0 — Detect (don't install anything yet)

Run these and show the user a short status summary:

```bash
uname -s                                          # Darwin = macOS (needed for iTerm2 split panes)
claude --version                                  # need >= 2.1.186 (background permission prompts, teammateMode "iterm2")
ls -d /Applications/iTerm.app 2>/dev/null || echo "iTerm2: missing"
which brew uv it2 2>/dev/null
ls -d ~/.claude/skills/gstack 2>/dev/null && echo "gstack: present" || echo "gstack: missing"
test -f ~/.claude/CLAUDE.md && echo "CLAUDE.md: exists" || echo "CLAUDE.md: none"
python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
d = json.load(open(p)) if os.path.exists(p) else {}
print("flag set:", d.get("env", {}).get("CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"))
print("teammateMode:", d.get("teammateMode"))
PY
```

- If `uname -s` is **not** `Darwin`: tell the user split panes need macOS+iTerm2
  (or tmux); they can still use `teammateMode: in-process`. Skip the iTerm2/it2
  offers below and continue with the core kit.
- If `claude --version` is older than 2.1.186: suggest updating Claude Code —
  before 2.1.186 background subagents silently auto-denied permission prompts,
  and split panes / `teammateMode: "iterm2"` may not work.

## Step 1 — Ask what to set up (AskUserQuestion)

Offer **only** items that are missing or are real decisions. Suggested:

1. **Components** (multiSelect): core kit (skill + agents — the point, pre-checked,
   enables the default background-subagent + Workflows path); optional teammate
   path (settings flag + `teammateMode` + `it2` + iTerm2 — only for live
   cross-talk); gstack *(if missing)*.
2. **CLAUDE.md handling** — only if `~/.claude/CLAUDE.md` already exists:
   *append the parallel-multi-agent section* (recommended) / *replace with this
   repo's CLAUDE.md* / *leave mine untouched*. If none exists, just install this
   repo's `CLAUDE.md` (no need to ask).

Explain briefly: the **default path** (background subagents + Workflows) needs
nothing beyond the skill + agents — no flag, no iTerm2. The settings flag +
iTerm2 + `it2` are **only** for the optional named-teammate split-pane path
(almost never needed — live dialogue with a delegated agent). gstack is optional — it powers `/autoplan`, `/ship`, `/context-save`
referenced by the workflow; without it, substitute plan mode and plain git.

## Step 2 — Execute (only chosen + only missing)

**Core kit** (always, if chosen):
```bash
mkdir -p ~/.claude/agents ~/.claude/skills
STAMP=$(date +%Y%m%d-%H%M%S); BK=~/.claude/.backup-$STAMP
# back up + copy skill and agents
[ -e ~/.claude/skills/agent-teams ] && mkdir -p "$BK/skills" && cp -R ~/.claude/skills/agent-teams "$BK/skills/"
rm -rf ~/.claude/skills/agent-teams && cp -R "$SRC/skills/agent-teams" ~/.claude/skills/agent-teams
for f in "$SRC"/agents/team-*.md; do
  b=$(basename "$f"); [ -e ~/.claude/agents/$b ] && mkdir -p "$BK/agents" && cp ~/.claude/agents/$b "$BK/agents/"
  cp "$f" ~/.claude/agents/$b
done
```
Then, **only if the user chose the optional teammate path**, merge its settings
keys (preserve everything else) — skip this for a default-path-only install:
```bash
python3 - "$SRC/settings.example.json" <<'PY'
import json, os, sys
ex = json.load(open(sys.argv[1]))
p = os.path.expanduser("~/.claude/settings.json")
d = json.load(open(p)) if os.path.exists(p) else {}
if os.path.exists(p): json.dump(d, open(p+".bak","w"), indent=2)
d.setdefault("env", {})["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = ex["env"]["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"]
d["teammateMode"] = ex["teammateMode"]
json.dump(d, open(p,"w"), indent=2)
print("settings.json: flag + teammateMode set (backup: settings.json.bak)")
PY
```

**CLAUDE.md** (per the chosen handling):
- *none exists* → `cp "$SRC/CLAUDE.md" ~/.claude/CLAUDE.md`
- *append* → add this repo's `## Parallel multi-agent` section to
  the end of the user's `~/.claude/CLAUDE.md` (copy it verbatim from
  `$SRC/CLAUDE.md`). Don't duplicate it if already present.
- *replace* → back up to `$BK`, then copy.
- *leave* → do nothing.

**it2** (if chosen):
```bash
if command -v uv >/dev/null; then uv tool install it2
elif command -v pip >/dev/null; then pip install it2
else echo "Install uv first (https://docs.astral.sh/uv/) or pip, then: uv tool install it2"; fi
```

**iTerm2** (if chosen):
```bash
if command -v brew >/dev/null; then brew install --cask iterm2
else echo "Homebrew not found — download iTerm2 from https://iterm2.com/downloads.html"; fi
```
Then enable its Python API (needed for split panes):
```bash
defaults write com.googlecode.iterm2 EnableAPIServer -bool true
```

**gstack** (if chosen):
```bash
git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack \
  && cd ~/.claude/skills/gstack && ./setup
```

## Step 3 — Tell the user the manual steps

**Default path:** just **restart Claude Code** so the skill + agents load. Nothing
else. Then suggest a test (background subagents, read-only → no worktrees):
> Spawn 3 background subagents to review this code in parallel — one on security,
> one on performance, one on test coverage. Have them report findings.

**Optional teammate path only** (skip unless they installed it — cannot be automated):
1. **Quit iTerm2 (Cmd+Q) and reopen** — activates the API server. Approve the
   one-time "allow Python API" dialog on first team spawn.
2. **Restart Claude Code** — cold start, inside iTerm2, so the flag,
   `teammateMode`, skill, and agents all load. Don't `--resume`.
3. **`/config` → Default teammate model → Sonnet** (token-efficient floor;
   per-role models in the agent files override it).

## Rules

- Never overwrite `~/.claude/CLAUDE.md` or `settings.json` without a backup.
- Skip anything already installed — say "already present" and move on.
- Report a final summary: what was installed, what was skipped, what's manual.
