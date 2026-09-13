### `install.sh:177` — `RETIRED_AGENTS` entries aren't validated as plain basenames

The installer's `RETIRED_AGENTS` array isn't checked for being a bare
filename. A future entry like `../rules/custom.md` resolves outside
`~/.claude/agents/`, deleting a file elsewhere under `~/.claude/` instead of a
retired agent. (`INSTALL.md`'s wizard used to carry its own copy of this same
loop; it now invokes `install.sh` instead, so this is the only remaining
site.)

**Deferred because:** only reachable through a mistaken future array entry,
not through current data — `RETIRED_AGENTS` has exactly one element
(`team-prompt-smith.md`) today, and it's a plain basename. Recorded per the
round-3 `/codex challenge` verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/5216f638-c3e8-4e76-a319-5478f71e801f/scratchpad/codex-prompt-smith-round3.md`.
