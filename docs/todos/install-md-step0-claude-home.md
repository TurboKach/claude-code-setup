### `INSTALL.md:19` — Step 0 detection hardcodes `~/.claude`, not `CLAUDE_HOME`

The wizard's Step 0 detection (`test -f ~/.claude/CLAUDE.md`) always checks
the default home, while `install.sh` operates on
`${CLAUDE_HOME:-$HOME/.claude}` (`install.sh:79`). With `CLAUDE_HOME` set,
the wizard decides its replace/append/leave question against a different
installation than the one `install.sh` will actually modify.

**Pre-existing** — `CLAUDE_HOME` support predates this feature; this feature
didn't introduce the mismatch, it just didn't fix it while making
`install.sh` the single implementation. Recorded per the round-3 `/codex
challenge` verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/5216f638-c3e8-4e76-a319-5478f71e801f/scratchpad/codex-install-consolidation-round3.md`.
