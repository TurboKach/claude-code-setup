# Handoff for the next session

Written 2026-08-19. This file is standalone — a fresh session needs nothing else
to start. It carries **two independent items**:

1. **Structured verdict schema for the codex gate** — designed and decided, ready
   to plan and build. Starts below.
2. **Task-list blocking is stricter than it needs to be** — an owner
   observation, not yet investigated. At the end of this file.

Do them in either order; they don't touch the same files.

---

# 1. Structured verdict schema for the codex gate

Read this, then read the four files listed under "Where the contract lives
today."

## What you are building

The `/codex` review gate currently ends with a **prose** verdict. The runner
agent writes a triage by hand, in a shape described only in prose, and the
master session takes it at its word. Replace that with a **structured** verdict
the master can check rather than trust.

The design combines two vocabularies deliberately — this is not "adopt the
OpenAI plugin's schema."

**Keep from the current kit** — the `class` axis, because it decides routing:

| class | what it means | routing |
|---|---|---|
| `real` | a genuine defect in the diff | fix loop |
| `regression` | behavior that worked before and doesn't now | fix loop, always P1 |
| `test-gap` | missing coverage, not a defect | fix-or-defer question |
| `theoretical` | reachable only via a path that can't occur | fix-or-defer question |

**Adopt from `codex-plugin-cc`'s `schemas/review-output.schema.json`** — precise
anchoring (`file`, `line_start`, `line_end`) instead of a hand-written
`file:line — summary` string, plus `confidence` and `recommendation`.

**SHIPPED 2026-08-19 — this section is history, not a spec.** The owner chose
to tighten the existing prose contract rather than build the JSON schema below:
counts are recomputed by the master from the finding lines, `confidence` rides
on the `[P1 conf:0.8]` prefix, and a finding is one line. See commits `739fbb6`
and `33da61a`. Read the rest for the reasoning, not for instructions.

**Owner decisions, already settled — do not re-gate these:**

- `test-gap` carries **no** priority. **Superseded:** `theoretical` carries no
  priority either — the P1/P2 definitions are about reachability, and a
  theoretical finding is by definition unreachable, so neither label applies.
  Priority routes the fix loop, which neither class ever enters.
- `confidence` is **mandatory** on every finding, auto-added by the runner, not
  optional.
- Priority stays `P1`/`P2` with the existing definitions: P1 = wrong behavior,
  data loss, or a regression reachable in normal use; P2 = real but reachable
  only through unusual or pathological input; a regression is always P1.

**The part that is neither** — the master computes the top-level verdict from
the findings (clean = zero `real` and zero `regression`) instead of the runner
asserting "clean" in prose.

## Why — the motivating failure

In round 1 of the prompt-smith retirement arc (2026-08-19), the runner labelled
a finding `[P2]` and then spent a paragraph arguing it wasn't really a problem.
The master had to referee a narrative. With a schema that is a `confidence`
value and a `class` field, not prose to adjudicate.

A second, sharper instance: across two features this session the runner reported
counts on its first line and then listed findings that didn't always match those
counts. Nothing checked the arithmetic because nothing could.

## Where the contract lives today

Read all four before changing anything — the verdict shape is described in more
than one place and they must not drift (the kit has already been bitten twice
this week by exactly that failure mode):

- `skills/feature-workflow/SKILL.md` — stage 5 (the fix loop, round-of-3 rules,
  the fix-or-defer question) and the **"Verdict size contract"** bullet under
  *Token discipline*, which fixes the ≤2,000-char rendered shape, the
  group-by-class ordering, and the rule that the master never reads the raw
  challenge-output file.
- `skills/agent-teams/SKILL.md` — the CODEX step in the pipeline block.
- `global/CLAUDE.md` — the `/codex` ship gate hard rule (mirrored to
  `~/.claude/CLAUDE.md`; keep them byte-identical).
- `~/.claude/skills/gstack/codex/SKILL.md` — gstack's own skill. **Not in this
  repo.** It returns Codex's output verbatim under a `CODEX SAYS` block with a
  `Recommendation:` line; it has no schema of its own. Decide early whether you
  are changing gstack or only the runner spawn prompt that wraps it.

## The decision that shapes everything

The triage happens in the **runner agent**, not in gstack and not in Codex.
So there are two places the schema could be enforced:

1. **Runner spawn prompt only** — the runner is told to return JSON matching a
   schema. Cheapest, no gstack change, but nothing validates the JSON.
2. **A `StructuredOutput`-style contract** — the runner is forced to emit
   validated structured data. Stronger, and it is what makes "the master
   computes clean" trustworthy rather than aspirational.

Option 2 is the point of the exercise; option 1 reproduces today's
trust-the-prose problem in JSON clothing. Confirm with the owner before
committing to the heavier path.

## Constraints

- **The master must still never read raw challenge output.** The size contract
  exists because those files are huge. A schema changes the *shape* of what the
  runner returns, not the rule that the runner is the only channel.
- **Rendered output stays.** The ≤2,000-char grouped-by-class summary is what
  the owner reads. It should be *derived* from the structured data, not written
  a second time by hand.
- **`fable` never in a subagent.** Runners are `sonnet`; reviewer agents run at
  effort `medium` (review accuracy holds at lower effort — Opus 5 guide).
