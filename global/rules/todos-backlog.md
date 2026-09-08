---
paths:
  - "TODOS.md"
  - "docs/tech-debt.md"
  - "docs/todos/**"
---

# Deferred-work index convention

The project's index — `TODOS.md`, or `docs/tech-debt.md` when there is no `TODOS.md` — is a
pure index: one line per item, grouped by priority, never an inline body. A session reads it to
decide what to pick up, so it must pay only for the entries it opens.

## Rules

- **Index line**: `- **<Title>** — <≤120-char hook> → [<context-file>](<context-file>)`, grouped
  under `Gates (P1)` / `P2` / `P3` / `Unprioritized`; deploy-blocking gates are marked
  (e.g. `**BLOCKS <target>**`) in the hook.
- **Context file**: a standalone item gets its own `docs/todos/<slug>.md`
  (What/Why/Context/Depends/Effort). A review finding's context is already the committed verdict
  file — link it instead of copying, keeping the stage-5 shape in the title:
  `- **[P2 conf:0.6] file:line** — <hook> → [docs/reviews/<verdict>.md](docs/reviews/<verdict>.md) #finding-N`.
- **Never an inline body** in the index — not a paragraph, not a repro, not a code block.
- **Completing an item** = delete its index line AND its `docs/todos/` file. Git history is the
  archive — no `done/` directory. A verdict file stays; other findings still reference it.
- **The project's own header wins.** If this file's header documents a different convention,
  follow that and leave this rule — a global default overriding a project's stated convention is
  how a multi-paragraph body landed in a file whose header said "never inline task bodies"
  (clipsy, 2026-09-08).
- **Keep it an index.** Past ~150 lines it has stopped being one: split bodies out before adding.
  Measured 2026-09-08 — `clipsy_ios/TODOS.md` was 508 lines / 112KB (~28k tokens per read) with
  78 detail files already extracted, so following the split rule for new items does not by itself
  keep the index small.
- **On finding a monolithic index** with inline bodies, offer to split it to this pattern (verify
  by byte-identical reassembly).
