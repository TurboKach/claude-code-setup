### Doctrine files — instruction text has had no line-test + provenance pass

**What.** One cut-only pass over the kit's instruction files. Apply the line test to every
sentence — "Would removing this cause Claude to make mistakes? If not, cut it." — and cut text
whose only job is to record where a rule came from. Scope: `global/CLAUDE.md`,
`global/rules/*.md`, `skills/*/SKILL.md`, `agents/*.md`.

**Why.** These files load into context — at session start, when a skill is invoked, when an agent
is spawned — so a sentence that changes no behavior still costs context on every load. Position
matters too: compaction re-attaches only the first 5,000 tokens of each invoked skill, so each
sentence cut from a long `SKILL.md` moves the rules behind it toward the part that survives.

**Context.**
- **Cut on sight:** dated incident recaps; version stamps and "since vX" clauses; status notes;
  doc citations used as justification; measurement tails; why-clauses that restate a rule;
  maintainer notes; anything the agent's frontmatter already guarantees.
- **Keep:** harness facts the model cannot infer, and exact step sequences.
- **Judge each cut for the model that reads the file.** Sonnet reads `step-executor`,
  `team-executor`, `fixer`, `codex-triage`, `spec-reviewer`, `explorer` and `team-merger`;
  `plan-reviewer` inherits the session's model and `team-reviewer` runs on Opus; the session's
  own model reads `global/` and the `SKILL.md` files. A line that works for a stronger model may
  need more detail for a weaker one, so a borderline cut in a Sonnet-read file stays.
- **Protected text** — report candidate cuts, do not apply them: the stage-5 loop rule in
  `skills/feature-workflow/SKILL.md` (the "Loop until clean" sentence, the round-5 check-in, the
  deferral sentence and the standalone-finding question); the docs-only clause in the codex gate
  of `global/CLAUDE.md`; the dedupe, pin-reason and Bash-write exclusion text in
  `skills/analyze-arcs/SKILL.md`.
- **Mechanics:** cuts only; reword only where a cut breaks a sentence. One Python script of
  exact-string replacements that aborts on a missing or non-unique match. Leave the result
  uncommitted until the owner has seen the cut list.
- **Report:** one line per cut, shaped
  `file:line — first words — category — what goes wrong if kept`, plus totals (sentences,
  bytes) and each `SKILL.md`'s post-cut size against the 5,000-token compaction budget.
- **Docs basis:** Claude Code's best-practices page (`best-practices.md:170`, written for
  CLAUDE.md): "For each line, ask: 'Would removing this cause Claude to make mistakes?' If not,
  cut it." For `SKILL.md` files, `skills.md:374` applies the same test: "apply the same
  conciseness test you would for CLAUDE.md content". The platform skill best-practices page adds
  "Only add context Claude doesn't already have". Its model line — "What works perfectly for Opus
  might need more detail for Haiku" — names Haiku, not Sonnet, and covers Skills, not
  `agents/*.md`. So keeping a borderline cut's text in a Sonnet-read agent file is the owner's
  policy, not a docs rule.

**Depends.** Nothing open. The protected text above already stands, so the pass reads the final
wording.

**Effort.** 15 files and about 125 KB are more than one step-executor finishes in roughly 100
tool calls. Split by file group — `global/` (2 files, ~19 KB), `skills/` (4 files, ~78 KB),
`agents/` (9 files, ~30 KB) — one Opus step-executor per group (judging each line against the
test is a design call), run in sequence.
