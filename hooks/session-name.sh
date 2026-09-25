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
# Always exit 0, stderr silenced, no network, no git, no python.
set -u
export LC_ALL=C

# stdin → the cwd to name from, followed by "." (so a trailing newline in the
# path survives $(...)); nothing when the session is not to be named, or when
# the JSON can't be followed. Top-level keys only, a later duplicate wins:
# session_title absent, "", null or false; source startup/resume/fork; cwd a
# non-empty string. Strings never span lines, so each line splits on quotes;
# structure is tokenized in 1 KiB chunks, since BSD awk regex substitution
# slows down quadratically on long strings.
cwd="$(awk '
function hex4(x) {
  return H[substr(x, 1, 1)] * 4096 + H[substr(x, 2, 1)] * 256 + H[substr(x, 3, 1)] * 16 + H[substr(x, 4, 1)]
}
function utf8(c) {
  if (c < 128) return sprintf("%c", c)
  if (c < 2048) return sprintf("%c%c", 192 + int(c / 64), 128 + c % 64)
  if (c < 65536) return sprintf("%c%c%c", 224 + int(c / 4096), 128 + int(c / 64) % 64, 128 + c % 64)
  return sprintf("%c%c%c%c", 240 + int(c / 262144), 128 + int(c / 4096) % 64, 128 + int(c / 64) % 64, 128 + c % 64)
}
# Decodes a raw string. After an escaped backslash (an empty piece) the next
# backslash is the escaped one, not an introducer.
function dec(r,   n, p, k, out, intro, c, cp, lo) {
  if (!index(r, "\\")) return r
  n = split(r, p, "\\"); out = p[1]; intro = 1
  for (k = 2; k <= n; k++) {
    if (!intro) { out = out p[k]; intro = 1; continue }
    if (p[k] == "") { out = out "\\"; intro = 0; continue }
    c = substr(p[k], 1, 1)
    if (c != "u") { out = out E[c] substr(p[k], 2); continue }
    cp = hex4(substr(p[k], 2, 4))
    if (cp >= 55296 && cp < 56320 && length(p[k]) == 5 && substr(p[k + 1], 1, 1) == "u" \
        && (lo = hex4(substr(p[k + 1], 2, 4))) >= 56320 && lo < 57344) {
      cp = 65536 + (cp - 55296) * 1024 + lo - 56320; k++
    }
    out = out utf8(cp) substr(p[k], 6)
  }
  return out
}
# One token: a string ("s", raw), punctuation or a literal. At depth 1 a
# string after ":" is the current key'"'"'s value, any other string a key.
function tok(t, raw) {
  if (!depth) { if (seen++) exit; top = t == "{" }
  if (t == "{" || t == "[") {
    if (depth == 1 && val) { V[key] = t; val = 0 }
    depth++; return
  }
  if (t == "}" || t == "]") { if (--depth < 0) exit; return }
  if (depth != 1) return
  if (t == ":") val = 1
  else if (t == "s" && !val) key = length(raw) > 78 ? "" : dec(raw)
  else if (val) { V[key] = t; R[key] = raw; val = 0 }
}
# Text between strings. A literal cut by a chunk edge is held in lit.
function outside(o,   L, a, c, m, j, W) {
  if (o == "") return
  if (length(o) == 1 && index("{}[],:", o)) { tok(o); return }
  L = length(o)
  for (a = 1; a <= L; a += 1024) {
    c = substr(o, a, 1024)
    gsub(/[ \t\r]+/, " ", c); gsub(/[][{},:]/, " & ", c)
    m = split(c, W, " "); j = 1
    if (lit != "") {
      if (m && substr(c, 1, 1) != " ") { lit = lit W[1]; j = 2 }
      if (j == 2 && m == 1 && substr(c, length(c)) != " ") continue
      tok(lit); lit = ""
    }
    for (; j <= m; j++) {
      if (j == m && substr(c, length(c)) != " ") { lit = W[j]; break }
      tok(W[j])
    }
  }
  if (lit != "") { tok(lit); lit = "" }
}
BEGIN {
  for (i = 0; i < 16; i++) H[substr("0123456789abcdef", i + 1, 1)] = H[substr("0123456789ABCDEF", i + 1, 1)] = i
  E["\""] = "\""; E["/"] = "/"; E["b"] = "\b"; E["f"] = "\f"; E["n"] = "\n"; E["r"] = "\r"; E["t"] = "\t"
}
{
  n = split($0, P, "\""); i = 1
  for (;;) {
    outside(P[i])
    if (i >= n) break
    # A string: its segments end at quotes; an odd backslash run before a
    # quote escapes it. raw stops growing past 24 KiB (see cwd below).
    raw = ""; long = 0
    do {
      if (++i == n) exit
      s = P[i]; esc = 0
      if (substr(s, length(s)) == "\\") {
        m = split(s, B, "\\")
        for (b = m; b > 1 && B[b] == ""; b--) esc = !esc
      }
      if (!long) { raw = raw s (esc ? "\"" : ""); long = length(raw) > 24576 }
    } while (esc)
    tok("s", long ? "\001" : raw)
    i++
  }
}
END {
  if (!top || depth) exit 1
  t = V["session_title"]
  if (t != "" && t != "null" && t != "false" && !(t == "s" && R["session_title"] == "")) exit 1
  if (V["source"] != "s" || V["cwd"] != "s" || R["cwd"] == "" || R["cwd"] == "\001") exit 1
  src = dec(R["source"])
  if (src != "startup" && src != "resume" && src != "fork") exit 1
  # Past 24 KiB raw the path is longer than PATH_MAX (an escape decodes to
  # at least 1 byte per 6): no file to read either way.
  printf "%s.", dec(R["cwd"])
}' 2>/dev/null)" || exit 0
cwd="${cwd%.}"
[ -n "$cwd" ] || exit 0

