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

print()
if fails:
    print(f"{fails} FAILED")
    sys.exit(1)
print("all passed")
