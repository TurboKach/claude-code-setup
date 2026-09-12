#!/usr/bin/env python3
"""Measure Claude Code pipeline sessions since a date and flag mechanical doctrine violations.
usage: analyze.py --since YYYY-MM-DD [--projects-dir ~/.claude/projects] --out <report.md> [--min-kb 150]
Reads master transcripts, their subagents/*.jsonl, and the codex-challenge --out logs the masters named.
Judgment findings (verification proved only negatives, review escapes) are NOT detected here."""
import argparse, datetime as dt, glob, json, os, re, sys

PINS = {'team-planner': 'fable', 'team-plan-reviewer': 'fable', 'team-reviewer': 'opus',
        'step-executor': 'sonnet', 'team-executor': 'sonnet', 'fixer': 'sonnet',
        'codex-triage': 'sonnet', 'spec-reviewer': 'sonnet', 'explorer': 'sonnet', 'general-purpose': 'sonnet'}
FW = re.compile(r'Base directory for this skill: \S*/feature-workflow\b')
NON_PRODUCT = ('/.claude', '/memory/', '/MEMORY.md', '/docs/prompts/', '/docs/reviews/', '/docs/todos/', '/TODOS.md', '/tech-debt', '/__pycache__/')   # anywhere in the path
HANDOFF_DOC = re.compile(r'HANDOFF[^/]*\.md$')   # a handoff doc by basename, wherever it lives
SCRATCH_PREFIX = ('/tmp/', '/private/tmp/', '/dev/')   # only at the start of an absolute path (a repo's own dev/ or tmp/ is product)
# A path call line: "Path call: ...", or a message that opens with one-shot / pipeline, or names one with a colon or dash.
PATH_CALL = re.compile(r'(?i)\bpath call\b|^\s*\**\s*(one-shot|pipeline)\b(?!-)|\b(one-shot|pipeline)\**\s*[:\u2014\u2013]|\b(one-shot|pipeline)\**\s+-\s')
# A stated reason for an off-doctrine pin: the doctrine's own categories (structural / same-mechanism / fable rate-limited) count.
REASON = re.compile(r'(?i)reason|opus for|structural|mechanism|rate.?limit|429')
def product_file(f):
    """True when f names a product file; False for scratch, plans, reviews, TODO indexes and build artifacts."""
    f = (f or '').strip('\'"')
    if not f: return False
    a = f if f.startswith('/') else '/' + f
    scratch = f.startswith('/') and f.startswith(SCRATCH_PREFIX)
    return not (scratch or any(k in a for k in NON_PRODUCT) or HANDOFF_DOC.search(a))

def ts(s):
    return dt.datetime.strptime(s[:19], '%Y-%m-%dT%H:%M:%S') if s else None

def records(p):
    for line in open(p, errors='ignore'):
        try: yield json.loads(line)
        except Exception: continue

