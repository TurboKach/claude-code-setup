#!/usr/bin/env bash
# PreToolUse hook on Bash (settings.example.json registers it; install.sh
# merges it). Hook JSON on stdin; a deny is printed as the documented
# hookSpecificOutput JSON on stdout, exit 0. Three rules:
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
#   C. a bare wait on a process — an until/while loop whose head tests
#      pgrep, pidof, `kill -0` or ps — is denied everywhere. The Bash tool
#      timeout backgrounds such a loop instead of ending it, so the wait must
#      run under the `timeout` command: `timeout <N> bash -c "until …"`. That
#      form is quoted and passes. Same boundary and quote-stripping as B.
#
# Why: a fixer's `xcodebuild test` (no timeout)
# was auto-backgrounded at the 2-min default; its `sleep 90; tail` was blocked
# with "use Monitor with an until-loop", a tool the agent's tools: list
# strips; so it ran `until [ -f <task>.output.done ]; do sleep 5; done` in
# the background, and that loop outlived the agent's report by 54 minutes.
# Across 8 sessions since 2026-08-25: 25 subagents auto-backgrounded, 16 hit
# the sleep block, 2 orphaned pollers. The agent-definition line asking for
# an explicit timeout was ignored in ~30 of ~40 calls — prose does not hold.
#
# Cost: this runs before every Bash call. A call whose raw text cannot reach
# a rule (no until/while, no agent_id with run_in_background, no \u escape)
# exits after a builtin read, with no process started. Anything else goes
# through one awk pass that reads the JSON Claude Code sends: top-level keys
# by depth, strings decoded, the last duplicate key wins; a subagent has a
# non-empty string agent_id, a non-string command counts as empty. Word
# boundaries are ASCII, as in C-locale regexes. BSD awk's cost grows with
# every regex hit and every substr() of a long string, so the text is cut
# with one-character split(), never gsub.
#
# Fail-open: input the reader cannot follow (an unterminated string,
# unbalanced brackets), a missing awk, or any other tool name produces no
# output and exit 0, so a hook fault can never strand a run.
set -u
LC_ALL=C

# The first 64 KiB are read by the builtin (no process), the rest of a
# bigger input streams through tr (the builtin reads a pipe byte by byte).
# Both drop NUL bytes, as the old $(cat) did.
input='' chunk='' big=''
while IFS= read -r -d '' -n 65536 chunk; do
  input+=$chunk
  [ ${#chunk} -lt 65536 ] || { big=1; break; }
done
[ -n "$big" ] || input+=$chunk

[ -n "$big" ] || case $input in
  *'\u'* | *until* | *while*) ;;
  *agent_id*) case $input in *run_in_background*) ;; *) exit 0 ;; esac ;;
  *) exit 0 ;;
esac

