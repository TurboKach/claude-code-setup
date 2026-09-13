### `global/CLAUDE.md:12` — simplicity mnemonic cut, salience not replaced

The line `Test: "Would a senior engineer say this is overcomplicated?" If yes,
simplify.` was removed. Codex round 1 of the consolidation noted the cut loses
a salience cue for the simplicity standard.

**Deferred, not restored.** Classified `theoretical` at `conf:0.3` by the
runner's own triage — the standard itself ("minimum code that solves the
problem", the line directly above) is unchanged, so no enforceable behavior
differs. The cut follows Claude Code's documented CLAUDE.md guidance, which
excludes *"self-evident practices like 'write clean code'"* and names the
over-specified CLAUDE.md as a failure mode: *"If Claude already does something
correctly without the instruction, delete it."* Recorded so a future session
doesn't re-litigate it. Round-1 verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/a4bff32a-75bb-4ec0-b24d-7d092e902147/scratchpad/codex-consolidation-round1.md`.
