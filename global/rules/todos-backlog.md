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

- **Index line**: `- **<Title>** — <≤120-char hook> → <context-file>` (bare path, no
  `[path](path)` — the duplicate cost 10 KB on a 268-line index), grouped
  under `Gates (P1)` / `P2` / `P3` / `Unprioritized`; deploy-blocking gates are marked
  (e.g. `**BLOCKS <target>**`) in the hook.
- **Context file**: a standalone item gets its own `docs/todos/<slug>.md`
  (What/Why/Context/Depends/Effort). A review finding's context is already the committed verdict
  file — link it instead of copying, keeping the stage-5 shape in the title:
  `- **[P2 conf:0.6] file:line** — <hook> → docs/reviews/<verdict>.md #finding-N`.
  A verdict outside the repo is not a context file: two backend tech-debt entries pointed at a
  `/private/tmp` scratchpad that was gone by the next session. Commit the verdict first.
- **Never an inline body** in the index — not a paragraph, not a repro, not a code block.
- **Completing an item** = delete its index line AND its `docs/todos/` file. Git history is the
  archive — no `done/` directory. A verdict file stays; other findings still reference it.
- **The project's header wins on line format and grouping, never on bodies.** A header that
  spells out a different line shape is followed (clipsy, 2026-09-08: the global default overrode a
  header that said "never inline task bodies"). A header that only describes the entries — "each
  item carries enough context to be picked up months later" — is not a convention, and no header
  licenses an inline body: the backend index took three multi-paragraph bodies on 2026-09-12 under
  exactly that reading, with the rule loaded in context.
- **Index budget: one Read — about 300 lines / 50 KB (~12k tokens).** The "pick a todo" read is the
  index alone, so it must fit one cheap Read; an index line is ~190 bytes with a bare path, so the
  auto-memory index's 25 KB (docs `memory#how-it-works`) is not the number here. Measured
  2026-09-13 — `clipsy_ios/TODOS.md` was 586 lines / 130 KB (~32k tokens) with 98 detail files
  already extracted; the per-arc close-out sections did the growing. After filing them it is 268
  lines: past that point the file is as small as the backlog is, and the lever is pruning items,
  which is the owner's call, not a format change.
- **Review close-outs**: an arc's P1/P2 findings get their own index lines (verdict-link shape
  above). Its theoretical / test-gap / unprefixed leftovers go verbatim into one
  `docs/todos/<arc>-close-out.md` with a single index line for the arc — one line, not one per
  finding.
- **On finding a monolithic index** with inline bodies: the new item still goes in the split shape
  (one line + context file) — matching the existing bodies is how the backend file grew on
  2026-09-12, with "over the kit's index threshold; I can split it when you want, not now" written
  in the same turn. The split of the rest is offered through AskUserQuestion, never that prose
  sentence (the turn walks past it). Verify a split by byte-identical reassembly.
