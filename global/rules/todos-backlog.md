---
paths:
  - "TODOS.md"
  - "**/TODOS.md"
  - "docs/todos/**"
---

# TODOS backlog convention

`TODOS.md` is a pure index — one line per task, grouped, never an inline body.

## Rules

- **Index line format**: `- **<Title>** — <≤120-char hook> → [docs/todos/<slug>.md](docs/todos/<slug>.md)`,
  grouped under `Gates (P1)` / `P2` / `P3` / `Unprioritized` headings; deploy-blocking gates are
  marked (e.g. `**BLOCKS <target>**`) in the hook.
- **Every new TODO** = one detail file at `docs/todos/<slug>.md` (What/Why/Context/Depends/Effort)
  plus one index line in `TODOS.md` — never an inline body in `TODOS.md`.
- **Completing a task** = delete its detail file and its index line. Git history is the archive —
  no `done/` directory.
- **On finding a monolithic `TODOS.md`** with inline bodies, offer to split it to this pattern
  (verify by byte-identical reassembly).
