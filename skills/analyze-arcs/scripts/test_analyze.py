#!/usr/bin/env python3
"""Plain assert-based tests for analyze.py's plan-mode span and Bash-read token filter.
Run: python3 test_analyze.py
No pytest, no fixtures on disk — everything is built in-process."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analyze

fails = 0

def check(name, got, want):
    global fails
    if got != want:
        fails += 1
        print(f"FAIL {name}: got {got!r} want {want!r}")
    else:
        print(f"ok   {name}")

# --- bash_read_paths: the six command shapes plus the reported false-negative/positive cases ---
check("cat single path", analyze.bash_read_paths("cat file1.txt"), ["file1.txt"])
check("head -n consumes its count, not a path", analyze.bash_read_paths("head -n 5 dir/file2.py"), ["dir/file2.py"])
check("tail before &&", analyze.bash_read_paths("tail -f log/file3.log && echo done"), ["log/file3.log"])
check("less path", analyze.bash_read_paths("less docs/readme.md"), ["docs/readme.md"])
check("grep drops pattern, keeps path", analyze.bash_read_paths("grep -n pattern src/app.py"), ["src/app.py"])
check("sed drops script, keeps path", analyze.bash_read_paths("sed -n '1,5p' config.yaml"), ["config.yaml"])

check("cat Makefile (no dot-extension, no slash)", analyze.bash_read_paths("cat Makefile"), ["Makefile"])
check("rg TODO src (bare dir, no slash/extension)", analyze.bash_read_paths("rg TODO src"), ["src"])
check("grep quoted path-like pattern is not a path",
      analyze.bash_read_paths("grep 'src/app.py' docs/x.md"), ["docs/x.md"])
check("cat on line 2 of a multi-line command",
      analyze.bash_read_paths("echo start\ncat file4.txt\necho end"), ["file4.txt"])
check("sed address range is not a path",
      analyze.bash_read_paths("sed -n '/^a:/,/^b:/p' file.yaml"), ["file.yaml"])

# --- quoting: quoted metacharacters never split a segment or terminate the capture ---
check("quoted pipe inside a grep pattern", analyze.bash_read_paths("grep -E 'foo|bar' src/app.py"), ["src/app.py"])
check("quoted '; cat' is text, not a command", analyze.bash_read_paths('echo "; cat x"'), [])
check("unbalanced quote yields nothing, no exception", analyze.bash_read_paths('cat "file.txt'), [])
check("unbalanced quote only kills its own segment",
      analyze.bash_read_paths('cat a.txt && cat "b'), ["a.txt"])
check("double-quoted path is unquoted once", analyze.bash_read_paths('cat "dir with space/x.py"'), ["dir with space/x.py"])

# --- grep/rg: the pattern is an operand only when no -e/-f/--regexp gave it ---
check("grep -e PAT", analyze.bash_read_paths("grep -e foo bar.py"), ["bar.py"])
check("grep -ePAT attached", analyze.bash_read_paths("grep -efoo bar.py"), ["bar.py"])
check("grep --regexp=PAT", analyze.bash_read_paths("grep --regexp=foo bar.py"), ["bar.py"])
check("grep --regexp PAT", analyze.bash_read_paths("grep --regexp foo bar.py"), ["bar.py"])
check("grep -f FILE leaves every operand a path", analyze.bash_read_paths("grep -f pats.txt src/app.py"), ["src/app.py"])
check("bare rg needle reads the cwd", analyze.bash_read_paths("rg needle"), ["."])
check("grep -r needle reads the cwd", analyze.bash_read_paths("grep -r needle"), ["."])

# --- option values are consumed with their option, per command ---
check("grep -m N", analyze.bash_read_paths("grep -m 3 pat path.py"), ["path.py"])
check("grep -A/-B context counts", analyze.bash_read_paths("grep -A 3 -B 2 pat f.py"), ["f.py"])
check("grep --include=GLOB", analyze.bash_read_paths("grep --include=*.py pat src"), ["src"])
check("rg -g GLOB and -t TYPE", analyze.bash_read_paths("rg -t py -g '*.py' pat src"), ["src"])
check("tail -c N", analyze.bash_read_paths("tail -c 100 f.log"), ["f.log"])
check("tail --lines=N", analyze.bash_read_paths("tail --lines=5 f.log"), ["f.log"])
check("head -n 5 on a plan file", analyze.bash_read_paths("head -n 5 docs/prompts/plan.md"), ["docs/prompts/plan.md"])
check("sed -i[SUFFIX] takes no separate value", analyze.bash_read_paths("sed -i.bak 's/a/b/' f.txt"), ["f.txt"])
check("sed -e SCRIPT leaves every operand a path",
      analyze.bash_read_paths("sed -n -e '/^a:/,/^b:/p' a.yaml b.yaml"), ["a.yaml", "b.yaml"])
check("sed -eSCRIPT attached", analyze.bash_read_paths("sed -n -e1,5p a.yaml"), ["a.yaml"])

# --- redirections are not operands; a < redirect is a read ---
check("2>/dev/null is not a path", analyze.bash_read_paths("cat x.txt 2>/dev/null"), ["x.txt"])
check("> target is not a path", analyze.bash_read_paths("cat x.txt >out.txt"), ["x.txt"])
check("cat <path is a read", analyze.bash_read_paths("cat <src/app.py"), ["src/app.py"])
check("grep pat <path is a read of path only", analyze.bash_read_paths("grep pat <src/app.py"), ["src/app.py"])
check("heredoc is not a read", analyze.bash_read_paths("cat <<'EOF'\nhello\nEOF"), [])
check("bare heredoc delimiter is not a read", analyze.bash_read_paths("cat << EOF"), [])
check("BSD sed -i '' keeps only the file", analyze.bash_read_paths("sed -i '' 's/a/b/' notes.md"), ["notes.md"])

# --- segments split on || and newlines too ---
check("|| splits segments", analyze.bash_read_paths("grep -q pat a.py || cat b.py"), ["a.py", "b.py"])
check("multi-line command, one read per line",
      analyze.bash_read_paths("cd /x\ncat one.py\nrg needle two/"), ["one.py", "two/"])

# --- product_file normalizes before matching ---
check("traversal out of docs/prompts is product", analyze.product_file("docs/prompts/../../src/app.py"), True)
check("plan file stays exempt", analyze.product_file("docs/prompts/plan.md"), False)
check("normalized plan file stays exempt", analyze.product_file("src/../docs/prompts/plan.md"), False)

# --- product_file: a trailing slash on an exempt directory must not defeat the match ---
check("docs/prompts/ (trailing slash) stays exempt", analyze.product_file("docs/prompts/"), False)
check("docs/prompts (no trailing slash) stays exempt", analyze.product_file("docs/prompts"), False)
check("/tmp/ stays scratch", analyze.product_file("/tmp/"), False)
check("/tmp (no trailing slash) stays scratch", analyze.product_file("/tmp"), False)
check("/tmp/x stays scratch", analyze.product_file("/tmp/x"), False)
check("docs/promptsX is product (no false match)", analyze.product_file("docs/promptsX"), True)

# --- plan_span_end: reject -> revise -> approve keeps the span open past the rejected exit ---
def t(s): return f"2026-01-01T00:00:{s:02d}"

check("rejected exit does not end the span; approved exit does",
      analyze.plan_span_end(t(0), [t(10), t(30)], [t(40)], [], [], t(50)), t(30))
check("no approved exit ever, no edit either -> end of transcript",
      analyze.plan_span_end(t(0), [t(10)], [], [], [], t(20)), t(20))
check("no approved exit ever, but a proven product edit closes the span",
      analyze.plan_span_end(t(0), [], [], [dict(t=t(5), file='src/app.py', error=False)], [], t(20)), t(5))
check("an edit whose result errored proves nothing -> end of transcript",
      analyze.plan_span_end(t(0), [], [], [dict(t=t(5), file='src/app.py', error=True)], [], t(20)), t(20))
check("an edit to a non-product file proves nothing -> end of transcript",
      analyze.plan_span_end(t(0), [], [], [dict(t=t(5), file='docs/prompts/plan.md', error=False)], [], t(20)), t(20))
check("a later enter_plan closes an unclosed earlier span",
      analyze.plan_span_end(t(0), [], [], [], [t(15)], t(50)), t(15))
check("a later enter_plan does not override an earlier approved exit within the cycle",
      analyze.plan_span_end(t(0), [t(5)], [t(6)], [], [t(15)], t(50)), t(5))

# --- scan_master_records: a synthetic transcript exercising both invariants end to end ---
def tool_use(T, tid, name, inp=None):
    return dict(type='assistant', timestamp=T,
                message=dict(model='claude-x', content=[dict(type='tool_use', id=tid, name=name, input=inp or {})]))

def tool_result(T, tid, content='ok', is_error=False):
    return dict(type='user', timestamp=T,
                message=dict(content=[dict(type='tool_result', tool_use_id=tid, content=content, is_error=is_error)]))

def read_use(T, tid, path):
    return tool_use(T, tid, 'Read', dict(file_path=path))

recs = [
    tool_use(t(0), 'e1', 'EnterPlanMode'),
    tool_result(t(1), 'e1'),                                    # opens the span at t(0)
    tool_use(t(2), 'x1', 'ExitPlanMode'),
    tool_result(t(3), 'x1', content='the user rejected the plan'),   # rejected: does not end the span
    read_use(t(4), 'r1', 'src/inside_after_reject.py'),
    tool_use(t(5), 'x2', 'ExitPlanMode'),
    tool_result(t(6), 'x2', content='User has approved your plan. ok'),   # approved: ends the span
    read_use(t(7), 'r2', 'src/outside_after_approve.py'),
]
r = analyze.scan_master_records(recs)
check("enter_plan opened once", r['enter_plan'], [t(0)])
check("exit_plan has both exits", r['exit_plan'], [t(2), t(5)])
check("plan_approved recorded", r['plan_approved'], [t(6)])
end = analyze.plan_span_end(r['enter_plan'][0], r['exit_plan'], r['plan_approved'], r['edits'], r['enter_plan'], r['last'])
check("span end is the approved exit, not the rejected one", end, t(5))
inside = [rd['file'] for rd in r['reads'] if r['enter_plan'][0] <= rd['t'] <= end and analyze.product_file(rd['file'])]
check("read during the rejected/revision phase is inside the span", inside, ['src/inside_after_reject.py'])
outside = [rd['file'] for rd in r['reads'] if not (r['enter_plan'][0] <= rd['t'] <= end) and analyze.product_file(rd['file'])]
check("read after the approved exit is outside the span", outside, ['src/outside_after_approve.py'])

# --- a denied EnterPlanMode opens nothing ---
recs_denied = [
    tool_use(t(0), 'e1', 'EnterPlanMode'),
    tool_result(t(1), 'e1', content='denied', is_error=True),
    read_use(t(2), 'r1', 'src/never_windowed.py'),
]
r2 = analyze.scan_master_records(recs_denied)
check("denied EnterPlanMode opens no span", r2['enter_plan'], [])

def edit_use(T, tid, name, path):
    return tool_use(T, tid, name, dict(file_path=path))

# --- (a) the approval string in a tool_result with no pending ExitPlanMode call is not an approval ---
recs_false_close = [
    tool_use(t(0), 'e1', 'EnterPlanMode'),
    tool_result(t(1), 'e1'),                                             # opens the span at t(0)
    read_use(t(2), 'r1', 'analyze.py'),
    tool_result(t(3), 'r1', content='...\nif \'User has approved your plan\' in rr: ...'),  # a Read, not an ExitPlanMode result
    read_use(t(4), 'r2', 'src/still_inside.py'),
]
ra = analyze.scan_master_records(recs_false_close)
check("(a) approval string outside an ExitPlanMode result is not recorded", ra['plan_approved'], [])
end_a = analyze.plan_span_end(ra['enter_plan'][0], ra['exit_plan'], ra['plan_approved'], ra['edits'], ra['enter_plan'], ra['last'])
check("(a) span stays open through both reads", end_a, ra['last'])
inside_a = [rd['file'] for rd in ra['reads'] if ra['enter_plan'][0] <= rd['t'] <= end_a and analyze.product_file(rd['file'])]
check("(a) both reads are inside the still-open span", sorted(inside_a), ['analyze.py', 'src/still_inside.py'])

# --- (b) enter -> exit(rejected) -> reads -> exit(approved) -> reads: middle reads in, trailing out ---
recs_b = [
    tool_use(t(0), 'e1', 'EnterPlanMode'), tool_result(t(1), 'e1'),
    tool_use(t(2), 'x1', 'ExitPlanMode'),
    tool_result(t(3), 'x1', content='the user rejected the plan', is_error=True),
    read_use(t(4), 'r1', 'src/middle.py'),
    tool_use(t(5), 'x2', 'ExitPlanMode'),
    tool_result(t(6), 'x2', content='User has approved your plan. ok'),
    read_use(t(7), 'r2', 'src/trailing.py'),
]
rb = analyze.scan_master_records(recs_b)
end_b = analyze.plan_span_end(rb['enter_plan'][0], rb['exit_plan'], rb['plan_approved'], rb['edits'], rb['enter_plan'], rb['last'])
inside_b = [rd['file'] for rd in rb['reads'] if rb['enter_plan'][0] <= rd['t'] <= end_b and analyze.product_file(rd['file'])]
outside_b = [rd['file'] for rd in rb['reads'] if not (rb['enter_plan'][0] <= rd['t'] <= end_b) and analyze.product_file(rd['file'])]
check("(b) middle read (after rejection, before approval) is inside", inside_b, ['src/middle.py'])
check("(b) trailing read (after approval) is outside", outside_b, ['src/trailing.py'])

# --- (c) enter -> reads -> successful Edit on a product file -> reads: first reads in, later reads out ---
recs_c = [
    tool_use(t(0), 'e1', 'EnterPlanMode'), tool_result(t(1), 'e1'),
    read_use(t(2), 'r1', 'src/before_edit.py'),
    edit_use(t(3), 'ed1', 'Edit', 'src/app.py'),
    tool_result(t(4), 'ed1', content='edited'),
    read_use(t(5), 'r2', 'src/after_edit.py'),
]
rc = analyze.scan_master_records(recs_c)
end_c = analyze.plan_span_end(rc['enter_plan'][0], rc['exit_plan'], rc['plan_approved'], rc['edits'], rc['enter_plan'], rc['last'])
inside_c = [rd['file'] for rd in rc['reads'] if rc['enter_plan'][0] <= rd['t'] <= end_c and analyze.product_file(rd['file'])]
outside_c = [rd['file'] for rd in rc['reads'] if not (rc['enter_plan'][0] <= rd['t'] <= end_c) and analyze.product_file(rd['file'])]
check("(c) end of span is the successful edit's timestamp", end_c, t(3))
check("(c) read before the proven edit is inside", inside_c, ['src/before_edit.py'])
check("(c) read after the proven edit is outside", outside_c, ['src/after_edit.py'])

# --- (d) enter -> reads -> Edit whose result is_error -> reads: all in (edit didn't prove anything) ---
recs_d = [
    tool_use(t(0), 'e1', 'EnterPlanMode'), tool_result(t(1), 'e1'),
    read_use(t(2), 'r1', 'src/before_edit.py'),
    edit_use(t(3), 'ed1', 'Edit', 'src/app.py'),
    tool_result(t(4), 'ed1', content='blocked: still in plan mode', is_error=True),
    read_use(t(5), 'r2', 'src/after_edit.py'),
]
rd_ = analyze.scan_master_records(recs_d)
end_d = analyze.plan_span_end(rd_['enter_plan'][0], rd_['exit_plan'], rd_['plan_approved'], rd_['edits'], rd_['enter_plan'], rd_['last'])
inside_d = [rd['file'] for rd in rd_['reads'] if rd_['enter_plan'][0] <= rd['t'] <= end_d and analyze.product_file(rd['file'])]
check("(d) a failed edit proves nothing; span runs to end of transcript", end_d, rd_['last'])
check("(d) both reads stay inside the still-open span", sorted(inside_d), ['src/after_edit.py', 'src/before_edit.py'])

# --- (e) an Edit with no tool_result at all (session interrupted) proves nothing ---
recs_e = [
    tool_use(t(0), 'e1', 'EnterPlanMode'), tool_result(t(1), 'e1'),
    read_use(t(2), 'r1', 'src/before_edit.py'),
    edit_use(t(3), 'ed1', 'Edit', 'src/app.py'),   # no tool_result for ed1 -- session interrupted
]
re_ = analyze.scan_master_records(recs_e)
check("(e) an edit with no tool_result is unproven", re_['edits'][0]['error'], True)
end_e = analyze.plan_span_end(re_['enter_plan'][0], re_['exit_plan'], re_['plan_approved'], re_['edits'], re_['enter_plan'], re_['last'])
check("(e) unresolved edit does not close the span; span runs to end of transcript", end_e, re_['last'])

# --- (f) two plan-mode cycles: enter -> rejected/manual exit -> proven edit -> enter -> approved exit ---
recs_f = [
    tool_use(t(0), 'e1', 'EnterPlanMode'), tool_result(t(1), 'e1'),                 # cycle 1 opens
    read_use(t(2), 'r1', 'src/cycle1_read.py'),
    tool_use(t(3), 'x1', 'ExitPlanMode'),
    tool_result(t(4), 'x1', content='the user rejected the plan', is_error=True),   # cycle 1: rejected exit
    edit_use(t(5), 'ed1', 'Edit', 'src/app.py'),
    tool_result(t(6), 'ed1', content='edited'),                                     # proven edit closes cycle 1
    tool_use(t(7), 'e2', 'EnterPlanMode'), tool_result(t(8), 'e2'),                 # cycle 2 opens
    read_use(t(9), 'r2', 'src/cycle2_read.py'),
    tool_use(t(10), 'x2', 'ExitPlanMode'),
    tool_result(t(11), 'x2', content='User has approved your plan. ok'),            # cycle 2: approved exit
    read_use(t(12), 'r3', 'src/after_approve.py'),
]
rf = analyze.scan_master_records(recs_f)
check("(f) both cycles opened", rf['enter_plan'], [t(0), t(7)])
end_f1 = analyze.plan_span_end(rf['enter_plan'][0], rf['exit_plan'], rf['plan_approved'], rf['edits'], rf['enter_plan'], rf['last'])
end_f2 = analyze.plan_span_end(rf['enter_plan'][1], rf['exit_plan'], rf['plan_approved'], rf['edits'], rf['enter_plan'], rf['last'])
check("(f) cycle 1 span ends at its own proven edit, not cycle 2's approved exit", end_f1, t(5))
check("(f) cycle 2 span ends at its own approved exit", end_f2, t(10))
inside_f1 = [rd['file'] for rd in rf['reads'] if rf['enter_plan'][0] <= rd['t'] <= end_f1 and analyze.product_file(rd['file'])]
inside_f2 = [rd['file'] for rd in rf['reads'] if rf['enter_plan'][1] <= rd['t'] <= end_f2 and analyze.product_file(rd['file'])]
outside_f2 = [rd['file'] for rd in rf['reads'] if rd['t'] > end_f2 and analyze.product_file(rd['file'])]
check("(f) cycle 1 read is attributed to cycle 1's span", inside_f1, ['src/cycle1_read.py'])
check("(f) cycle 2 read is attributed to cycle 2's span", inside_f2, ['src/cycle2_read.py'])
check("(f) read after cycle 2's approval is outside every span", outside_f2, ['src/after_approve.py'])

# ---------------------------------------------------------------- --semantic: PATH_CALL candidate collection
def text_msg(T, text):
    return dict(type='assistant', timestamp=T, message=dict(model='claude-x', content=[dict(type='text', text=text)]))

def user_str(T, text):
    return dict(type='user', timestamp=T, message=dict(content=text))

recs_cap = [text_msg(t(i), 'x' * 700) for i in range(10)] + \
    [user_str(t(20), 'Base directory for this skill: /foo/feature-workflow'), text_msg(t(21), 'after fw text')]
r_cap = analyze.scan_master_records(recs_cap)
check("path_call_candidates capped at 8 per session", len(r_cap['path_call_candidates']), 8)
check("each candidate truncated to 600 chars", all(len(c['text']) == 600 for c in r_cap['path_call_candidates']), True)
check("candidates only precede fw_loaded", all(c['t'] < r_cap['fw_loaded'] for c in r_cap['path_call_candidates']), True)
check("text after fw_loaded is not a candidate", any(c['t'] == t(21) for c in r_cap['path_call_candidates']), False)

recs_edit_cutoff = [text_msg(t(0), 'before the edit'), edit_use(t(1), 'ed1', 'Edit', 'src/app.py'),
                     tool_result(t(2), 'ed1', content='edited'), text_msg(t(3), 'after the edit')]
r_ec = analyze.scan_master_records(recs_edit_cutoff)
check("first_product_edit recorded", r_ec['first_product_edit'], t(1))
check("only the pre-edit block is a candidate", [c['text'] for c in r_ec['path_call_candidates']], ['before the edit'])

recs_nonproduct_edit = [text_msg(t(0), 'before'), edit_use(t(1), 'ed1', 'Edit', 'docs/prompts/plan.md'),
                         tool_result(t(2), 'ed1', content='edited'), text_msg(t(3), 'still collected')]
r_np = analyze.scan_master_records(recs_nonproduct_edit)
check("an edit to a non-product file does not close the cutoff", r_np['first_product_edit'], None)
check("both blocks are candidates when the edit is not a product file",
      [c['text'] for c in r_np['path_call_candidates']], ['before', 'still collected'])

# ---------------------------------------------------------------- --semantic: resolve_path_call_semantic (post-scan pass)
# analyze.py's own `import jev` is lazy (main(), --semantic only); these tests exercise the
# semantic-override functions directly, so they import jev themselves, same as main() would.
sys.path.insert(0, os.path.expanduser('~/.claude/local/analyze-arcs'))
try:
    import jev
    analyze.jev = jev
except ImportError:   # the local-only semantic layer is not shipped with the kit
    jev = None

if jev is not None:
    def make_r(candidates, path_call=None):
        return dict(path_call=path_call, path_call_candidates=candidates, path_call_regex_fallback=False)

    class FakePathCallAskMany:
        def __init__(self, fn):
            self.calls = []
            self.fn = fn

        def __call__(self, items, workers=8):
            self.calls.append(list(items))
            return [self.fn(kw['state']['text']) for kw in items]

    def yn_answer(text):
        if text == 'FAIL':
            return None
        return {'path_call': {'type': 'noul', 'noul': 0.9 if 'yes' in text else 0.1}}

    r_a = make_r([dict(t='ta0', text='yes text'), dict(t='ta1', text='irrelevant')])
    r_b = make_r([dict(t='tb0', text='no1'), dict(t='tb1', text='no2'), dict(t='tb2', text='yes3')])
    r_c = make_r([dict(t='tc0', text='no')])
    r_e = make_r([dict(t='te0', text='no')], path_call='regex_ts')

    fake_pc = FakePathCallAskMany(yn_answer)
    orig_ask_many = analyze.jev.ask_many
    analyze.jev.ask_many = fake_pc
    try:
        analyze.resolve_path_call_semantic([r_a, r_b, r_c, r_e])
    finally:
        analyze.jev.ask_many = orig_ask_many

    check("session stops at its first yes candidate", r_a['path_call'], 'ta0')
    check("session keeps trying later candidates until it finds a yes", r_b['path_call'], 'tb2')
    check("session exhausted with no yes keeps its (None) regex path_call", r_c['path_call'], None)
    check("session exhausted with no yes is not marked as a failure fallback", r_c['path_call_regex_fallback'], False)
    check("session with an existing regex path_call and no yes keeps that value", r_e['path_call'], 'regex_ts')
    check("3 rounds run (the longest candidate list has 3 entries)", len(fake_pc.calls), 3)
    check("round 0 batches every session with a candidate", len(fake_pc.calls[0]), 4)
    check("round 1 drops the session that already found yes or exhausted a 1-candidate list",
          len(fake_pc.calls[1]), 1)
    check("round 2 only the still-undecided session remains", len(fake_pc.calls[2]), 1)

    r_fail = make_r([dict(t='td0', text='FAIL')])
    analyze.jev.ask_many = fake_pc
    fake_pc.calls.clear()
    try:
        analyze.resolve_path_call_semantic([r_fail])
    finally:
        analyze.jev.ask_many = orig_ask_many
    check("a failed call (no key or exhausted retries) keeps the regex path_call", r_fail['path_call'], None)
    check("a failed call marks the session for the ' (regex)' flag suffix", r_fail['path_call_regex_fallback'], True)

    fake_pc.calls.clear()
    analyze.jev.ask_many = fake_pc
    try:
        analyze.resolve_path_call_semantic([make_r([])])
    finally:
        analyze.jev.ask_many = orig_ask_many
    check("no sessions with candidates -> no-op, no call made", fake_pc.calls, [])

    # ---------------------------------------------------------------- --semantic: REASON override (both directions) + fallback
    orig_ask = analyze.jev.ask
    try:
        analyze.jev.ask = lambda **kw: {'reason': {'type': 'noul', 'noul': 0.1}}
        check("regex hits but semantic overrides to 'no reason'",
              analyze.reason_suffix("the reason is money", "fixer", "opus", "sonnet", True), ' — no reason in prompt')

        analyze.jev.ask = lambda **kw: {'reason': {'type': 'noul', 'noul': 0.9}}
        check("regex misses but semantic overrides to 'reason stated'",
              analyze.reason_suffix("just do it, opus please", "fixer", "opus", "sonnet", True), ' — reason stated')

        analyze.jev.ask = lambda **kw: None
        check("no key/failed call falls back to the regex, suffixed ' (regex)'",
              analyze.reason_suffix("the reason is clear", "fixer", "opus", "sonnet", True), ' — reason stated (regex)')

        check("without --semantic, only the regex runs, no suffix ever",
              analyze.reason_suffix("the reason is clear", "fixer", "opus", "sonnet", False), ' — reason stated')
    finally:
        analyze.jev.ask = orig_ask
else:
    print("skip semantic tests: jev.py (local-only semantic layer) not present")

# --- pins_for: a session is judged by the pins in force when it started ---
check("pre-cutover session: executor doctrine is sonnet",
      analyze.pins_for("2026-09-20T10:00:00.000Z")['step-executor'], 'sonnet')
check("pre-cutover session: fixer doctrine is sonnet",
      analyze.pins_for("2026-09-22T23:59:59.000Z")['fixer'], 'sonnet')
check("post-cutover session: executor doctrine is opus",
      analyze.pins_for("2026-09-23T00:00:01.000Z")['team-executor'], 'opus')
check("unknown start: current pins", analyze.pins_for(None), analyze.PINS)

print()
if fails:
    print(f"{fails} FAILED")
    sys.exit(1)
print("all passed")
