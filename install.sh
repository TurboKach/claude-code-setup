#!/usr/bin/env bash
set -euo pipefail

# Claude Code parallel-multi-agent starter kit installer.
# Copies CLAUDE.md, the agent-teams skill, and the team-* agents into ~/.claude,
# backing up anything it would overwrite. The kit's default path (background
# subagents + Workflows) needs nothing else. This also merges the settings keys
# from settings.example.json: every key in that file's "env" block, added only
# if you haven't set your own value (CLAUDE_CODE_ENABLE_TODO_TOOLS for the task-list feature, the Sonnet
# subagent floor, BASH_DEFAULT_TIMEOUT_MS=900000 so a build or test run
# with no explicit timeout is not auto-backgrounded at 2 minutes, and
# CODEX_REVIEW_MODEL / CODEX_REVIEW_EFFORT for the codex cross-review gate),
# plus bashOutputMaxChars=30000 (a valid command result over 30k characters
# arrives as a file path + 2k preview instead of flooding the context; 2.1.261+) and
# bashEditDiffEnabled=true (the transcript records which files each Bash
# command changed, in every permission mode; /analyze-arcs reads it; 2.1.269+).
# The master model (settings "model" + "modelSettings") is written only on an
# explicit --master answer; with no flag it is left alone and a one-line notice
# points at the recommendation when your settings don't already match it —
# unless --master=dont-ask recorded that recommendation in
# .claude-code-setup/master-dont-ask (a changed recommendation asks again).
# It also
# installs two hooks: a SessionStart hook that checks once a day whether this
# repo has moved past the SHA you installed (and stamps that SHA so the check
# has something to compare against), and a PreToolUse hook on Bash that denies
# run_in_background inside subagents — see hooks/subagent-no-background.sh.
#
# Flags (all optional — no flags reproduces the behavior above exactly; see
# --help). INSTALL.md's interactive wizard drives this script with them instead
# of reimplementing any of the above by hand.

usage() {
  cat <<EOF
Usage: install.sh [--opus-pin=MODEL_ID | --no-opus-pin] [--codex-model=MODEL_ID] [--claude-md=append|replace|leave]
                  [--master=recommended|keep|dont-ask|MODEL_ID[:EFFORT]]

No flags: leave the "opus" alias unpinned (it follows the latest Opus), install
CLAUDE.md only if none exists yet, and leave the master model untouched.

  --opus-pin=MODEL_ID    Setdefault ANTHROPIC_DEFAULT_OPUS_MODEL to MODEL_ID (never
                         clobbers an existing value).
  --no-opus-pin          Don't set ANTHROPIC_DEFAULT_OPUS_MODEL (the default).
  --codex-model=MODEL_ID Setdefault CODEX_REVIEW_MODEL to MODEL_ID instead of the repo
                         default (never clobbers an existing value).
  --claude-md=append     Append this repo's Feature workflow section to an existing
                         ~/.claude/CLAUDE.md (no-op if that section is already there).
  --claude-md=replace    Back up and overwrite ~/.claude/CLAUDE.md with this repo's copy.
  --claude-md=leave      Leave an existing ~/.claude/CLAUDE.md untouched.
  --master=recommended   Write settings.example.json's "model" and each
                         modelSettings.<id>.effortLevel, overwriting existing values.
  --master=keep          Leave "model" and "modelSettings" untouched (no notice this run).
  --master=dont-ask      Same as keep, and record the current recommendation in
                         .claude-code-setup/master-dont-ask so no-flag runs stop
                         printing the notice until the recommendation changes.
  --master=MODEL_ID[:EFFORT]
                         Write "model" = MODEL_ID and, with EFFORT (low, medium, high,
                         xhigh), modelSettings.MODEL_ID.effortLevel = EFFORT.
                         recommended and MODEL_ID[:EFFORT] clear master-dont-ask.
EOF
}

OPUS_PIN=""
OPUS_PIN_SET=0
OPUS_SKIP=0
CODEX_MODEL=""
CODEX_MODEL_SET=0
CLAUDE_MD_MODE="auto"
MASTER=""
MASTER_SET=0

