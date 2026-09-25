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

is_sha() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }  # full, exact SHA — no partial/trailing-junk matches

# notify <remote-sha> [context]: the update notice, to the user and to Claude.
# Nothing interpolated here can hold a quote or backslash, so no JSON escaping.
notify() {
  local msg="claude-code-setup: update available (installed ${installed:0:7} → remote ${1:0:7}) — run /stack-update"
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s%s"}}\n' \
    "$msg" "${2:+$2\\n}" "$msg"
}

installed="$(cat "$STATE/installed" 2>/dev/null)"
is_sha "$installed" || exit 0          # not installed via install.sh, or corrupt stamp — opt out
[ -e "$STATE/disabled" ] && exit 0     # explicitly turned off

last_check="$(cat "$STATE/last-check" 2>/dev/null || echo 0)"
case "$last_check" in
  *[!0-9]*|'') last_check=0 ;;   # corrupt stamp — treat as never checked
esac
now="$(date +%s)"
if [ $((now - 10#$last_check)) -lt 86400 ]; then  # 10# forces base-10: no leading-zero-as-octal trap
  # Replay the last poll offline, so a known update shows at every session
  # start, not only the first of the day — but only while the install it was
  # measured against is still the installed one.
  read -r polled_for remote 2>/dev/null < "$STATE/remote"
  [ "$polled_for" = "$installed" ] && is_sha "$remote" && [ "$remote" != "$installed" ] && notify "$remote"
  exit 0
fi

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
drift=""
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
  { echo "$installed $remote" > "$STATE/remote"; } 2>/dev/null
  [ "$remote" != "$installed" ] && { notify "$remote" "$drift"; exit 0; }
fi
[ -n "$drift" ] && echo "$drift"
exit 0
