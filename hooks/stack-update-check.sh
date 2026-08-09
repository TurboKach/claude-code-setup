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

is_sha() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }  # full, exact SHA — no partial/trailing-junk matches

installed="$(cat "$STATE/installed" 2>/dev/null)"
is_sha "$installed" || exit 0          # not installed via install.sh, or corrupt stamp — opt out
[ -e "$STATE/disabled" ] && exit 0     # explicitly turned off

last_check="$(cat "$STATE/last-check" 2>/dev/null || echo 0)"
case "$last_check" in
  *[!0-9]*|'') last_check=0 ;;   # corrupt stamp — treat as never checked
esac
now="$(date +%s)"
[ $((now - 10#$last_check)) -lt 86400 ] && exit 0  # 10# forces base-10: no leading-zero-as-octal trap

# Stamp before the network call: an offline machine must not pay the curl
# timeout on every single session start. Cost: an update found while offline
# surfaces up to a day later — the right trade for a startup hook. If the
# state dir isn't writable, bail before the network call too, or every
# session would pay the curl timeout instead of just this one.
{ echo "$now" > "$STATE/last-check"; } 2>/dev/null || exit 0

remote="$(curl -sfm 4 -H 'Accept: application/vnd.github.sha' \
  "https://api.github.com/repos/${REPO}/commits/${BRANCH}" 2>/dev/null)"

is_sha "$remote" || exit 0  # empty or not a full SHA
[ "$remote" = "$installed" ] && exit 0

echo "claude-code-setup: update available (installed ${installed:0:7} → remote ${remote:0:7}) — run /stack-update"
exit 0
