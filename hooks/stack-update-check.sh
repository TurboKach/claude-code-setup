#!/usr/bin/env bash
# SessionStart hook: notice-only check for a newer claude-code-setup on the
# remote branch. Plain stdout reaches only Claude's context, so an update is
# printed as JSON whose systemMessage is shown to the user. It must print
# nothing at all unless there is news, and it must never break or slow a
# session start (always exit 0, stderr silenced, hard network timeout via
# `curl -m` since `git ls-remote` has no timeout and macOS ships no
# `timeout(1)`).

STATE="${CLAUDE_HOME:-$HOME/.claude}/.claude-code-setup"
REPO="${CLAUDE_SETUP_REPO:-TurboKach/claude-code-setup}"
BRANCH="${CLAUDE_SETUP_BRANCH:-master}"
SOURCE="$REPO@$BRANCH"  # a cached poll is only valid for the source it came from

is_sha() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }  # full, exact SHA — no partial/trailing-junk matches

# notify <remote-sha> <count or -> [context]: the update notice, to the user
# and to Claude. Nothing interpolated here can hold a quote or backslash, so no
# JSON escaping.
notify() {
  local what="update available"
  case "$2" in 1) what="1 new change" ;; [1-9]*) what="$2 new changes" ;; esac
  local msg="claude-code-setup: $what (installed ${installed:0:7} → remote ${1:0:7}) — run /stack-update"
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s%s"}}\n' \
    "$msg" "${3:+$3\\n}" "$msg"
}

installed="$(cat "$STATE/installed" 2>/dev/null)"
is_sha "$installed" || exit 0          # not installed via install.sh, or corrupt stamp — opt out
[ -e "$STATE/disabled" ] && exit 0     # explicitly turned off

last_check="$(cat "$STATE/last-check" 2>/dev/null || echo 0)"
case "$last_check" in
  *[!0-9]*|'') last_check=0 ;;   # corrupt stamp — treat as never checked
esac
now="$(date +%s)"
drift=""
if [ $((now - 10#$last_check)) -ge 86400 ]; then  # 10# forces base-10: no leading-zero-as-octal trap
  # Stamp before the network call: an offline machine must not pay the curl
  # timeout on every single session start. Cost: an update found while offline
  # surfaces up to a day later — the right trade for a startup hook. If the
  # state dir isn't writable, bail before the network call too, or every
  # session would pay the curl timeout instead of just this one.
  { echo "$now" > "$STATE/last-check"; } 2>/dev/null || exit 0

  # Doctrine-vs-harness drift. The kit's rules encode version-dependent harness
  # behavior; install.sh stamps the version docs/references.md was last validated
  # against. One line when the running Claude Code differs — the changelog diff
  # itself stays a manual, discussed step. `claude --version` starts node, so it
  # sits behind the once-a-day gate above and under gtimeout where available.
  validated="$(cat "$STATE/validated-cc-version" 2>/dev/null)"
  if [[ "$validated" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
    to="$(command -v gtimeout || command -v timeout)" 2>/dev/null
    running="$(${to:+"$to" 5} claude --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
    if [ -n "$running" ] && [ "$running" != "$validated" ]; then
      drift="claude-code-setup: Claude Code $running is running, doctrine last validated against $validated — diff the changelog $validated → $running before the next pipeline change"
    fi
  fi

  remote="$(curl -sfm 4 -H 'Accept: application/vnd.github.sha' \
    "https://api.github.com/repos/${REPO}/commits/${BRANCH}" 2>/dev/null)"
  if is_sha "$remote"; then
    { echo "$installed $SOURCE $remote -" > "$STATE/remote"; } 2>/dev/null
    if [ "$remote" != "$installed" ]; then
      # How many commits behind. A second call, only when there is news: the
      # compare body carries file patches (100 KB+). 0 means the install is
      # ahead of the remote — nothing to update. Unknown to GitHub (404) or
      # timed out → no count, the notice still shows.
      count="$(curl -sfm 3 "https://api.github.com/repos/${REPO}/compare/${installed}...${remote}?per_page=1" 2>/dev/null \
        | grep -oE '"ahead_by": *[0-9]+' | head -1 | grep -oE '[0-9]+$')"
      [ -n "$count" ] && { echo "$installed $SOURCE $remote $count" > "$STATE/remote"; } 2>/dev/null
    fi
  fi
fi

# Replay the last successful poll — this run's, or an earlier one's when this
# poll failed offline — so a known update shows at every session start until it
# is installed, as long as it was measured against this install and source.
read -r polled_for polled_src remote count 2>/dev/null < "$STATE/remote"
if [ "$polled_for" = "$installed" ] && [ "$polled_src" = "$SOURCE" ] && is_sha "$remote" \
  && [ "$remote" != "$installed" ] && [ "$count" != 0 ]; then
  notify "$remote" "$count" "$drift"
  exit 0
fi
[ -n "$drift" ] && echo "$drift"
exit 0