# The trailing \001 ends awk's one record.
rule=$({ printf '%s' "$input"; [ -z "$big" ] || tr -d '\000'; printf '\001'; } | LC_ALL=C awk '
function join(m,   i, n) {  # D[1..m] concatenated pairwise: n log n, not quadratic
  while (m > 1) {
    n = 0
    for (i = 1; i <= m; i += 2) D[++n] = i < m ? D[i] D[i + 1] : D[i]
    m = n
  }
  return m ? D[1] : ""
}
function add(x) {  # grow the text being built: short pieces merge first, so D stays small
  sb = sb x
  if (length(sb) > 256) { D[++m] = sb; sb = "" }
}
function take(   r) {  # the text built so far; starts the next one
  D[++m] = sb; r = join(m); m = 0; sb = ""
  return r
}
function hex(p,   i, h, v) {  # "uXXXX…" -> code point, or -1
  if (length(p) < 5) return -1
  for (i = 2; i <= 5; i++) { if (!(h = index(HX, substr(p, i, 1)))) return -1; v = v * 16 + (h - 1) % 16 }
  return v
}
function utf8(c) {
  if (c == 10) return "\001"  # a newline is \001 (see BEGIN)
  if (c < 2) return "\003"    # NUL and \001 stand in as \003: same class for every rule
  if (c < 128) return chr[c]
  if (c < 2048) return chr[192 + int(c / 64)] chr[128 + c % 64]
  if (c < 65536) return chr[224 + int(c / 4096)] chr[128 + int(c / 64) % 64] chr[128 + c % 64]
  return chr[240 + int(c / 262144)] chr[128 + int(c / 4096) % 64] chr[128 + int(c / 64) % 64] chr[128 + c % 64]
}
function strip(c,   na, A, i, ne, E, j, st, oi, tail, skip) {  # drop "…" and \047…\047 as python re.sub did
  # Walk the pieces between double quotes; a piece is cut at single quotes
  # only when it is not inside a double-quoted span. st: the open quote.
  na = split(c, A, "\"")
  for (i = 1; i <= na; i++) {
    if (!skip) {
      if (st == "\"" || !index(A[i], "\047")) { if (st == "") add(A[i]) }
      else {
        ne = split(A[i], E, "\047")
        for (j = 1; j <= ne; j++) {
          if (j > 1) { if (st == "") { st = "\047"; oi = i; tail = E[j] } else st = "" }
          if (st == "") add(E[j])
        }
      }
    }
    skip = 0
    if (i < na) { if (st == "") { st = "\""; oi = i } else if (st == "\"") st = "" }
    # A quote left open at the end has no partner: it stays as text, and the
    # scan resumes right after it (nothing was added since it opened).
    else if (st == "\"") { add("\""); st = ""; i = oi }
    else if (st == "\047") { add("\047" tail); st = ""; i = oi - 1; skip = 1 }
  }
  return take()
}
function val(v, isstr) {  # a value at depth d; a container passes "", 0
  if (d == 1 && T[1] == "{") {
    if (key[1] == "tool_name") bash = isstr && v == "Bash"
    else if (key[1] == "agent_id") aid = isstr && v != ""
  } else if (d == 2 && T[2] == "{" && T[1] == "{" && key[1] == "tool_input") {
    if (key[2] == "command") cmd = isstr ? v : ""
    else if (key[2] == "run_in_background") bg = !isstr && v == "true"
  }
  K[d] = T[d] == "{"  # an object expects a key next
}
function str(v) { if (d && K[d]) { key[d] = v; K[d] = 0 } else val(v, 1) }
function outside(x,   L, j, c, w) {  # the structure between strings, one char at a time
  L = split(x, CH, "")  # not substr(): BSD awk measures the whole string on every call
  for (j = 1; j <= L; j++) {
    c = CH[j]
    if (!(c in SEP)) { add(c); w = 1; continue }
    if (w) { val(take(), 0); w = 0 }
    if (c == "{" || c == "[") { val("", 0); T[++d] = c; K[d] = c == "{"; key[d] = "" }
    else if ((c == "}" || c == "]") && --d < 0) return 0
  }
  if (w) val(take(), 0)
  return 1
}
BEGIN {
  RS = "\001"; HX = "0123456789abcdef0123456789ABCDEF"
  for (i = 1; i < 256; i++) chr[i] = sprintf("%c", i)
  ESC["\""] = "\""; ESC["/"] = "/"; ESC["b"] = "\010"; ESC["f"] = "\014"; ESC["n"] = "\001"; ESC["r"] = "\r"; ESC["t"] = "\t"
  SEP["{"] = SEP["}"] = SEP["["] = SEP["]"] = SEP[":"] = SEP[","] = SEP[" "] = SEP["\t"] = SEP["\r"] = SEP["\001"] = 1
  # python re on the command: \s is Unicode whitespace (as UTF-8 bytes), \b
  # is ASCII. A newline is \001, so no newline reaches split(), which BSD
  # awk would also cut there.
  S = "([ \t\001\013\014\r\034-\037]|\302[\205\240]|\341\232\200|\342\200[\200-\212\250\251\257]|\342\201\237|\343\200\200)*"
  W = "[^A-Za-z0-9_;\001]"
  HEAD = "(^|[;&|(){}\001])" S "(until|while)" W
  RB = HEAD "[^;\001]*output[.]done"
  RC = HEAD "([^;\001]*" W ")?(pgrep|pidof|kill -0|ps )"
}
NR == 1 { s = $0 }
NR > 1 { more = 1; exit }
END {
  if (more) exit
  if (index(s, "\n")) {  # every raw newline becomes \001, as a decoded one does
    k = split(s, D, "\n")
    for (i = 1; i < k; i++) D[i] = D[i] "\001"
    s = join(k)
  }
  # Cut at every backslash: a piece after the first starts with an escape,
  # and the quotes in the rest of it open and close strings. An open
  # string is built with add() and read at its closing quote.
  n = split(s, B, "\\")
  for (i = 1; i <= n; i++) {
    x = B[i]; e = ""
    if (i > 1) {
      if (!ins) exit  # a backslash outside a string
      if ((c = substr(x, 1, 1)) in ESC) { e = ESC[c]; x = substr(x, 2) }
      else if (x == "" && i < n) { e = "\\"; x = B[++i] }  # \\ : the next piece is plain text
      else if (c == "u" && (cp = hex(x)) >= 0) {
        if (cp >= 55296 && cp < 56320 && length(x) == 5 && i < n && (lo = hex(B[i + 1])) >= 56320 && lo < 57344) {
          cp = 65536 + (cp - 55296) * 1024 + lo - 56320; x = B[++i]  # a surrogate pair
        }
        e = utf8(cp); x = substr(x, 6)
      } else exit
    }
    if (!index(x, "\"")) {  # most pieces hold no quote: one step, no function call
      if (ins) { sb = sb e x; if (length(sb) > 256) { D[++m] = sb; sb = "" } }
      else if (!outside(x)) exit
      continue
    }
    sb = sb e
    k = split(x, Q, "\"")
    for (j = 1; j <= k; j++) {
      if (j > 1) { ins = !ins; if (!ins) str(take()) }  # a quote
      if (ins) add(Q[j])
      else if (!outside(Q[j])) exit
    }
  }
  if (ins || d || !bash) exit
  c = strip(cmd)
  if (c ~ RB) print "B"
  else if (aid && bg) print "A"
  else if (c ~ RC) print "C"
}' 2>/dev/null)

WAIT='wait in the foreground on the process itself: `until ! pgrep -f <pattern> >/dev/null; do sleep 10; done` under its own `timeout` sized to the run, then read the task .output file. Bracket the first letter of the pattern (`<[p]attern>`) so pgrep cannot match its own command line.'
case $rule in
  B) reason="Denied: no \`.output.done\` marker is ever written for a background task, so this loop never ends. To wait for a command that was auto-backgrounded, $WAIT Better: give the command itself a \`timeout\` sized to the run so it is never backgrounded." ;;
  A) reason="Denied: subagents never background commands. You run as a background subagent, and background commands started by a background subagent keep running after its final report with nobody left to stop them (tools-reference, Background commands). Run the command in the foreground with an explicit \`timeout\` sized to the run (the default is 15 min; past its timeout a simple command is auto-backgrounded and a pipeline is killed). If a command was already auto-backgrounded, $WAIT Never poll for a \`.output.done\` marker; none is written." ;;
  C) reason='Denied: a bare wait on a process never ends on its own \u2014 the Bash tool timeout backgrounds a loop instead of stopping it. Wait once, under the timeout command, sized to the remaining run: `timeout <N> bash -c \"until ! pgrep -f <[p]attern> >/dev/null; do sleep 10; done\"`, then read the task .output file. If that wait expires the run is hung: stop its process tree (`pkill -f`), or report it to the lead when sibling agents run the same tool; change the code under test, and never rerun identical code or write a second wait.' ;;
  *) exit 0 ;;
esac
printf '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "%s"}}\n' "$reason"
exit 0
