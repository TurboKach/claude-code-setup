### `skills/feature-workflow/SKILL.md:39` — the unattended next-arc launch may be refused by the auto-mode classifier

The unattended handoff launches the next master as one foreground Bash:
`cd <repo> && claude --bg --name <this session's name> --permission-mode auto "$(cat <brief>)"`.
From a master in auto mode, a launch of the same shape
(`claude --bg --permission-mode auto --settings <file> "<prompt>"`) was denied by the
classifier as "Create Unsafe Agents".

The documented default block is broader than its example
(https://code.claude.com/docs/en/permission-modes.md, "What the classifier blocks by default"):
"Launching an autonomous agent loop that runs without human approval or a sandbox, such as one
started with `--dangerously-skip-permissions` or `--no-sandbox`." A `--permission-mode auto`
child keeps its own classifier, so the doc's example doesn't obviously cover the handoff. The
observed refusal says the classifier treats it as covered anyway, at least when the owner hasn't
asked for the launch.

**Open:** whether delegated approval in the transcript changes the verdict. Run one unattended
handoff under delegated approval in auto mode. If it's refused, the doctrine needs a fallback in
one clause: an attended handoff, or a Bash allow rule for that exact launch shape, documented in
INSTALL.md.