# Repo root: walk up from the physical cwd to the first directory holding a
# .git entry (dir, or a worktree/submodule's file) — what git rev-parse
# --show-toplevel finds. No .git, a cwd inside a git dir (git fails there),
# or a cwd that isn't a searchable directory: the cwd itself.
root="$cwd"
case "$cwd" in /*) dir="$cwd" ;; *) dir="./$cwd" ;; esac
if cd -P -- "$dir" 2>/dev/null; then
  root="$PWD" d="$PWD"
  while :; do
    if [ -e "${d%/}/.git" ]; then root="$d"; break; fi
    if [ -f "$d/HEAD" ] && [ -d "$d/objects" ] && [ -d "$d/refs" ]; then break; fi
    [ "$d" = / ] && break
    d="${d%/*}"; d="${d:-/}"
  done
fi

# First "Session name:" line across the two files wins, valid or not; a file
# without one, or that can't be opened, moves on to the next. Regular files
# only (a symlink to one is fine): a FIFO would block the open, /dev/zero
# would never end. At most 1 MiB each (awk holds a whole line before it could
# stop). Lines split and trim as python's splitlines and \s did.
for f in "$root/CLAUDE.md" "$root/.claude/CLAUDE.md"; do
  [ -f "$f" ] && { : < "$f"; } 2>/dev/null || continue
  head -c 1048576 -- "$f" 2>/dev/null | awk '
  BEGIN { ws = "([ \t\037]|\302\240|\341\232\200|\342\200[\200\201\202\203\204\205\206\207\210\211\212\257]|\342\201\237|\343\200\200)+" }
  {
    n = split($0, L, /[\r\013\014\034\035\036]|\302\205|\342\200[\250\251]/)
    for (i = 1; i <= n; i++) {
      if (substr(L[i], 1, 13) != "Session name:") continue
      v = substr(L[i], 14); sub("^" ws, "", v); sub(ws "$", "", v)
      if (v ~ /^`?[A-Za-z0-9][A-Za-z0-9_-]*`?$/ && (substr(v, 1, 1) == "`") == (substr(v, length(v)) == "`")) {
        sub(/^`/, "", v); sub(/`$/, "", v)
        printf "{\"hookSpecificOutput\": {\"hookEventName\": \"SessionStart\", \"sessionTitle\": \"%s\"}}\n", v
      }
      found = 1; exit
    }
  }
  END { exit !found }' 2>/dev/null && break
done
exit 0
