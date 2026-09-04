#!/usr/bin/env bash
# PreToolUse hook on Bash (settings.example.json registers it; install.sh
# merges it). Hook JSON on stdin; a deny is printed as the documented
# hookSpecificOutput JSON on stdout, exit 0. Two rules:
#
#   A. run_in_background:true inside a subagent (hook input carries agent_id
#      only there) is denied. With fork mode on — the interactive default
#      since 2.1.232 — every spawn is a background subagent, and the docs
#      (tools-reference, "Background commands") say a background subagent's
#      background commands keep running past its final response; 2.1.260
#      removed the one-hour cap. The master keeps run_in_background: the
#      codex run and the full suite live there by doctrine.
#   B. a poll loop on a <task>.output.done marker is denied everywhere: the
#      harness never writes that file, so the loop runs until its timeout or
#      forever — and a foreground one is auto-backgrounded at the timeout,
#      which rule A cannot see. Only an executed loop matches: quoted text
#      is stripped first and the loop keyword must sit at a command boundary,
#      so an echo, a commit message or a grep that mentions the loop is
#      allowed. Known gaps, accepted: a loop inside `bash -c "…"` is quoted
#      and passes; a heredoc body line that starts with the loop is denied.
#
# Why: 2026-09-04 clipsy_ios arc — a fixer's `xcodebuild test` (no timeout)
# was auto-backgrounded at the 2-min default; its `sleep 90; tail` was blocked
# with "use Monitor with an until-loop", a tool the agent's tools: list
# strips; so it ran `until [ -f <task>.output.done ]; do sleep 5; done` in
# the background, and that loop outlived the agent's report by 54 minutes.
# Across 8 sessions since 2026-08-25: 25 subagents auto-backgrounded, 16 hit
# the sleep block, 2 orphaned pollers. The agent-definition line asking for
# an explicit timeout was ignored in ~30 of ~40 calls — prose does not hold.
#
# Fail-open: empty or malformed stdin, a missing python3, or any other tool
# name produces no output and exit 0, so a hook fault can never strand a run.
set -u

command -v python3 >/dev/null 2>&1 || exit 0
input="$(cat)"

# The script goes in via -c (single-quoted: no apostrophes inside), not a
# heredoc — a heredoc would take over python's stdin and the hook JSON would
# never reach json.load(sys.stdin).
printf '%s' "$input" | python3 -c '
import json, re, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(data, dict) or data.get("tool_name") != "Bash":
    sys.exit(0)
tool_input = data.get("tool_input") or {}
if not isinstance(tool_input, dict):
    sys.exit(0)
command = tool_input.get("command") or ""
in_subagent = bool(data.get("agent_id"))

WAIT = ("wait in the foreground on the process itself: `until ! pgrep -f "
        "<pattern> >/dev/null; do sleep 10; done` under its own `timeout` sized to "
        "the run, then read the task .output file. Bracket the first letter of the "
        "pattern (`[x]codebuild`) so pgrep cannot match its own command line.")

def polls_marker(cmd):
    # Only a loop that would execute counts: drop quoted text first (an echo,
    # a commit message, a doc line mentioning the loop is not a poll), then
    # require the loop keyword at a command boundary — start of command, or
    # after ; & | newline ( { — and the marker somewhere in that loop head.
    stripped = re.sub(r"\"[^\"]*\"|\x27[^\x27]*\x27", "", cmd)
    return re.search(r"(?:^|[;&|(){}\n])\s*(until|while)\b[^;\n]*output\.done",
                     stripped) is not None

reason = None
if polls_marker(command):
    reason = ("Denied: no `.output.done` marker is ever written for a background task, "
              "so this loop never ends. To wait for a command that was auto-backgrounded, "
              + WAIT + " Better: give the command itself a `timeout` sized to the run so "
              "it is never backgrounded.")
elif in_subagent and tool_input.get("run_in_background") is True:
    reason = ("Denied: subagents never background commands. You run as a background "
              "subagent, and background commands started by a background subagent keep "
              "running after its final report with nobody left to stop them "
              "(tools-reference, Background commands). Run the command in the foreground "
              "with an explicit `timeout` sized to the run (the default is 15 min; past "
              "its timeout a simple command is auto-backgrounded and a pipeline is "
              "killed). If a command was already auto-backgrounded, " + WAIT +
              " Never poll for a `.output.done` marker; none is written.")

if reason:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
' 2>/dev/null
exit 0