for arg in "$@"; do
  case "$arg" in
    --opus-pin=*) OPUS_PIN="${arg#--opus-pin=}"; OPUS_PIN_SET=1 ;;
    --no-opus-pin) OPUS_SKIP=1 ;;
    --codex-model=*) CODEX_MODEL="${arg#--codex-model=}"; CODEX_MODEL_SET=1 ;;
    --claude-md=*) CLAUDE_MD_MODE="${arg#--claude-md=}" ;;
    --master=*) MASTER="${arg#--master=}"; MASTER_SET=1 ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "install.sh: unrecognized flag: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

case "$CLAUDE_MD_MODE" in
  auto|append|replace|leave) ;;
  *)
    echo "install.sh: invalid --claude-md value: '$CLAUDE_MD_MODE' (expected append, replace, or leave)" >&2
    exit 1
    ;;
esac

if [ "$OPUS_PIN_SET" = 1 ] && [ "$OPUS_SKIP" = 1 ]; then
  echo "install.sh: --opus-pin and --no-opus-pin are mutually exclusive" >&2
  exit 1
fi

if [ "$OPUS_PIN_SET" = 1 ] && [ -z "$OPUS_PIN" ]; then
  echo "install.sh: --opus-pin requires a non-empty MODEL_ID" >&2
  exit 1
fi

if [ "$CODEX_MODEL_SET" = 1 ] && [ -z "$CODEX_MODEL" ]; then
  echo "install.sh: --codex-model requires a non-empty MODEL_ID" >&2
  exit 1
fi

# --master → mode (none|recommended|keep|dont-ask|model) plus MODEL_ID and optional EFFORT.
MASTER_MODE="none"
MASTER_MODEL=""
MASTER_EFFORT=""
if [ "$MASTER_SET" = 1 ]; then
  case "$MASTER" in
    recommended|keep|dont-ask) MASTER_MODE="$MASTER" ;;
    *)
      MASTER_MODE="model"
      MASTER_MODEL="${MASTER%%:*}"
      if [ -z "$MASTER_MODEL" ]; then
        echo "install.sh: --master requires recommended, keep, dont-ask, or a non-empty MODEL_ID[:EFFORT]" >&2
        exit 1
      fi
      if [ "$MASTER_MODEL" != "$MASTER" ]; then
        MASTER_EFFORT="${MASTER#*:}"
        case "$MASTER_EFFORT" in
          low|medium|high|xhigh) ;;
          max)
            echo "install.sh: --master effort max can't be saved as a default — Claude Code applies max to the current session only; use /effort max in a session or set CLAUDE_CODE_EFFORT_LEVEL=max" >&2
            exit 1
            ;;
          *)
            echo "install.sh: invalid --master effort: '$MASTER_EFFORT' (expected low, medium, high, or xhigh)" >&2
            exit 1
            ;;
        esac
      fi
      ;;
  esac
fi

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${CLAUDE_HOME:-$HOME/.claude}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$DEST/.backup-$STAMP"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

mkdir -p "$DEST/agents" "$DEST/skills" "$DEST/rules"

backup() { # $1 = path under DEST
  if [ -e "$DEST/$1" ]; then
    mkdir -p "$BACKUP/$(dirname "$1")"
    cp -R "$DEST/$1" "$BACKUP/$1"
    echo "  backed up $1"
  fi
}

say "Installing into $DEST (backups -> $BACKUP)"

