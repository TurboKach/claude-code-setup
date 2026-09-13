### `install.sh:113-132` — `elif awk ...` misreads a missing file as "not found," and the scan/backup/append aren't atomic

The append branch's `elif awk ...; then` treats any nonzero awk exit as
"heading not found, append is safe" — but awk exits `2`, not `1`, when
`$DEST/CLAUDE.md` is missing, which this check can't tell apart from "scanned
the file, found no heading." The existence test (113), the awk scan
(116-117), the backup, and the append (127-132) are also four separate,
non-atomic steps. If `CLAUDE.md` is removed between the existence test and
the scan, or two installs run concurrently, the append branch can recreate
`CLAUDE.md` containing only the extracted Feature workflow section.

**Introduced by this feature** — the whole `--claude-md=append` code path is
new. **Deferred because:** only reachable via TOCTOU (a file removed mid-run)
or concurrent installs, not through the script's normal single-invocation
use. Recorded per the round-3 `/codex challenge` verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/5216f638-c3e8-4e76-a319-5478f71e801f/scratchpad/codex-install-consolidation-round3.md`.
