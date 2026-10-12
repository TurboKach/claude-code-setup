### Stage 5 → push — no record of the verified HEAD, and nothing checks it at push time

**What.** Record what the gate verified, on the commit it verified, and check that record when
a push is about to happen. One mechanism, three uses: the freshness check at push, the doctrine
version each arc ran under, and the data for the escape-rate metric
(docs/todos/escape-rate-metric.md).

**Why.** "The gate is the whole range at a single HEAD" (feature-workflow stage 5) is a rule
the master keeps in mind; nothing enforces it. Commits that land after the clean verdict
(docs fixes, handoff notes, a "tiny" change) go out under a review that never saw them. The
2026-10-12 weekly arc review measured it: after the final verdict, 3 of 6 masters re-ran codex
and 3 pushed past the gated head. Idea source: "AI Broke the Assumptions Behind CI"
(https://stack72.dev/ai-broke-the-assumptions-behind-ci/), an attestation tied to the final
commit that goes stale once the branch moves.

**Context.** Proposed shape, which the implementing arc settles:
- **The record is a git note** (`git notes --ref=verified`) on the verified commit, not a file.
  It lives in the repo but outside the tree, so no scratchpad cleanup loses it. Notes are not
  pushed by default, so team repos get no noise. A rebase drops the note, which is correct: a
  rewritten commit is unverified.
- **`codex-challenge.sh` writes a run note mechanically on every run**: range, head,
  model/effort, exit, verdict path, and a doctrine fingerprint. The fingerprint is the kit's
  `installed` SHA plus a sha256 over the instruction files actually loaded (`~/.claude/CLAUDE.md`,
  `agents/*.md`, the skills' `SKILL.md`). The installed SHA alone misses local CLAUDE.md edits,
  because install never overwrites CLAUDE.md.
- **At gate close the master adds the verdict**: the triaged verdict (≤2,000 chars, so it fits
  in a note), full-suite executed/skipped/failed counts, and the spec-reviewer result. The
  one-shot path does the same at its cross-review close.
- **A PreToolUse hook on `git push`** compares HEAD with the newest clean record. If they
  differ, it denies the push and lists the commits after the verified head with their files.
  The owner then re-runs the review on that delta, or pushes knowingly. The hook parses the
  command structurally, not with a regex.

Open policy question for that arc: does a docs-only delta need a re-review? (The C1 split above.)

**Depends.** Nothing.

**Effort.** One pipeline arc. The work touches `codex-challenge.sh` (run note), a new hook plus
its install registration, and stage-5 / stage-6 / one-shot doctrine sentences. Test the hook
with a fixture repo, the way `hooks/tests/` already does.
