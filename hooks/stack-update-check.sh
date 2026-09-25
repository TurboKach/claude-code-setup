#!/usr/bin/env bash
# SessionStart hook: notice-only check for a newer claude-code-setup on the
# remote branch. Plain stdout reaches only Claude's context, so an update is
# printed as JSON whose systemMessage is shown to the user. It must print
# nothing at all unless there is news, and it must never break or slow a
# session start (always exit 0, stderr silenced, hard network timeout via
# `curl -m` since `git ls-remote` has no timeout and macOS ships no
# `timeout(1)`). The steps' timeouts sum to 3 + 2 = 5s, under the 10s hook
# timeout install.sh registers.

STATE="${CLAUDE_HOME:-$HOME/.claude}/.claude-code-setup"

is_sha() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }  # full, exact SHA — no partial/trailing-junk matches
# slurp <var> <file>: the file's text minus trailing newlines, as $(cat) gives it
slurp() {
  local v=
  IFS= read -r -d '' v 2>/dev/null < "$2"
  while [[ "$v" == *$'\n' ]]; do v="${v%$'\n'}"; done
  printf -v "$1" %s "$v"
}

# notify <remote-sha> <count or ->: the update notice, to the user
# and to Claude. The user's copy comes from $STATE/notice when present — one
# line in the user's language, written by /stack-update, with {n} {from} {to}
# filled in here — and is the only interpolated text that needs JSON escaping.
notify() {
  local what="update available" n="?"
  case "$2" in ''|*[!0-9]*|0) ;; 1) what="1 new change" n=1 ;; *) what="$2 new changes" n="$2" ;; esac
  local msg="claude-code-setup: $what (installed ${installed:0:7} → remote ${1:0:7}) — run /stack-update"
  local user="$msg" tpl
  IFS= read -r tpl 2>/dev/null < "$STATE/notice"
  tpl="${tpl//[[:cntrl:]]/}"
  if [ -n "$tpl" ]; then
    tpl="${tpl//\\/\\\\}"; tpl="${tpl//\"/\\\"}"
    tpl="${tpl//\{n\}/$n}"; tpl="${tpl//\{from\}/${installed:0:7}}"; tpl="${tpl//\{to\}/${1:0:7}}"
    user="claude-code-setup: $tpl"
  fi
  printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' \
    "$user" "$msg"
}

slurp installed "$STATE/installed"
is_sha "$installed" || exit 0          # not installed via install.sh, or corrupt stamp — opt out
[ -e "$STATE/disabled" ] && exit 0     # explicitly turned off

slurp last_check "$STATE/last-check"
case "$last_check" in
  *[!0-9]*|'') last_check=0 ;;   # corrupt stamp — treat as never checked
esac
now="${EPOCHSECONDS:-$(date +%s)}"
# Stamp before the network call: an offline machine must not pay the curl
# timeout on every single session start. Cost: an update found while offline
# surfaces up to a day later — the right trade for a startup hook. If the stamp
# can't be written, skip the network too, or every session would pay the curl
# timeout instead of just this one.
if [ $((now - 10#$last_check)) -ge 86400 ] \
  && { echo "$now" > "$STATE/last-check"; } 2>/dev/null; then  # 10# forces base-10: no leading-zero-as-octal trap
  remote="$(curl -sfm 3 -H 'Accept: application/vnd.github.sha' \
    "https://api.github.com/repos/TurboKach/claude-code-setup/commits/master" 2>/dev/null)"
  if is_sha "$remote"; then
    { echo "$installed $remote -" > "$STATE/remote"; } 2>/dev/null
    if [ "$remote" != "$installed" ]; then
      # How many commits behind. A second call, only when there is news: the
      # compare body carries file patches (100 KB+). 0 means the install is
      # ahead of the remote — nothing to update. Unknown to GitHub (404) or
      # timed out → no count, the notice still shows.
      count="$(curl -sfm 2 "https://api.github.com/repos/TurboKach/claude-code-setup/compare/${installed}...${remote}?per_page=1" 2>/dev/null \
        | grep -oE '"ahead_by": *[0-9]+' | head -1 | grep -oE '[0-9]+$')"
      [ -n "$count" ] && { echo "$installed $remote $count" > "$STATE/remote"; } 2>/dev/null
    fi
  fi
fi

# Replay the last successful poll — this run's, or an earlier one's when this
# poll failed offline — so a known update shows at every session start until it
# is installed, as long as it was measured against this install. The count
# field must be `-` or digits: an older 2- or 4-field cache stays silent.
read -r polled_for remote count 2>/dev/null < "$STATE/remote"
if [ "$polled_for" = "$installed" ] && is_sha "$remote" && [ "$remote" != "$installed" ] \
  && [[ "$count" =~ ^(-|[0-9]+)$ ]] && [ "$count" != 0 ]; then
  notify "$remote" "$count"
fi
exit 0