def scan_master(p):
    r = dict(path=p, first=None, last=None, cwd=None, models=set(), user_turns=0, first_prompt='', peak=0,
             spawns=[], codex=[], edits=[], gates=[], pushes=[], killed=[], fw_loaded=None, path_call=None,
             plan_approved=[], exit_plan=[], first_edit=None, api_errors=0, bash_diff=False)
    pending_q = {}
    for d in records(p):
        t = d.get('type'); T = d.get('timestamp')
        if T:
            r['first'] = r['first'] or T; r['last'] = T
        if d.get('cwd') and not r['cwd']: r['cwd'] = d['cwd']
        m = d.get('message', {}) or {}
        if t == 'assistant':
            if d.get('isApiErrorMessage'): r['api_errors'] += 1
            if m.get('model'): r['models'].add(m['model'])
            u = m.get('usage') or {}
            tot = u.get('input_tokens', 0) + u.get('cache_read_input_tokens', 0) + u.get('cache_creation_input_tokens', 0)
            r['peak'] = max(r['peak'], tot)
            for c in m.get('content', []) or []:
                if not isinstance(c, dict): continue
                if c.get('type') == 'text' and r['path_call'] is None:
                    if PATH_CALL.search(c['text'][:200]): r['path_call'] = T
                if c.get('type') != 'tool_use': continue
                n = c['name']; i = c.get('input', {}) or {}
                if n == 'Agent':
                    r['spawns'].append(dict(t=T, type=i.get('subagent_type'), model=i.get('model'), name=i.get('name'),
                                            desc=(i.get('description') or '')[:60], prompt=i.get('prompt', '') or '', id=c['id']))
                elif n == 'Bash':
                    cmd = i.get('command', '') or ''
                    rng = re.search(r'codex-challenge\.sh\s+(\S+\.\.\S+)', cmd)   # an actual launch: script followed by a <base>..<head> range
                    if rng:
                        out = re.search(r'--out\s+(\S+)', cmd)
                        r['codex'].append(dict(t=T, bg=bool(i.get('run_in_background')), range=rng.group(1) if rng else '?',
                                               pin='--pin' in cmd, out=out.group(1).strip('\'";') if out else None,
                                               timeout=i.get('timeout'), id=c['id']))
                    if re.search(r'\bgit push\b', cmd): r['pushes'].append(T)
                elif n in ('Edit', 'Write', 'MultiEdit', 'NotebookEdit'):
                    r['edits'].append(dict(t=T, tool=n, file=i.get('file_path') or i.get('notebook_path') or ''))
                    r['first_edit'] = r['first_edit'] or T
                elif n in ('AskUserQuestion', 'ExitPlanMode', 'EnterPlanMode', 'PushNotification'):
                    q = i.get('questions') or [{}]
                    r['gates'].append(dict(t=T, tool=n, q=(q[0].get('question', '') if isinstance(q, list) and q else '')[:100], answered=None))
                    pending_q[c['id']] = r['gates'][-1]
                    if n == 'ExitPlanMode': r['exit_plan'].append(T)
        elif t == 'user':
            # Files a Bash command changed, as the harness recorded them (git working tree, ≤200 paths; 2.1.269+, `bashEditDiffEnabled`,
            # on by default in auto/bypass mode, never shown to the model). Ground truth — the command text is not parsed.
            tur = d.get('toolUseResult'); bed = tur.get('bashEditDiff') if isinstance(tur, dict) else None
            if isinstance(bed, dict) and isinstance(bed.get('changedFiles'), list):   # a record without the list (snapshot skipped) proves nothing
                r['bash_diff'] = True
                for f in bed['changedFiles']:
                    r['edits'].append(dict(t=T, tool='Bash', file=f)); r['first_edit'] = r['first_edit'] or T
            c = m.get('content')
            if isinstance(c, str):
                if not d.get('isMeta'):
                    r['user_turns'] += 1; r['first_prompt'] = r['first_prompt'] or c[:160].replace('\n', ' ')
                if FW.search(c): r['fw_loaded'] = r['fw_loaded'] or T
                if '<status>killed</status>' in c: r['killed'].append(T)
            elif isinstance(c, list):
                for x in c:
                    if not isinstance(x, dict): continue
                    if x.get('type') == 'text':
                        tx = x.get('text', '')
                        if FW.search(tx): r['fw_loaded'] = r['fw_loaded'] or T
                        if '<status>killed</status>' in tx: r['killed'].append(T)
                    if x.get('type') == 'tool_result':
                        g = pending_q.pop(x.get('tool_use_id'), None)
                        if g: g['answered'] = T
                        rr = x.get('content'); rr = rr if isinstance(rr, str) else ' '.join(y.get('text', '') for y in (rr or []) if isinstance(y, dict))
                        if 'User has approved your plan' in rr: r['plan_approved'].append(T)
    return r

