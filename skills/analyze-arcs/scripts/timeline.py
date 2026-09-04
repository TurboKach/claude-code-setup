#!/usr/bin/env python3
"""Dump one Claude Code transcript (master or subagent JSONL) as a readable timeline:
user text, assistant text, tool calls (Agent spawns with type/model/prompt head), tool results (head).
usage: timeline.py <transcript.jsonl> <out.txt>"""
import json, sys
p, out = sys.argv[1], sys.argv[2]
with open(out, 'w') as o:
    for line in open(p):
        try: d = json.loads(line)
        except Exception: continue
        t = d.get('type'); ts = (d.get('timestamp') or '')[5:19]
        m = d.get('message', {}); c = m.get('content')
        if t == 'user':
            if isinstance(c, str):
                o.write(f"\n[{ts}] USER: {c[:1500]}\n")
            elif isinstance(c, list):
                for x in c:
                    if not isinstance(x, dict): continue
                    if x.get('type') == 'text': o.write(f"\n[{ts}] USER: {x['text'][:1500]}\n")
                    elif x.get('type') == 'tool_result':
                        r = x.get('content'); r = r if isinstance(r, str) else ' '.join(y.get('text', '') for y in (r or []) if isinstance(y, dict))
                        o.write(f"[{ts}] RESULT: {r[:700]}\n")
        elif t == 'assistant':
            for x in c or []:
                if not isinstance(x, dict): continue
                if x.get('type') == 'text': o.write(f"\n[{ts}] ASSISTANT: {x['text'][:2500]}\n")
                elif x.get('type') == 'tool_use':
                    i = x.get('input', {}); n = x['name']
                    if n == 'Agent':
                        o.write(f"[{ts}] TOOL Agent type={i.get('subagent_type')} model={i.get('model')} desc={i.get('description')}\n   PROMPT: {i.get('prompt', '')[:1200]}\n")
                    elif n == 'Bash':
                        o.write(f"[{ts}] TOOL Bash{' (bg)' if i.get('run_in_background') else ''}: {i.get('command', '')[:400]}\n")
                    elif n == 'AskUserQuestion':
                        o.write(f"[{ts}] TOOL AskUserQuestion: {json.dumps(i.get('questions'))[:1500]}\n")
                    else:
                        o.write(f"[{ts}] TOOL {n}: {json.dumps(i)[:300]}\n")
print(out)