# CLAUDE.md — mode defaults to "auto": copy if absent, else leave untouched
# (never clobber an existing personal one). --claude-md=append/replace/leave
# overrides that per-run.
# (The source lives at global/CLAUDE.md so sessions in this repo don't load it
# twice — a repo-root CLAUDE.md would duplicate ~/.claude/CLAUDE.md in context.)
CLAUDE_MD_INSTALLED=0
case "$CLAUDE_MD_MODE" in
  leave)
    echo "  CLAUDE.md: left untouched (--claude-md=leave)"
    ;;
  replace)
    backup "CLAUDE.md"
    cp "$SRC/global/CLAUDE.md" "$DEST/CLAUDE.md"; echo "  installed CLAUDE.md (replaced)"
    CLAUDE_MD_INSTALLED=1
    ;;
  append)
    if [ ! -e "$DEST/CLAUDE.md" ]; then
      cp "$SRC/global/CLAUDE.md" "$DEST/CLAUDE.md"; echo "  installed CLAUDE.md (none existed — nothing to append to)"
      CLAUDE_MD_INSTALLED=1
    elif awk '{ sub(/\r$/, "") } /^## Feature workflow$/ { found = 1 } END { exit !found }' \
        "$DEST/CLAUDE.md" 2>/dev/null; then
      echo "  $DEST/CLAUDE.md already has a line matching '## Feature workflow' — append skipped." \
           "(This matches even inside a code fence, so if that line is just an example rather than" \
           "a real section, the file wasn't actually appended to — remove the false match or use" \
           "--claude-md=replace instead.)"
    else
      if ! grep -q '^## Feature workflow$' "$SRC/global/CLAUDE.md"; then
        echo "install.sh: couldn't find a '## Feature workflow' section in $SRC/global/CLAUDE.md — aborting append (nothing changed)" >&2
        exit 1
      fi
      backup "CLAUDE.md"
      { printf '\n'; awk '
          /^## Feature workflow$/ {flag=1}
          flag && /^## / && !/^## Feature workflow$/ {exit}
          flag {print}
        ' "$SRC/global/CLAUDE.md"; } >> "$DEST/CLAUDE.md"
      echo "  appended the Feature workflow section to CLAUDE.md"
    fi
    ;;
  *) # auto — today's default behavior
    if [ -e "$DEST/CLAUDE.md" ]; then
      echo "  $DEST/CLAUDE.md exists — left untouched. Merge from $SRC/global/CLAUDE.md by hand if you want it."
    else
      cp "$SRC/global/CLAUDE.md" "$DEST/CLAUDE.md"; echo "  installed CLAUDE.md"
      CLAUDE_MD_INSTALLED=1
    fi
    ;;
esac

# Skills — back up then replace.
for skill in agent-teams feature-workflow stack-update analyze-arcs; do
  backup "skills/$skill"
  rm -rf "$DEST/skills/$skill"
  cp -R "$SRC/skills/$skill" "$DEST/skills/$skill"
  echo "  installed skills/$skill"
done