def scan_subagents(session_dir):
    rows = []
    for p in sorted(glob.glob(os.path.join(session_dir, 'subagents', '*.jsonl'))):
        first = last = None; turns = 0; models = set(); err = 0; capped = False; kb = os.path.getsize(p) // 1024
        for d in records(p):
            T = d.get('timestamp')
            if T: first = first or T; last = T
            if d.get('type') == 'assistant':
                turns += 1
                mm = (d.get('message') or {}).get('model')
                if mm: models.add(mm)
                if d.get('isApiErrorMessage'): err += 1
            if d.get('type') == 'user':
                c = (d.get('message') or {}).get('content')
                if isinstance(c, str) and 'turn limit' in c: capped = True
        rows.append(dict(file=os.path.basename(p), first=first, last=last, turns=turns, models=','.join(sorted(models)), err=err, kb=kb, capped=capped))
    return rows

def codex_run(out):
    if not out: return None
    log = out + '.log'
    if not os.path.exists(log): return dict(out=out, missing=True)
    st = os.stat(log); b = getattr(st, 'st_birthtime', st.st_mtime)
    header = ''
    if os.path.exists(out):
        with open(out, errors='ignore') as f: header = f.readline().strip()
    return dict(out=out, minutes=int((st.st_mtime - b) // 60), log_kb=st.st_size // 1024,
                verdict_b=os.path.getsize(out) if os.path.exists(out) else -1, header=header[:140])

def mins(a, b):
    return int((ts(b) - ts(a)).total_seconds() // 60) if a and b else None

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--since', required=True); ap.add_argument('--projects-dir', default=os.path.expanduser('~/.claude/projects'))
    ap.add_argument('--out', required=True); ap.add_argument('--min-kb', type=int, default=150)
    a = ap.parse_args(); since = dt.datetime.strptime(a.since, '%Y-%m-%d').timestamp()
    masters = []
    for p in glob.glob(os.path.join(a.projects_dir, '*', '*.jsonl')):
        if os.path.getmtime(p) < since: continue
        sd = p[:-6]; nsub = len(glob.glob(os.path.join(sd, 'subagents', '*.jsonl')))
        if os.path.getsize(p) < a.min_kb * 1024 and nsub == 0: continue
        masters.append((p, sd, nsub))
    masters.sort(key=lambda x: os.path.getmtime(x[0]))
    L = [f"# Arc analysis since {a.since} (generated {dt.datetime.now():%Y-%m-%d %H:%M})", '',
         f"Sessions ≥{a.min_kb} KB or with subagents: {len(masters)}. Times are UTC. Flags are mechanical; judgment findings need the timelines.", '']
    flags_all = []
    for p, sd, nsub in masters:
        r = scan_master(p); subs = scan_subagents(sd); sid = os.path.basename(p)[:8]; proj = os.path.basename(os.path.dirname(p))
        L += [f"## {proj} / {sid}", f"- {r['first']} → {r['last']}, user turns {r['user_turns']}, models {sorted(r['models'])}, peak context {r['peak']:,}, api errors {r['api_errors']}",
              f"- prompt: {r['first_prompt']}", f"- feature-workflow loaded: {r['fw_loaded'] or 'no'}; path call line: {r['path_call'] or 'none'}; first master edit: {r['first_edit'] or 'none'}; Bash writes: {'recorded by the harness' if r['bash_diff'] else 'not recorded (Edit/Write only — needs 2.1.269+ with bashEditDiffEnabled)'}",
              f"- subagents {len(subs)} ({sum(s['kb'] for s in subs)//1024} MB), codex launches {len(r['codex'])}, pushes {len(r['pushes'])}, background tasks killed {len(r['killed'])}"]
        flags = []
        if r['fw_loaded'] and not (r['path_call'] and r['path_call'] <= r['fw_loaded']): flags.append('no one-shot/pipeline call line before feature-workflow loaded')
        if not r['fw_loaded'] and not r['path_call'] and any(product_file(e['file']) for e in r['edits']): flags.append('product edits without a one-shot/pipeline call line')
        for s in r['spawns']:
            want = PINS.get(s['type'])
            if s['model'] is None: flags.append(f"{s['t'][11:16]} unpinned spawn {s['type']} ({s['desc']})")
            elif want and s['model'] != want:
                reason = bool(REASON.search(s['prompt']))
                flags.append(f"{s['t'][11:16]} {s['type']} pinned {s['model']} (doctrine {want}){' — reason stated' if reason else ' — no reason in prompt'}")
            if s['name']: flags.append(f"{s['t'][11:16]} named spawn {s['type']} name={s['name']}")
        for c in r['codex']:
            if not c['bg']: flags.append(f"{c['t'][11:16]} codex-challenge run in the foreground")
            if c['out'] and not re.search(r'/claude-\d+/[^/]*|/scratchpad/|docs/reviews/', c['out']): flags.append(f"{c['t'][11:16]} --out outside scratchpad/docs/reviews: {c['out']}")
        if r['fw_loaded']:
            for e in r['edits']:
                if e['t'] > r['fw_loaded'] and product_file(e['file']): flags.append(f"{e['t'][11:16]} master {e['tool']} on product file inside pipeline: {e['file']}")
        for x in r['exit_plan']:
            ap_ = next((q for q in r['plan_approved'] if q > x), None); w = mins(x, ap_)
            if w is None: flags.append(f"{x[11:16]} ExitPlanMode never approved in this session")
            elif w > 60: flags.append(f"{x[11:16]} ExitPlanMode waited {w} min for approval")
        for g in r['gates']:
            if g['tool'] == 'AskUserQuestion':
                w = mins(g['t'], g['answered'])
                if w is not None and w > 60: flags.append(f"{g['t'][11:16]} AskUserQuestion waited {w} min: {g['q']}")
        deaths = [s for s in subs if s['err'] and s['turns'] <= 1]
        if deaths: flags.append(f"{len(deaths)} subagent(s) died on an API error before doing work")
        for s in subs:
            if s['capped']: flags.append(f"{(s['first'] or '')[11:16]} subagent {s['file'][:14]} hit its turn cap")
        L.append('- **flags:** ' + ('; '.join(flags) if flags else 'none'))
        flags_all += [(proj, sid, f) for f in flags]
        if r['spawns']:
            L += ['', '| spawn | type | model | desc | turns | min | KB | model seen |', '|---|---|---|---|---|---|---|---|']
            subs_by_time = sorted(subs, key=lambda s: s['first'] or '')
            for s, sub in zip(r['spawns'], subs_by_time + [None] * len(r['spawns'])):
                if sub: L.append(f"| {s['t'][11:16]} | {s['type']} | {s['model']} | {s['desc']} | {sub['turns']} | {mins(sub['first'], sub['last'])} | {sub['kb']} | {sub['models']} |")
                else: L.append(f"| {s['t'][11:16]} | {s['type']} | {s['model']} | {s['desc']} | | | | (no transcript matched) |")
        if r['codex']:
            L += ['', '| launch | bg | range | pin | out | run min | verdict B | header |', '|---|---|---|---|---|---|---|---|']
            for c in r['codex']:
                run = codex_run(c['out']) or {}
                L.append(f"| {c['t'][11:16]} | {'bg' if c['bg'] else 'FG'} | {c['range'][:30]} | {'pin' if c['pin'] else ''} | {(c['out'] or '-')[-40:]} | {run.get('minutes','?')} | {run.get('verdict_b','?')} | {run.get('header','')[:80]} |")
        if r['gates']:
            L += ['', 'gates: ' + '; '.join(f"{g['t'][11:16]} {g['tool']}{' ('+str(mins(g['t'], g['answered']))+' min)' if g['answered'] else ''} {g['q']}" for g in r['gates'])]
        L.append('')
    L += ['## All flags', ''] + [f"- {p} / {s}: {f}" for p, s, f in flags_all] + ([] if flags_all else ['- none'])
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    open(a.out, 'w').write('\n'.join(L) + '\n'); print(a.out, f"({len(masters)} sessions, {len(flags_all)} flags)")

if __name__ == '__main__': main()
