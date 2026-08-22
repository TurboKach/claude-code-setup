#!/usr/bin/env bash
# Frontmatter hooks for the codex-runner agent (agents/codex-runner.md).
# Two modes, selected by $1, hook JSON read from stdin:
#   pre-bash — PreToolUse on Bash: denies a Bash call with
#              tool_input.run_in_background:true (exit 2, reason on stderr).
#   stop     — Stop (auto-converted to SubagentStop for a subagent): blocks
#              the turn from ending while a `codex exec` process is still
#              running, by printing {"decision":"block","reason":"..."} to
#              stdout.
# Malformed/empty stdin never blocks: it is treated as allow (exit 0) so a
# hook crash can never strand the runner. stop_hook_active is deliberately
# not consulted here — the 8-consecutive-block override is the safety valve;
# a still-running codex should keep blocking every time it's checked.
#
# Known limitation: `pgrep -f "codex exec"` is process-wide, not scoped to
# this agent's own PID tree, so a sibling runner's codex process also blocks
# this runner's stop. That degrades to an extra wait, never to a lost verdict.
set -u

mode="${1:-}"
input="$(cat)"

case "$mode" in
  pre-bash)
    result="$(printf '%s' "$input" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    print("allow")
    sys.exit(0)
if data.get("tool_name") != "Bash":
    print("allow")
    sys.exit(0)
tool_input = data.get("tool_input") or {}
if tool_input.get("run_in_background") is True:
    print("deny")
else:
    print("allow")
' 2>/dev/null)"
    if [ "$result" = "deny" ]; then
      echo "codex-runner: run_in_background is not allowed here — a subagent that ends its turn is never re-woken by its own background task. Re-issue this command as a foreground Bash call with timeout 600000; if the harness later moves it to the background at the timeout, re-wait in the foreground with: until grep -q DONE_EXIT_ <codex-err file>; do sleep 10; done" >&2
      exit 2
    fi
    exit 0
    ;;
  stop)
    if pgrep -f "codex exec" >/dev/null 2>&1; then
      python3 -c '
import json
reason = ("A codex exec process is still running, so this turn must not end. "
          "Issue a foreground Bash wait (timeout 600000): "
          "until grep -q DONE_EXIT_ <the codex-err file the skill printed>; do sleep 10; done "
          "-- then Read the codex output file and return the triaged verdict. "
          "Do not summarize partial output.")
print(json.dumps({"decision": "block", "reason": reason}))
'
    fi
    exit 0
    ;;
  *)
    echo "usage: codex-runner-hooks.sh {pre-bash|stop}  (JSON on stdin)" >&2
    exit 1
    ;;
esac