# Rules — back up each, then copy.
for f in "$SRC"/global/rules/*.md; do
  base="rules/$(basename "$f")"
  backup "$base"
  cp "$f" "$DEST/$base"
done
echo "  installed rules"

# Agents — back up each, then copy.
for f in "$SRC"/agents/*.md; do
  base="agents/$(basename "$f")"
  backup "$base"
  cp "$f" "$DEST/$base"
done
echo "  installed agents (team-* + explorer + step-executor + fixer + codex-triage + spec-reviewer)"

# Retired agents — exact-filename removal so a re-run doesn't leave a stale
# copy behind. These names only ever shipped from this kit, so removing them
# by exact match can't touch an agent file the user wrote themselves; ~/.claude/agents
# is a shared directory and everything else in it is left alone. Add one line
# here the next time an agent is retired. This is the only copy of the list —
# INSTALL.md's wizard invokes this script rather than keeping its own.
RETIRED_AGENTS=(team-prompt-smith.md codex-runner.md team-planner.md)
for name in "${RETIRED_AGENTS[@]}"; do
  base="agents/$name"
  if [ -e "$DEST/$base" ]; then
    backup "$base"
    rm -f "$DEST/$base"
    echo "  removed retired $base"
  fi
done

# Hooks — back up then replace, one loop over every hooks/*.sh (the glob
# doesn't descend into hooks/tests/, so those never get installed).
mkdir -p "$DEST/hooks"
for f in "$SRC"/hooks/*.sh; do
  base="hooks/$(basename "$f")"
  backup "$base"
  cp "$f" "$DEST/$base"
  chmod +x "$DEST/$base"
  echo "  installed $base"
done
# Retired hooks — same exact-filename rule as retired agents.
for name in codex-runner-hooks.sh; do
  base="hooks/$name"
  if [ -e "$DEST/$base" ]; then
    backup "$base"
    rm -f "$DEST/$base"
    echo "  removed retired $base"
  fi
done

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

# Stamp the Claude Code version the doctrine was last validated against (the
# header line in docs/references.md), so the SessionStart hook can notice when
# the running harness has moved past it. No git needed.
if VALIDATED="$(grep -oE 'validated against Claude Code v[0-9]+(\.[0-9]+)+' "$SRC/docs/references.md" 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)+')"; then
  mkdir -p "$DEST/.claude-code-setup"
  echo "$VALIDATED" > "$DEST/.claude-code-setup/validated-cc-version"
  echo "  stamped .claude-code-setup/validated-cc-version ($VALIDATED)"
fi

# settings.json — merge the example keys, preserving everything else.
# The Opus pin env var is added only with --opus-pin, and only when absent
# (never clobbering a user's own pin).
SETTINGS="$DEST/settings.json"
HOOK_PATH="$DEST/hooks/stack-update-check.sh"
BG_HOOK_PATH="$DEST/hooks/subagent-no-background.sh"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$SETTINGS" "$SRC/settings.example.json" "$HOOK_PATH" "$DEST" "$OPUS_PIN_SET" "$OPUS_PIN" "$OPUS_SKIP" "$BG_HOOK_PATH" "$CODEX_MODEL" "$MASTER_MODE" "$MASTER_MODEL" "$MASTER_EFFORT" <<'PY'
import json, os, sys
settings, example, hook_path, dest = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
opus_pin_set = sys.argv[5] == "1"
opus_pin = sys.argv[6]
bg_hook_path = sys.argv[8]
codex_model = sys.argv[9]
master_mode, master_model, master_effort = sys.argv[10], sys.argv[11], sys.argv[12]
ex = json.load(open(example))
if os.path.exists(settings):
    d = json.load(open(settings))
    json.dump(d, open(settings + ".bak", "w"), indent=2)  # safety copy
else:
    d = {}
env = d.setdefault("env", {})
for k, v in ex["env"].items():
    if k == "CODEX_REVIEW_MODEL" and codex_model:
        v = codex_model
    env.setdefault(k, v)  # model pins etc. — never clobber an existing choice
if not codex_model:  # the kit's earlier review models move to their successors; a user's own choice is left alone
    env["CODEX_REVIEW_MODEL"] = {"gpt-5.6-sol": "gpt-6-sol", "gpt-5.6-luna": "gpt-6-luna"}.get(env["CODEX_REVIEW_MODEL"], env["CODEX_REVIEW_MODEL"])
if opus_pin_set:
    env.setdefault("ANTHROPIC_DEFAULT_OPUS_MODEL", opus_pin)
elif env.get("ANTHROPIC_DEFAULT_OPUS_MODEL") == "claude-opus-5":  # the kit's earlier pin; a user's own choice is left alone
    del env["ANTHROPIC_DEFAULT_OPUS_MODEL"]
# Executor worktrees must branch from the session's in-progress branch, not the
# remote default — otherwise they can't see the plan file or prior units' work.
d.setdefault("worktree", {}).setdefault("baseRef", ex["worktree"]["baseRef"])
# Inline output ceiling for a valid Bash result (sizes the read-back window too; 2.1.261+).
if d.get("bashOutputMaxChars") == 64000:   # the kit's earlier value; a user's own choice is left alone
    d["bashOutputMaxChars"] = ex["bashOutputMaxChars"]
d.setdefault("bashOutputMaxChars", ex["bashOutputMaxChars"])
# Changed-file record on every Bash result, in every permission mode (analyze-arcs reads it; 2.1.269+).
d.setdefault("bashEditDiffEnabled", ex["bashEditDiffEnabled"])
# Master model — written only on an explicit --master answer (it overwrites: the user chose).
# Effort goes per model — a top-level effortLevel does not reach Opus 5.5, and
# CLAUDE_CODE_EFFORT_LEVEL would override the agents' frontmatter effort. A
# modelSettings that isn't the shape we expect is skipped with a warning, never rewritten.
master_written, master_warnings = [], []
def set_effort(mid, effort):
    ms = d.setdefault("modelSettings", {})
    if not isinstance(ms, dict):
        return master_warnings.append(f'"modelSettings" is not an object — skipped setting {mid} effort {effort}')
    entry = ms.setdefault(mid, {})
    if not isinstance(entry, dict):
        return master_warnings.append(f'"modelSettings.{mid}" is not an object — skipped setting its effort {effort}')
    entry["effortLevel"] = effort
    if "modelSettings" not in master_written:
        master_written.append("modelSettings")
if master_mode in ("recommended", "model"):
    d["model"] = ex["model"] if master_mode == "recommended" else master_model
    master_written.append("model")
    efforts = {mid: cfg["effortLevel"] for mid, cfg in ex["modelSettings"].items()} if master_mode == "recommended" \
        else ({master_model: master_effort} if master_effort else {})
    for mid, effort in efforts.items():
        set_effort(mid, effort)
    if "ANTHROPIC_MODEL" in env or "ANTHROPIC_MODEL" in os.environ:
        master_warnings.append('ANTHROPIC_MODEL is set — it outranks the settings "model" field, so the master stays on it until you unset it')
# The dont-ask record is the recommendation it was given for, so a changed recommendation asks again.
dont_ask_path = os.path.join(dest, ".claude-code-setup", "master-dont-ask")
recommendation = json.dumps({"model": ex["model"], "modelSettings": ex["modelSettings"]}, separators=(",", ":"), sort_keys=True)
if master_mode == "dont-ask":
    os.makedirs(os.path.dirname(dont_ask_path), exist_ok=True)
    open(dont_ask_path, "w").write(recommendation + "\n")
elif master_mode in ("recommended", "model") and os.path.exists(dont_ask_path):
    os.remove(dont_ask_path)
dont_ask = os.path.exists(dont_ask_path) and open(dont_ask_path).read().strip() == recommendation
master_matches = d.get("model") == ex["model"] and isinstance(d.get("modelSettings"), dict) and all(
    isinstance(d["modelSettings"].get(mid), dict) and d["modelSettings"][mid].get("effortLevel") == cfg["effortLevel"]
    for mid, cfg in ex["modelSettings"].items())

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

# Hooks — each one is appended into the existing group with its matcher
# (creating the group if absent) rather than replacing the array, so the user's
# other hooks (e.g. a peon-ping SessionStart command, or a PreToolUse group
# with a different matcher) survive untouched. If hooks/<event>/the group
# aren't the shape we expect, skip that hook's registration only — never
# rewrite a structure we don't understand, and never abort the merge.
def register_hook(event, matcher, path, timeout):
    """Returns None on success, else a one-line description of why it skipped."""
    hooks = d.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        return '"hooks" is not an object'
    groups = hooks.setdefault(event, [])
    if not isinstance(groups, list):
        return f'"hooks.{event}" is not an array'
    if not all(isinstance(g, dict) for g in groups):
        return f'"hooks.{event}" contains a non-object entry'
    group = next((g for g in groups if g.get("matcher") == matcher), None)
    if group is None:
        group = {"matcher": matcher, "hooks": []}
        groups.append(group)
    if "hooks" not in group:
        group["hooks"] = []
    entries = group["hooks"]
    if not isinstance(entries, list):
        return f'the {event} matcher-"{matcher}" group\'s "hooks" is not an array'
    target = norm_path(path)
    already_present = any(
        isinstance(e, dict) and "command" in e and norm_path(e["command"]) == target
        for e in entries
    )
    if not already_present:
        entries.append({"type": "command", "command": path, "timeout": timeout})
    return None

installed_hooks, skipped_hooks = [], []
for label, event, matcher, path, timeout in (
    ("SessionStart update-check hook", "SessionStart", "", hook_path, 10),
    ("PreToolUse subagent-no-background hook", "PreToolUse", "Bash", bg_hook_path, 5),
):
    warning = register_hook(event, matcher, path, timeout)
    (skipped_hooks if warning else installed_hooks).append((label, warning))

merged_desc = " + ".join(["env"] + master_written + ["worktree.baseRef", "bashOutputMaxChars", "bashEditDiffEnabled"])
json.dump(d, open(settings, "w"), indent=2)
for warning in master_warnings:
    print(f"  WARNING: {warning}.")
if master_mode == "none" and not master_matches and not dont_ask:
    efforts = ", ".join(f"{mid} at effort {cfg['effortLevel']}" for mid, cfg in ex["modelSettings"].items())
    print(f"  Recommended master: model \"{ex['model']}\", {efforts} — rerun with --master=recommended (or --master=dont-ask to stop this notice).")
for label, warning in skipped_hooks:
    print(f"  WARNING: settings.json's {warning} — skipped installing the {label}.")
    print(f"  Add it by hand: copy its entry from the \"hooks\" block in {example} into {settings}.")
installed = " + ".join(label for label, _ in installed_hooks)
print(f"  merged {merged_desc}{' + ' + installed if installed else ''} into settings.json (backup: settings.json.bak)")
PY
else
  echo "  python3 not found — add the keys from settings.example.json to $SETTINGS by hand"
fi

say "Files installed. The default path (background subagents + Workflows) is ready now —"
say "just restart Claude Code and ask for parallel work."

cat <<'EOF'

Recommended for the full workflow:
  - gstack for /browse (browser verification):
      git clone --single-branch --depth 1 https://github.com/garrytan/gstack.git ~/.claude/skills/gstack \
        && cd ~/.claude/skills/gstack && ./setup
EOF
