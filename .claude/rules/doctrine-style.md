---
paths:
  - "global/**"
  - "skills/**/SKILL.md"
  - "agents/*.md"
  - "README.md"
  - "INSTALL.md"
---

# Doctrine style

These files are read by the model every session or by a teammate installing the
kit. They carry instructions and the facts needed to follow them — nothing else.

- Test every sentence: would removing it cause a mistake? If not, cut it.
- No incident stories, dates, session names, measured counts or hours, version
  stamps, "experiment since", or doc citations as justification. The change
  goes in the file; the story stays in the commit message or the owner's local
  memory.
- Keep a harness fact the model cannot infer (what auto-backgrounds, what
  auto-delivers, what the installer never overwrites). State the fact, not how
  it was discovered.
- A rationale clause earns its place only when the rule is counter-intuitive
  without it, and then it is one clause, not a paragraph.
