### `skills/feature-workflow/SKILL.md:39` — the unattended next-arc launch may be refused by the auto-mode classifier

The unattended handoff launches the next master as one foreground Bash:
`cd <repo> && claude --bg --name <feature> --permission-mode auto "$(cat <brief>)"`.
From a master running in auto mode, a launch of the same shape
(`claude --bg --permission-mode auto --settings <file> "<prompt>"`) was denied by the
auto-mode classifier as "Create Unsafe Agents".

**Unverified for the handoff itself.** The denied launch was a probe the owner had not asked
for. The handoff runs under delegated approval, which the classifier may weigh differently.
Check it by running an unattended handoff under delegated approval in auto mode. If it's
refused, the doctrine needs a fallback: attended handoff, or a Bash permission rule for that
exact launch shape, documented in INSTALL.md.

Effort: one observed unattended handoff; the doctrine fallback is one clause.
