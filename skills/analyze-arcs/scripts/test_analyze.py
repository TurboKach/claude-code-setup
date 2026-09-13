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
check("head with flag (a non-flag value token like the -n count is treated as a path too, per the invariant)",
      analyze.bash_read_paths("head -n 5 dir/file2.py"), ["5", "dir/file2.py"])
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

# --- plan_span_end: reject -> revise -> approve keeps the span open past the rejected exit ---
def t(s): return f"2026-01-01T00:00:{s:02d}"

check("rejected exit does not end the span; approved exit does",
      analyze.plan_span_end(t(0), [t(10), t(30)], [t(40)], t(50)), t(30))
check("no approved exit ever -> end of transcript",
      analyze.plan_span_end(t(0), [t(10)], [], t(20)), t(20))

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
end = analyze.plan_span_end(r['enter_plan'][0], r['exit_plan'], r['plan_approved'], r['last'])
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

print()
if fails:
    print(f"{fails} FAILED")
    sys.exit(1)
print("all passed")
