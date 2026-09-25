### `install.sh:429` — `register_hook` stores the hook command path unquoted

`register_hook` writes `{"type": "command", "command": path}` with `path`
as-is. The harness runs `command` through a shell, so a `CLAUDE_HOME` (or home
directory) containing a space splits the path and every kit hook silently
no-ops, while `install.sh` still reports it registered them.

**Pre-existing**: every hook goes through `register_hook`/`norm_path`, and the
session-name hook just uses the same path. A fix quotes the path on write and
makes `norm_path` accept both the quoted and the unquoted form, so a re-run
finds entries that already exist and doesn't add duplicates.

Effort: small — `install.sh` register/normalize plus one temp-`CLAUDE_HOME`-with-a-space
install check.
