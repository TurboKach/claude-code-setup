#!/usr/bin/env bash
# SessionStart hook (matcher "compact"): after a compaction, reminds the session
# to invoke the feature-workflow skill again when it had loaded it before —
# compaction can drop an invoked skill's text entirely.
#
# Facts it relies on: a SessionStart group with matcher "compact" runs after an
# auto or manual compaction; its stdin JSON carries source and transcript_path;
# the transcript is JSONL that keeps the lines from before the compaction; a
# skill load is an assistant record whose message.content[] holds a tool_use
# block named Skill with input.skill set to the skill name. Text that only
# mentions the skill (a user message, a tool result) is not a load: each
# candidate line is parsed and its tool_use blocks checked, after a fixed-string
# prefilter on the raw bytes. The file is read line by line, never whole.
#
# stdout is injected into the session's context, so this prints one line when
# the skill was loaded and nothing otherwise. Fail-open: any error, a missing
# python3 or an unreadable transcript prints nothing. Always exit 0, stderr
# silenced.
set -u
python3 -I -c '
import json, sys

def loaded(path):
    with open(path, "rb") as f:
        for line in f:
            if b"\"name\":\"Skill\"" not in line or b"feature-workflow" not in line:
                continue
            try:
                content = json.loads(line)["message"]["content"]
            except Exception:
                continue
            if not isinstance(content, list):
                continue
            for b in content:
                if (isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Skill"
                        and isinstance(b.get("input"), dict) and b["input"].get("skill") == "feature-workflow"):
                    return True
    return False

try:
    event = json.load(sys.stdin)
    if event["source"] == "compact" and loaded(event["transcript_path"]):
        print("This session loaded the feature-workflow skill before the compaction, and compaction can drop its text: invoke the skill again before the next pipeline step.")
except Exception:
    pass
' 2>/dev/null
exit 0
