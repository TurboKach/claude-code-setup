# Tech debt

Known gaps, deliberately left unfixed. Each entry names the exact site, what's
wrong, why it's deferred rather than fixed, and the review that surfaced it —
so the next person touching that code inherits the reasoning, not just the
gap.

## Entries

### `install.sh:77` and `INSTALL.md:84` — `RETIRED_AGENTS` entries aren't validated as plain basenames

Neither the installer's `RETIRED_AGENTS` array nor the wizard's matching loop
checks that an entry is a bare filename. A future entry like
`../rules/custom.md` resolves outside `~/.claude/agents/` in both removal
paths, deleting a file elsewhere under `~/.claude/` instead of a retired
agent. In the wizard specifically, `$name` is also unquoted in `[ -e
~/.claude/agents/$name ]`, so an entry that's the single character `*` would
glob-expand against the wizard's own working directory rather than staying a
literal filename.

**Deferred because:** only reachable through a mistaken future array entry,
not through current data — `RETIRED_AGENTS` has exactly one element
(`team-prompt-smith.md`) today, and it's a plain basename. Recorded per the
round-3 `/codex challenge` verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/5216f638-c3e8-4e76-a319-5478f71e801f/scratchpad/codex-prompt-smith-round3.md`.

### `install.sh:57-67` vs `install.sh:77-85` (and the equivalent pair in `INSTALL.md`) — no disjointness check between shipped and retired agents

Both installers run a copy loop over every file in `$SRC/agents/*.md` before
the retirement-prune loop runs. If a maintainer ever lists a name in
`RETIRED_AGENTS` that's *also* still shipped (e.g. adds `team-executor.md` to
the retired list without first deleting `agents/team-executor.md` from the
repo), the copy loop backs up the user's existing agent and installs the kit
version, then the prune loop backs up that just-installed version over the
same backup path and deletes the destination — losing the user's original
copy and leaving the agent missing entirely after install.

**Deferred because:** only reachable through a mistaken future array entry,
not through current data — the one retired name today
(`team-prompt-smith.md`) is not present in `agents/*.md`. Recorded per the
round-3 `/codex challenge` verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/5216f638-c3e8-4e76-a319-5478f71e801f/scratchpad/codex-prompt-smith-round3.md`.