- This is a **pipeline**, not a one-shot: 3+ doctrine files and a real design
  decision. Plan mode, `team-planner`, `team-plan-reviewer`, `ExitPlanMode`.

## Reference material

Six real verdicts produced by the current prose contract, from this session —
use them as test cases for any schema you design. Every one should round-trip
into the new shape without losing information:

```
/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/5216f638-c3e8-4e76-a319-5478f71e801f/scratchpad/
  codex-prompt-smith-round1.md
  codex-prompt-smith-round2.md
  codex-prompt-smith-round3.md
  codex-install-consolidation-round1.md
  codex-install-consolidation-round2.md
  codex-install-consolidation-round3.md
```

These live in the session scratchpad and **will not survive** indefinitely. If
you need them, copy them somewhere durable before starting.

The plugin's schema, for the fields worth borrowing:
`~/.claude/plugins/cache/openai-codex/codex/1.0.6/schemas/review-output.schema.json`

---

# 2. Task-list blocking is stricter than it needs to be

**RESOLVED 2026-08-19 — stage 3 now chains only real dependencies.**

Evidence from the four past arcs: `auto-update` steps 1–2 (disjoint new files)
and `gate-and-backlog-discipline` steps 1–2 (*different repos*, and the plan
said so in prose at its line 21) were independent and got serialised anyway;
`codex-gate-goal-granularity` and `prompt-smith-retirement` were genuinely
linear. Measured cost of the strict chain: zero — no step ever idled behind a
bogus dependency. It was relaxed because the information loss was real, not
because it had hurt yet.

The docs back the looser rule: nothing in them asks for one-unblocked-task,
teammates self-claim "the next unassigned, unblocked task" with file locking
against simultaneous claims, and the stated guidance is conditional —
independent + non-overlapping files parallelise, "for sequential tasks,
same-file edits, or work with many dependencies, a single session or subagents
are more effective." Concurrency caps at 20 (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`).
Note `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` became *required* in v2.1.233 — the Task
tools are no longer served by default on Sonnet 5 / Opus 4.8 / Fable 5+.

The original observation follows, unchanged.

## The observation

The master chains every task in the list behind the previous one, so `TaskList`
surfaces exactly one actionable task at a time. That is correct when the steps
genuinely depend on each other, and wrong when they don't — it serialises work
that could run in parallel, and it hides from the list the fact that two steps
were independent.

## What the doctrine actually says

The two pipelines disagree, and the disagreement is the interesting part:

- `skills/feature-workflow/SKILL.md`, stage 3: *"Chain them with `TaskUpdate
  addBlockedBy` so the order lives in the list, not just the plan: **each step
  blocked by the previous one**, the codex task by the last step, the
  fix-or-defer task by codex, tests/handoff/no-live-agents by everything before
  — then `TaskList` shows **exactly one unblocked task at a time**."*
  Strictly linear, and one-unblocked-task is stated as the goal rather than a
  consequence.

- `skills/agent-teams/SKILL.md`, step 1: *"mirror the units into the native task
  list (one task per unit, `owner` = the executor that gets it, `addBlockedBy`
  **for any cross-unit ordering**; REVIEW/MERGE/CODEX tasks blocked by the
  units)"*. Dependencies only where they exist — which is what a parallel
  fan-out needs.

So the kit does distinguish, but it splits on **which pipeline you are in**
rather than on **whether the steps actually depend on each other**. A
feature-workflow run whose steps happen to be independent has no way to say so.

## Why it may not matter as much as it looks

feature-workflow is the *sequential* pipeline by definition — parallel work is
supposed to be routed to agent-teams instead. So the strict chain may be a
deliberate expression of "if these could run in parallel, you picked the wrong
pipeline." Before changing anything, establish whether that is the actual intent
or an accident of wording. Ask the owner; do not assume from the text.

## Questions worth answering

- Are there real feature-workflow arcs with genuinely independent steps, or does
  the mechanism picker already route those to agent-teams? Look at
  `docs/prompts/*-plan.md` for past arcs and check whether any plan's steps were
  independent.
- Does one-unblocked-task-at-a-time buy anything on its own — as a focus device,
  or a guard against the master starting work out of order — independently of
  whether the steps depend on each other?
- If the rule should relax, what does the plan need to carry so the master knows
  which steps are independent? The plan already names who executes each step;
  it does not currently say what each step depends on.

## Precedent in this session

The prompt-smith retirement arc used the strict chain (#1→#2→#3→#4→#5, with #5
blocked by all of them). It happened to be genuinely sequential — the edits had
to land before verification, which had to land before the codex challenge — so
the chain cost nothing there. That is a data point for "the strict rule is
usually harmless," not evidence that it is right.

## What was decided against

Migrating the gate to `codex-plugin-cc` itself. Its `/codex:review` and
`/codex:adversarial-review` commands carry `disable-model-invocation: true`, so
no subagent can call them — confirmed current at v1.0.6 and visibly enforced
(they don't appear in a session's skill list). `codex:rescue` is delegation of
coding work, not review. Both paths wrap the same local `codex` CLI and auth, so
there is no cost or model difference to gain either way. Keep
`Skill(codex, "challenge <feature-base-sha>..HEAD")`.
