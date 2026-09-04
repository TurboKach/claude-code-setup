# codex challenge — range 51d3cd9cd10a531b3a510849d3a3c8e83774368c..b5c457c5778ba5e8d7efd27542e0e57f3d0bce30 — checkout /Users/turbokach/Dev/claude-code-setup — exit 0 — 317s
hooks/subagent-no-background.sh:62 — The guard checks only `run_in_background`; `long-build &`, `nohup … &`, `setsid …`, and self-daemonizing programs pass with the flag absent and can outlive the subagent.

hooks/subagent-no-background.sh:67 — A foreground simple command exceeding the new 15-minute ceiling is auto-backgrounded after this pre-execution hook has already allowed it, so a slow or hung build recreates the original orphan-process failure.

hooks/subagent-no-background.sh:57 — Marker polling is trivially bypassed by indirection such as `marker=output.done; until [ -f "$marker" ]; do …; done`, allowing the prohibited infinite poll to survive unchanged.

hooks/subagent-no-background.sh:57 — The cross-line regex examines quoted strings, comments, and heredoc bodies as executable syntax; generating documentation containing `while … output.done` is denied even in the main session.

hooks/subagent-no-background.sh:52 — `pgrep -f <pattern>` is not correlated with the background task, so concurrent matching builds keep the waiter blocked, while launchers that change argv or exit before their workers cause premature completion and partial-output reads.

install.sh:314 — Hook paths are stored as unquoted shell commands; a supported `CLAUDE_HOME` containing whitespace makes the hook unexecutable, while shell metacharacters turn the persisted hook entry into command injection.

skills/feature-workflow/SKILL.md:47 — The global `pgrep -f 'output\.done'` close-out test is neither session- nor agent-scoped, so another Claude session’s poll—or the invoking shell’s command line—can prevent an otherwise clean workflow from completing.

docs/references.md:40 — The one-hour limit removal is attributed to 2.1.257, but it shipped in 2.1.260; compatibility decisions for 2.1.257–2.1.259 therefore use the wrong process-lifetime invariant. [Claude Code 2.1.260 changelog](https://code.claude.com/docs/en/changelog#2-1-260)