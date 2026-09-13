### `install.sh:164-168` vs `install.sh:178-185` — no disjointness check between shipped and retired agents

`install.sh` runs a copy loop over every file in `$SRC/agents/*.md` before
the retirement-prune loop runs. If a maintainer ever lists a name in
`RETIRED_AGENTS` that's *also* still shipped (e.g. adds `team-executor.md` to
the retired list without first deleting `agents/team-executor.md` from the
repo), the copy loop backs up the user's existing agent and installs the kit
version, then the prune loop backs up that just-installed version over the
same backup path and deletes the destination — losing the user's original
copy and leaving the agent missing entirely after install. (`INSTALL.md`'s
wizard used to run the equivalent pair of loops itself; it now invokes
`install.sh` instead, so this is the only remaining site.)

**Deferred because:** only reachable through a mistaken future array entry,
not through current data — the one retired name today
(`team-prompt-smith.md`) is not present in `agents/*.md`. Recorded per the
round-3 `/codex challenge` verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/5216f638-c3e8-4e76-a319-5478f71e801f/scratchpad/codex-prompt-smith-round3.md`.
