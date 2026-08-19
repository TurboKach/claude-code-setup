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

1. **Components** (multiSelect): core kit (skills + agents + the `stack-update`
   check — the point, pre-checked, enables the default background-subagent +
   Workflows path); optional teammate path (settings flag + `teammateMode` +
   `it2` + iTerm2 — only for live cross-talk); gstack *(if missing)*.
2. **CLAUDE.md handling** — only if `~/.claude/CLAUDE.md` already exists:
   *append the feature-workflow pointer section* (recommended — the workflow
   itself lives in the `feature-workflow` skill the core kit installs) /
   *replace with this repo's CLAUDE.md* / *leave mine untouched*. If none
   exists, just install this repo's `CLAUDE.md` (no need to ask).
3. **Opus version** — only if `ANTHROPIC_DEFAULT_OPUS_MODEL` isn't already in
   their settings `env`: ask which Opus the `opus` alias should mean (via
   AskUserQuestion), so agent files saying `model: opus` don't silently follow
   new Opus releases. Options:
   - `claude-opus-5` *(recommended, the repo default — pinned so a future Opus
     won't silently bump it; control token use via effort + prompt tuning)*
   - `claude-opus-4-8` *(previous generation, if you want the older behavior)*
   - *don't pin* — the alias keeps following whatever Anthropic ships as Opus
   - custom: any full model ID the user types (the "Other" answer)

Explain briefly: the **default path** (background subagents + Workflows) needs
nothing beyond the skill + agents — no flag, no iTerm2. The settings flag +
iTerm2 + `it2` are **only** for the optional named-teammate split-pane path
(almost never needed — live dialogue with a delegated agent). gstack is optional — it powers `/office-hours`, `/codex`, `/ship`, `/context-save`
referenced by the workflow; without it, use plain git.

## Step 2 — Execute (only chosen + only missing)

**Core kit** (always, if chosen):
```bash
mkdir -p ~/.claude/agents ~/.claude/skills ~/.claude/hooks ~/.claude/rules
STAMP=$(date +%Y%m%d-%H%M%S); BK=~/.claude/.backup-$STAMP
# back up + copy skills and agents
for s in agent-teams feature-workflow stack-update; do
  [ -e ~/.claude/skills/$s ] && mkdir -p "$BK/skills" && cp -R ~/.claude/skills/$s "$BK/skills/"
  rm -rf ~/.claude/skills/$s && cp -R "$SRC/skills/$s" ~/.claude/skills/$s
done
for f in "$SRC"/agents/*.md; do
  b=$(basename "$f"); [ -e ~/.claude/agents/$b ] && mkdir -p "$BK/agents" && cp ~/.claude/agents/$b "$BK/agents/"
  cp "$f" ~/.claude/agents/$b
done
# retired agents — remove stale copies of agents the kit no longer ships.
# Reads the exact-filename list straight out of install.sh's RETIRED_AGENTS
# array so this can't drift from the script's own copy; matches by exact
# filename only, so it can never touch an agent file the user wrote themselves.
for name in $(sed -n 's/^RETIRED_AGENTS=(\(.*\))$/\1/p' "$SRC/install.sh"); do
  if [ -e ~/.claude/agents/$name ]; then
    mkdir -p "$BK/agents" && cp ~/.claude/agents/$name "$BK/agents/"
    rm -f ~/.claude/agents/$name
    echo "  removed retired agents/$name"
  fi
done
# back up + copy rules
for f in "$SRC"/global/rules/*.md; do
  b=$(basename "$f"); [ -e ~/.claude/rules/$b ] && mkdir -p "$BK/rules" && cp ~/.claude/rules/$b "$BK/rules/"
  cp "$f" ~/.claude/rules/$b
done
# update-check hook
[ -e ~/.claude/hooks/stack-update-check.sh ] && mkdir -p "$BK/hooks" && cp ~/.claude/hooks/stack-update-check.sh "$BK/hooks/"
cp "$SRC/hooks/stack-update-check.sh" ~/.claude/hooks/stack-update-check.sh
chmod +x ~/.claude/hooks/stack-update-check.sh
# stamp the state dir so the update check has a SHA to compare against —
# skip if $SRC isn't a git checkout (e.g. a tarball); the check then stays
# permanently silent, which is correct with nothing to compare against
if INSTALLED_SHA=$(git -C "$SRC" rev-parse HEAD 2>/dev/null); then
  mkdir -p ~/.claude/.claude-code-setup
  echo "$INSTALLED_SHA" > ~/.claude/.claude-code-setup/installed
  # only on the branch where CLAUDE.md was actually copied, see below
else
  echo "  $SRC is not a git checkout — skipping update-check stamp (check stays disabled)"
fi
```
Then merge settings keys per the user's choices (preserve everything else).
The teammate flag + `teammateMode` go in **only if they chose the teammate
path**; `ANTHROPIC_DEFAULT_OPUS_MODEL` is set to **the Opus version they picked
in Step 1** (never overwritten if already present; leave it out entirely if
they chose *don't pin*). Skip entirely if they chose neither:
```bash
python3 - "$SRC/settings.example.json" <<'PY'
import json, os, sys
WANT_TEAMMATES = True            # set per the user's Step 1 answers
OPUS_PIN = "claude-opus-5"       # their chosen version, or None for "don't pin"
ex = json.load(open(sys.argv[1]))
p = os.path.expanduser("~/.claude/settings.json")
d = json.load(open(p)) if os.path.exists(p) else {}
if os.path.exists(p): json.dump(d, open(p+".bak","w"), indent=2)
env = d.setdefault("env", {})
if WANT_TEAMMATES:
    env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = ex["env"]["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"]
    d["teammateMode"] = ex["teammateMode"]
if OPUS_PIN:
    env.setdefault("ANTHROPIC_DEFAULT_OPUS_MODEL", OPUS_PIN)
# Not teammate-gated: any worktree fan-out needs it, or executor worktrees
# branch from the remote default instead of the session's in-progress work.
d.setdefault("worktree", {}).setdefault("baseRef", ex["worktree"]["baseRef"])
# SessionStart update-check hook — append into the existing matcher-"" group
# (creating it if absent) rather than replacing the array, and match on the
# command string so a second install doesn't add a duplicate entry.
hook_path = os.path.expanduser("~/.claude/hooks/stack-update-check.sh")
hooks = d.setdefault("hooks", {})
session_start = hooks.setdefault("SessionStart", [])
group = next((g for g in session_start if g.get("matcher") == ""), None)
if group is None:
    group = {"matcher": "", "hooks": []}
    session_start.append(group)
entries = group.setdefault("hooks", [])
if not any(e.get("command") == hook_path for e in entries):
    entries.append({"type": "command", "command": hook_path, "timeout": 10})
json.dump(d, open(p,"w"), indent=2)
print("settings.json updated (backup: settings.json.bak)")
PY
```

**CLAUDE.md** (per the chosen handling):
- *none exists* → `cp "$SRC/global/CLAUDE.md" ~/.claude/CLAUDE.md`
- *append* → add this repo's `## Feature workflow` pointer section to
  the end of the user's `~/.claude/CLAUDE.md` (copy it verbatim from
  `$SRC/global/CLAUDE.md`; the full workflow lives in the installed
  `feature-workflow` skill). Don't duplicate it if already present.
- *replace* → back up to `$BK`, then copy.
- *leave* → do nothing.

Only on the *none exists* and *replace* branches (a full copy, not the
partial *append*), and only if `INSTALLED_SHA` was set above, also stamp
`echo "$INSTALLED_SHA" > ~/.claude/.claude-code-setup/claude-md-installed` —
this is the SHA whose `global/CLAUDE.md` the user actually accepted, distinct
from `installed`, so a later declined `/stack-update` merge doesn't get
silently marked as applied.

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

Also mention: a `SessionStart` hook now checks once a day for a newer
`claude-code-setup` and prints one line if there's an update — `/stack-update`
applies it, and nothing is written without approval. Opt out with
`touch ~/.claude/.claude-code-setup/disabled`.

**Optional teammate path only** (skip unless they installed it — cannot be automated):
1. **Enable panes:** set `"teammateMode": "iterm2"` in `~/.claude/settings.json`.
   The installer leaves it at `"in-process"` (teammates in the status bar, no
   panes); `"iterm2"` is what renders them as split panes. (Panes don't
   self-close — `Cmd-W` a pane's tab to close it when done.)
2. **Quit iTerm2 (Cmd+Q) and reopen** — activates the API server. Approve the
   one-time "allow Python API" dialog on first team spawn.
3. **Restart Claude Code** — cold start, inside iTerm2, so the flag,
   `teammateMode`, skill, and agents all load. Don't `--resume`.
4. **`/config` → Default teammate model → Sonnet** (token-efficient floor;
   per-role models in the agent files override it).

## Rules

- Never overwrite `~/.claude/CLAUDE.md` or `settings.json` without a backup.
- Skip anything already installed — say "already present" and move on.
- Report a final summary: what was installed, what was skipped, what's manual.
