#!/usr/bin/env bash
set -euo pipefail

# Claude Code parallel-multi-agent starter kit installer.
# Copies CLAUDE.md, the agent-teams skill, and the team-* agents into ~/.claude,
# backing up anything it would overwrite. The kit's default path (background
# subagents + Workflows) needs nothing else. This also merges the settings keys
# from settings.example.json: the teammate-path pair (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS
# + teammateMode, only matter for the optional iTerm2 path) and the model pin
# (ANTHROPIC_DEFAULT_OPUS_MODEL — keeps the "opus" alias on a fixed version;
# added only if you haven't set your own value). It also installs a SessionStart
# hook that checks once a day whether this repo has moved past the SHA you
# installed, and stamps that SHA so the check has something to compare against.

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
CLAUDE_MD_INSTALLED=0
if [ -e "$DEST/CLAUDE.md" ]; then
  echo "  $DEST/CLAUDE.md exists — left untouched. Merge from $SRC/global/CLAUDE.md by hand if you want it."
else
  cp "$SRC/global/CLAUDE.md" "$DEST/CLAUDE.md"; echo "  installed CLAUDE.md"
  CLAUDE_MD_INSTALLED=1
fi

# Skills — back up then replace.
for skill in agent-teams feature-workflow stack-update; do
  backup "skills/$skill"
  rm -rf "$DEST/skills/$skill"
  cp -R "$SRC/skills/$skill" "$DEST/skills/$skill"
  echo "  installed skills/$skill"
done

# Agents — back up each, then copy.
for f in "$SRC"/agents/*.md; do
  base="agents/$(basename "$f")"
  backup "$base"
  cp "$f" "$DEST/$base"
done
echo "  installed agents (team-* + step-executor)"

# Update-check hook — back up then replace.
mkdir -p "$DEST/hooks"
backup "hooks/stack-update-check.sh"
cp "$SRC/hooks/stack-update-check.sh" "$DEST/hooks/stack-update-check.sh"
chmod +x "$DEST/hooks/stack-update-check.sh"
echo "  installed hooks/stack-update-check.sh"

# Stamp the state dir so the update check has a SHA to compare against.
# Skipped for a non-git checkout (e.g. a downloaded tarball) — with no stamp
# the hook stays silent forever, which is the correct behavior there.
if INSTALLED_SHA="$(git -C "$SRC" rev-parse HEAD 2>/dev/null)"; then
  mkdir -p "$DEST/.claude-code-setup"
  echo "$INSTALLED_SHA" > "$DEST/.claude-code-setup/installed"
  echo "  stamped .claude-code-setup/installed"
  if [ "$CLAUDE_MD_INSTALLED" = 1 ]; then
    echo "$INSTALLED_SHA" > "$DEST/.claude-code-setup/claude-md-installed"
    echo "  stamped .claude-code-setup/claude-md-installed"
  fi
else
  echo "  $SRC is not a git checkout — skipping update-check stamp (check will stay disabled)"
fi

# settings.json — merge the example keys, preserving everything else.
# Teammate-path pair is forced to the example values; model-pin env vars are
# added only when absent, so a user's own pin is never clobbered.
SETTINGS="$DEST/settings.json"
HOOK_PATH="$DEST/hooks/stack-update-check.sh"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS" "$SRC/settings.example.json" "$HOOK_PATH" "$DEST" <<'PY'
import json, os, sys
settings, example, hook_path, dest = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
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
# Executor worktrees must branch from the session's in-progress branch, not the
# remote default — otherwise they can't see the plan file or prior units' work.
d.setdefault("worktree", {}).setdefault("baseRef", ex["worktree"]["baseRef"])

def norm_path(cmd):
    # Representation-independent comparison: a command written as
    # "~/.claude/..." or "$HOME/.claude/..." (as settings.example.json ships
    # it) refers to this install's DEST, which may differ from the real $HOME
    # when CLAUDE_HOME is overridden — so resolve those prefixes against DEST
    # before falling back to normal ~/$HOME expansion, then resolve the path.
    # A malformed settings.json can hold a non-string (or unresolvable)
    # "command"; return None so it never matches a real path instead of
    # raising and aborting the whole merge.
    if not isinstance(cmd, str):
        return None
    try:
        for prefix in ("~/.claude", "$HOME/.claude"):
            if cmd.startswith(prefix):
                cmd = dest + cmd[len(prefix):]
                break
        else:
            cmd = os.path.expandvars(os.path.expanduser(cmd))
        return os.path.realpath(cmd)
    except Exception:
        return None

# SessionStart hook — append into the existing matcher-"" group (creating it if
# absent) rather than replacing the array, so other SessionStart hooks (e.g. a
# user's own peon-ping command) survive untouched. If hooks/SessionStart/the
# matcher-"" group aren't the shape we expect, skip hook registration only —
# never rewrite a structure we don't understand, and never abort the merge.
warning = None
hooks = d.setdefault("hooks", {})
if not isinstance(hooks, dict):
    warning = '"hooks" is not an object'
else:
    session_start = hooks.setdefault("SessionStart", [])
    if not isinstance(session_start, list):
        warning = '"hooks.SessionStart" is not an array'
    elif not all(isinstance(g, dict) for g in session_start):
        warning = '"hooks.SessionStart" contains a non-object entry'
    else:
        group = next((g for g in session_start if g.get("matcher") == ""), None)
        if group is None:
            group = {"matcher": "", "hooks": []}
            session_start.append(group)
        if "hooks" not in group:
            group["hooks"] = []
        entries = group["hooks"]
        if not isinstance(entries, list):
            warning = 'the matcher-"" group\'s "hooks" is not an array'
        else:
            target = norm_path(hook_path)
            already_present = any(
                isinstance(e, dict) and "command" in e and norm_path(e["command"]) == target
                for e in entries
            )
            if not already_present:
                entries.append({"type": "command", "command": hook_path, "timeout": 10})

json.dump(d, open(settings, "w"), indent=2)
if warning:
    print(f"  WARNING: settings.json's {warning} — skipped installing the SessionStart update-check hook.")
    print(f"  Add it by hand: copy the \"hooks\" block from {example} into {settings}.")
    print("  merged env + teammateMode + worktree.baseRef into settings.json (backup: settings.json.bak)")
else:
    print("  merged env + teammateMode + worktree.baseRef + SessionStart update-check hook into settings.json (backup: settings.json.bak)")
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
