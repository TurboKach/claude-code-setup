#!/usr/bin/env bash
# SessionStart hook: notice-only check for a newer claude-code-setup on the
# remote branch. stdout is injected into the session's context, so this must
# print nothing at all unless an update is genuinely available, and it must
# never break or slow a session start (always exit 0, stderr silenced, hard
# network timeout via `curl -m` since `git ls-remote` has no timeout and
# macOS ships no `timeout(1)`).

STATE="${CLAUDE_HOME:-$HOME/.claude}/.claude-code-setup"
REPO="${CLAUDE_SETUP_REPO:-TurboKach/claude-code-setup}"
BRANCH="${CLAUDE_SETUP_BRANCH:-master}"

installed="$(cat "$STATE/installed" 2>/dev/null)"
[ -n "$installed" ] || exit 0          # not installed via install.sh — opt-out for hand-copiers
[ -e "$STATE/disabled" ] && exit 0     # explicitly turned off

last_check="$(cat "$STATE/last-check" 2>/dev/null || echo 0)"
now="$(date +%s)"
[ $((now - last_check)) -lt 86400 ] && exit 0  # checked within the last 24h

# Stamp before the network call: an offline machine must not pay the curl
# timeout on every single session start. Cost: an update found while offline
# surfaces up to a day later — the right trade for a startup hook.
echo "$now" > "$STATE/last-check" 2>/dev/null

remote="$(curl -sfm 4 -H 'Accept: application/vnd.github.sha' \
  "https://api.github.com/repos/${REPO}/commits/${BRANCH}" 2>/dev/null)"

case "$remote" in
  [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*) ;;
  *) exit 0 ;;  # empty or not a plausible SHA
esac
[ "$remote" = "$installed" ] && exit 0

echo "claude-code-setup: update available (installed ${installed:0:7} → remote ${remote:0:7}) — run /stack-update"
exit 0
