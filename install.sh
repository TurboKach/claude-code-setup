#!/usr/bin/env bash
set -euo pipefail

# Claude Code parallel-multi-agent starter kit installer.
# Copies CLAUDE.md, the agent-teams skill, and the team-* agents into ~/.claude,
# backing up anything it would overwrite. The kit's default path (background
# subagents + Workflows) needs nothing else. This also merges the settings keys
# from settings.example.json: the teammate-path pair (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
# + teammateMode, only matter for the optional iTerm2 path) and the model pin
# (ANTHROPIC_DEFAULT_OPUS_MODEL — keeps the "opus" alias on a fixed version;
# added only if you haven't set your own value).

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CLAUDE_HOME:-$HOME/.claude}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$DEST/.backup-$STAMP"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

mkdir -p "$DEST/agents" "$DEST/skills"

backup() { # $1 = path under DEST
  if [ -e "$DEST/$1" ]; then
    mkdir -p "$BACKUP/$(dirname "$1")"
    cp -R "$DEST/$1" "$BACKUP/$1"
    echo "  backed up $1"
  fi
}

say "Installing into $DEST (backups -> $BACKUP)"

# CLAUDE.md — never clobber an existing personal one.
# (The source lives at global/CLAUDE.md so sessions in this repo don't load it
# twice — a repo-root CLAUDE.md would duplicate ~/.claude/CLAUDE.md in context.)
if [ -e "$DEST/CLAUDE.md" ]; then
  echo "  $DEST/CLAUDE.md exists — left untouched. Merge from $SRC/global/CLAUDE.md by hand if you want it."
else
  cp "$SRC/global/CLAUDE.md" "$DEST/CLAUDE.md"; echo "  installed CLAUDE.md"
fi

# Skill — back up then replace.
backup "skills/agent-teams"
rm -rf "$DEST/skills/agent-teams"
cp -R "$SRC/skills/agent-teams" "$DEST/skills/agent-teams"
echo "  installed skills/agent-teams"

# Agents — back up each, then copy.
for f in "$SRC"/agents/team-*.md; do
  base="agents/$(basename "$f")"
  backup "$base"
  cp "$f" "$DEST/$base"
done
echo "  installed team-* agents"

# settings.json — merge the example keys, preserving everything else.
# Teammate-path pair is forced to the example values; model-pin env vars are
# added only when absent, so a user's own pin is never clobbered.
SETTINGS="$DEST/settings.json"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS" "$SRC/settings.example.json" <<'PY'
import json, os, sys
settings, example = sys.argv[1], sys.argv[2]
ex = json.load(open(example))
if os.path.exists(settings):
    d = json.load(open(settings))
    json.dump(d, open(settings + ".bak", "w"), indent=2)  # safety copy
else:
    d = {}
env = d.setdefault("env", {})
env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = \
    ex["env"]["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"]
for k, v in ex["env"].items():
    env.setdefault(k, v)  # model pins etc. — never clobber an existing choice
d["teammateMode"] = ex["teammateMode"]
json.dump(d, open(settings, "w"), indent=2)
print("  merged env + teammateMode into settings.json (backup: settings.json.bak)")
PY
else
  echo "  python3 not found — add the keys from settings.example.json to $SETTINGS by hand"
fi

say "Files installed. The default path (background subagents + Workflows) is ready now —"
say "just restart Claude Code and ask for parallel work."
cat <<'EOF'

Optional — only if you want the experimental named-teammate (iTerm2 split-pane) path.
(The installer sets teammateMode: "in-process" = teammates run in-process and show
in the status bar, NO terminal panes. Opt into split panes by setting it to "iterm2":)
  1. Enable panes:  set "teammateMode": "iterm2" in ~/.claude/settings.json
  2. it2 CLI (iTerm2 split panes):   uv tool install it2      (or: pip install it2)
  3. Enable iTerm2 Python API:       defaults write com.googlecode.iterm2 EnableAPIServer -bool true
  4. Quit & reopen iTerm2 (Cmd+Q); approve the one-time API permission dialog on first use.
  5. Restart Claude Code (inside iTerm2), then: /config -> Default teammate model -> Sonnet.

Recommended for the full workflow:
  - gstack for /autoplan, /ship, /context-save, etc.:
      git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack \
        && cd ~/.claude/skills/gstack && ./setup

Named-teammate walkthrough: docs/agent-teams-setup.md
EOF
