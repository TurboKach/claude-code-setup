#!/usr/bin/env bash
# SessionStart hook: names the session from its repo, so sessions in sibling
# repos of one project find each other in ListAgents and the name survives a
# plan's acceptance. The repo declares it with a line in its CLAUDE.md (or
# .claude/CLAUDE.md) at the project root:
#
#   Session name: `acme-ios`
#
# A name already set (--name, /rename) is never overwritten. stdout is
# injected into the session's context, so this prints the sessionTitle JSON
# and nothing else — and nothing at all when it doesn't name the session.
# Always exit 0, stderr silenced, no network.
set -u

command -v python3 >/dev/null 2>&1 || exit 0
input="$(cat)"

# The script goes in via -c (single-quoted: no apostrophes inside), not a
# heredoc — a heredoc would take over python's stdin. -I: no cwd on sys.path,
# so a json.py in the repo is never imported.
printf '%s' "$input" | python3 -I -c '
import json, os, re, subprocess, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if not isinstance(data, dict) or data.get("session_title"):
    sys.exit(0)
if data.get("source") not in ("startup", "resume", "fork"):
    sys.exit(0)
cwd = data.get("cwd")
if not isinstance(cwd, str) or not cwd:
    sys.exit(0)

try:
    root = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True, timeout=3).stdout.strip() or cwd
except Exception:
    root = cwd

LINE = re.compile(r"^Session name:\s*(.*?)\s*$")
SLUG = re.compile(r"`?([A-Za-z0-9][A-Za-z0-9_-]*)`?")
for path in (os.path.join(root, "CLAUDE.md"), os.path.join(root, ".claude", "CLAUDE.md")):
    # Regular files only (a symlink to one is fine), first 1 MB: a FIFO would
    # block the open, /dev/zero would never end the read.
    if not os.path.isfile(path):
        continue
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read(1 << 20).splitlines()
    except OSError:
        continue
    for line in lines:
        m = LINE.match(line)
        if not m:
            continue
        # First matching line wins, valid or not; backticks must pair.
        v = m.group(1)
        s = SLUG.fullmatch(v)
        if s and v.startswith("`") == v.endswith("`"):
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "SessionStart", "sessionTitle": s.group(1)}}))
        sys.exit(0)
' 2>/dev/null
exit 0
