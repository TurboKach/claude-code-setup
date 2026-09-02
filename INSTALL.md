# Install wizard (agent-facing)

> **You are Claude Code, running this install for the user.** Follow these steps
> as an **interactive wizard**. Detect what's already present, ask before
> installing anything optional or heavy, never overwrite without a backup, and
> keep questions to a minimum — skip anything already satisfied. `SRC` below is
> the directory you cloned this repo into.

## Step 0 — Detect (don't install anything yet)

Run these and show the user a short status summary:

```bash
claude --version                                  # need >= 2.1.186 (background permission prompts)
ls -d ~/.claude/skills/gstack 2>/dev/null && echo "gstack: present" || echo "gstack: missing"
command -v codex >/dev/null && { command -v gtimeout || command -v timeout; } >/dev/null && codex exec --help 2>/dev/null | grep -q -- --ephemeral && echo "codex gate: ready" || echo "codex gate: needs codex-cli + GNU timeout (macOS: brew install coreutils)"
test -f ~/.claude/CLAUDE.md && echo "CLAUDE.md: exists" || echo "CLAUDE.md: none"
```

- If `claude --version` is older than 2.1.186: suggest updating Claude Code —
  before 2.1.186 background subagents silently auto-denied permission prompts.
- If the codex gate line reports missing: install codex-cli + GNU timeout
  (macOS: `brew install coreutils`) — the codex gate does not run without them.

## Step 1 — Ask what to set up (AskUserQuestion)

Offer **only** items that are missing or are real decisions. The core kit
(skills + agents + the `stack-update` check — enables the default
background-subagent + Workflows path) is always installed: it's the point of
running this installer, not a choice, and `install.sh` has no flag to skip
it — so don't offer it as a deselectable option. Suggested:

1. **Optional add-ons**: gstack *(if missing)*.
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
nothing beyond the skill + agents — no flags, no extra tools. gstack is
optional — it powers `/office-hours`, `/ship`, `/context-save`
referenced by the workflow; without it, use plain git.

## Step 2 — Execute (only chosen + only missing)

**Core kit + settings + `CLAUDE.md`** — all of it is `install.sh`'s job now;
don't reimplement any of its copy/backup/prune/merge logic here. Its settings
merge setdefaults `CLAUDE_CODE_ENABLE_TODO_TOOLS` (the task-list feature)
along with every other key in `settings.example.json`'s `env` block — added
only if that key isn't already set, never clobbering your existing value.
Translate the Step 1 answers into flags and run it once:

- **Opus answer was *claude-opus-5*, or the question was skipped because a
  pin already exists** → pass neither `--opus-pin` nor `--no-opus-pin` (the
  default already `setdefault`s `claude-opus-5` and never clobbers an
  existing value).
- **Opus answer was *claude-opus-4-8* or a custom ID** → `--opus-pin=<that id>`.
- **Opus answer was *don't pin*** → `--no-opus-pin`.
- **`~/.claude/CLAUDE.md` didn't exist** → pass no `--claude-md` flag (the
  default installs it).
- **CLAUDE.md handling was *append*** → `--claude-md=append`.
- **CLAUDE.md handling was *replace*** → `--claude-md=replace`.
- **CLAUDE.md handling was *leave mine untouched*** → `--claude-md=leave`.

For example, a user who wants to append the Feature workflow section to
their existing `CLAUDE.md`:
```bash
"$SRC/install.sh" --claude-md=append
```

Run it and show the output — it reports what it backed up, installed,
pruned, and merged (skills, agents, rules, the update-check hook and its
stamp, retired-agent removal, and the `settings.json` merge). **If it exits
non-zero, stop** — report exactly what it printed; nothing after that point
in its output was applied.

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

## Rules

- Never overwrite `~/.claude/CLAUDE.md` or `settings.json` without a backup.
- Skip anything already installed — say "already present" and move on.
- Report a final summary: what was installed, what was skipped, what's manual.
