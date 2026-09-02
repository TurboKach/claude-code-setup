# Tech debt

Known gaps, deliberately left unfixed. Each entry names the exact site, what's
wrong, why it's deferred rather than fixed, and the review that surfaced it —
so the next person touching that code inherits the reasoning, not just the
gap.

## Entries

### `install.sh:177` — `RETIRED_AGENTS` entries aren't validated as plain basenames

The installer's `RETIRED_AGENTS` array isn't checked for being a bare
filename. A future entry like `../rules/custom.md` resolves outside
`~/.claude/agents/`, deleting a file elsewhere under `~/.claude/` instead of a
retired agent. (`INSTALL.md`'s wizard used to carry its own copy of this same
loop; it now invokes `install.sh` instead, so this is the only remaining
site.)

**Deferred because:** only reachable through a mistaken future array entry,
not through current data — `RETIRED_AGENTS` has exactly one element
(`team-prompt-smith.md`) today, and it's a plain basename. Recorded per the
round-3 `/codex challenge` verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/5216f638-c3e8-4e76-a319-5478f71e801f/scratchpad/codex-prompt-smith-round3.md`.

### `install.sh:164-168` vs `install.sh:178-185` — no disjointness check between shipped and retired agents

`install.sh` runs a copy loop over every file in `$SRC/agents/*.md` before
the retirement-prune loop runs. If a maintainer ever lists a name in
`RETIRED_AGENTS` that's *also* still shipped (e.g. adds `team-executor.md` to
the retired list without first deleting `agents/team-executor.md` from the
repo), the copy loop backs up the user's existing agent and installs the kit
version, then the prune loop backs up that just-installed version over the
same backup path and deletes the destination — losing the user's original
copy and leaving the agent missing entirely after install. (`INSTALL.md`'s
wizard used to run the equivalent pair of loops itself; it now invokes
`install.sh` instead, so this is the only remaining site.)

**Deferred because:** only reachable through a mistaken future array entry,
not through current data — the one retired name today
(`team-prompt-smith.md`) is not present in `agents/*.md`. Recorded per the
round-3 `/codex challenge` verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/5216f638-c3e8-4e76-a319-5478f71e801f/scratchpad/codex-prompt-smith-round3.md`.

### `install.sh:116-117` — append idempotency check requires an exact `## Feature workflow` heading

The `--claude-md=append` mode's idempotency check matches only the literal
line `## Feature workflow` (CRLF-tolerant, otherwise exact). A hand-edited
variant — a trailing space, a closing `##`, or any other equivalent heading
syntax — isn't recognized as "already present," so a re-run appends a second,
duplicate section instead of skipping.

**Introduced by this feature** — the `--claude-md=append` mode is new.
**Deferred because:** it needs a deliberate decision about how tolerant the
match should be, and every previous attempt to make this check cleverer
(fence-tracking, etc.) produced new edge cases of its own — round 3
deliberately settled on this exact match as the simple, correct-by-inspection
version. Recorded per the round-3 `/codex challenge` verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/5216f638-c3e8-4e76-a319-5478f71e801f/scratchpad/codex-install-consolidation-round3.md`.

### `install.sh:113-132` — `elif awk ...` misreads a missing file as "not found," and the scan/backup/append aren't atomic

The append branch's `elif awk ...; then` treats any nonzero awk exit as
"heading not found, append is safe" — but awk exits `2`, not `1`, when
`$DEST/CLAUDE.md` is missing, which this check can't tell apart from "scanned
the file, found no heading." The existence test (113), the awk scan
(116-117), the backup, and the append (127-132) are also four separate,
non-atomic steps. If `CLAUDE.md` is removed between the existence test and
the scan, or two installs run concurrently, the append branch can recreate
`CLAUDE.md` containing only the extracted Feature workflow section.

**Introduced by this feature** — the whole `--claude-md=append` code path is
new. **Deferred because:** only reachable via TOCTOU (a file removed mid-run)
or concurrent installs, not through the script's normal single-invocation
use. Recorded per the round-3 `/codex challenge` verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/5216f638-c3e8-4e76-a319-5478f71e801f/scratchpad/codex-install-consolidation-round3.md`.

### `INSTALL.md:19` — Step 0 detection hardcodes `~/.claude`, not `CLAUDE_HOME`

The wizard's Step 0 detection (`test -f ~/.claude/CLAUDE.md`) always checks
the default home, while `install.sh` operates on
`${CLAUDE_HOME:-$HOME/.claude}` (`install.sh:79`). With `CLAUDE_HOME` set,
the wizard decides its replace/append/leave question against a different
installation than the one `install.sh` will actually modify.

**Pre-existing** — `CLAUDE_HOME` support predates this feature; this feature
didn't introduce the mismatch, it just didn't fix it while making
`install.sh` the single implementation. Recorded per the round-3 `/codex
challenge` verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/5216f638-c3e8-4e76-a319-5478f71e801f/scratchpad/codex-install-consolidation-round3.md`.

### `skills/feature-workflow/SKILL.md:17` — mixed dependency graph relies on a derived precondition

Stage 3 now chains a task only where a step consumes an earlier one's output,
so `TaskList` can show a dependent step and an independent step unblocked at
the same time. Codex round 4 argued that an un-isolated `step-executor` could
then run alongside a worktree-isolated `team-executor`.

**Declined, not fixed.** Stage 4 already states the precondition where the
choice is made — `step-executor` is "the only writer in flight" — so two
concurrent writers is not a state that rule permits, and concurrent
independent steps go to the `agent-teams` skill, which owns REVIEW/MERGE via
`team-merger` (codex read this as an ad-hoc `team-executor` spawn with no
merge owner, which the sentence does not say). Fixing it would restate a
condition the sentence already carries. Recorded because a careful reader has
to *derive* the mixed-graph case rather than read it: if it ever bites, the
minimal fix is one clause in stage 4, not a new rule. Round-4 verdict:
`/private/tmp/claude-501/-Users-turbokach-Dev-claude-code-setup/a4bff32a-75bb-4ec0-b24d-7d092e902147/scratchpad/codex-verdict-contract-round4.md`.

### `skills/feature-workflow/SKILL.md:52` — no fallback if real+regression lines alone exceed the cap

The verdict size contract now permits truncation to drop only `test-gap` and
`theoretical` lines. Codex round 4 noted there is no fallback when the real
and regression lines alone exceed 2,000 characters.

**Declined, not fixed.** It needs ~22+ real findings on a single diff, and it
cannot produce a wrong decision: clean is defined as zero real and zero
regression, the counts line is never dropped, and a verdict overflowing with
real findings is definitively not clean. Error handling for a case that
cannot change the outcome. Same round-4 verdict file as above.

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

### `skills/feature-workflow/SKILL.md:18` — the ship gate's diff range is probably ignored

Stage 5 and the `global/CLAUDE.md` ship gate both invoke
`Skill(codex, "challenge <feature-base-sha>..HEAD")`. But gstack's codex skill
parses `/codex challenge <text>` with everything after `challenge` as a **focus
area**, not a scope (`~/.claude/skills/gstack/codex/SKILL.md`, Step 1 mode
detection). The range string is then interpolated into the adversarial prompt as
a focus area, while the prompt itself still tells codex to run
`git diff origin/<base>` against the base branch detected in Step 0. So the gate
likely reviews the branch-vs-base diff rather than the recorded feature range,
and a range narrower or wider than the branch diff is silently not honored.

**Deferred because:** the fix belongs in gstack, not this kit — either a scope
flag on challenge mode, or a documented "challenge takes no range" contract that
stage 5 is then written against. Guessing gstack's intended argument shape from
this side would encode the wrong contract. Surfaced by the round-1 codex
challenge on the 2026-08-21 wall-clock doctrine edits, while verifying an
unrelated claim about challenge-mode diff scoping; not yet reported upstream.

**Resolved 2026-09-02:** measured (2026-09-01 backend and clipsy session
transcripts, 111 verdict files) — no recorded run ever diffed `origin/`;
masters bypassed the gstack path by hand-assembling each launch, which
drifted (three parser variants, 13 of 14 losing the `[codex ran]` audit
lines). `skills/feature-workflow/scripts/codex-challenge.sh` now owns the
invocation: one deterministic `codex exec` call on the explicit range, no
gstack scope-vs-focus-area ambiguity.

### Deferred from the codex-challenge arc — 2026-09-02

The stage-5 gate was clean at `ac1424d`; these are the standalone P2/test-gap/theoretical
lines the owner deferred rather than looped on. Round 3 at `5acce42` (exit 0, 1000s) found
one new P1 in INSTALL.md's readiness line, fixed in the commit that recorded this entry,
after round 2 had been clean.

1. `[P2 conf:0.5] skills/feature-workflow/scripts/codex-challenge.sh:68 — a pre-planted symlink at the --out path is followed by codex -o and the final redirect → F2 #1`
2. `[P2 conf:0.5] global/CLAUDE.md:27 — gate hard-codes ~/.claude/… while install.sh honours CLAUDE_HOME (same mismatch as the INSTALL.md Step 0 entry above) → F2 #2`
3. `[P2 conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh:41 — pin liveness keys on the wrapper shell PID, not the codex child; PID reuse can read a dead run as live → F1 #7`
4. `[P2 conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh:60 — -s read-only bounds shell writes, not MCP/connector side effects reachable from reviewed content → F1 #6`
5. `[conf:0.5] skills/feature-workflow/scripts/codex-challenge.sh:52 — test-gap: no self-check that codex actually ran the range diff; the --trace log is the only evidence → S1 test-gap #1`
6. `[conf:0.5] skills/feature-workflow/scripts/codex-challenge.sh:68 — test-gap: exit 0 with an empty .msg reports success; the stage-5 parking rule covers it only at the doctrine level → S1 test-gap #2`
7. `[conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh:65 — theoretical: every non-zero exit retries, including permanent auth/config errors (two 5-min sleeps) → S1 (dropped-for-cap line)`
8. `[conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh:60 — theoretical: no --ephemeral (present on codex-cli 0.152.0, semantics unverified); sessions accumulate on disk → S1 / F2 theoretical #2`
9. `[conf:0.4] skills/feature-workflow/SKILL.md:18 — theoretical: the unpinned stage-5 launch reads stray uncommitted working-tree state as final code → S2 theoretical #2`
10. `[conf:0.3] skills/feature-workflow/SKILL.md:22 — theoretical: unpinned slices read the final tree while triage verifies against git show <head>; consistent only while stage 5 has no writer → S2 theoretical #3`

11. `[P2 conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh:47 — the pin's worktree add runs outside the gtimeout wrapper; a hung LFS/smudge filter blocks --pin with no verdict → F3 #2`
12. `[P2 conf:0.4] skills/feature-workflow/scripts/codex-challenge.sh:45 — the fixed 10 GiB preflight ignores actual checkout and LFS size → F3 #3`
13. `[P2 conf:0.3] INSTALL.md:16 — readiness checks that codex exists, not that it is authenticated; an unauthenticated codex reads "ready" until the gate fails → F3 #4`
14. `[conf:0.3] global/CLAUDE.md:49 — theoretical: the one-shot path does not say to commit before gating; an uncommitted one-shot makes <pre-change-sha>..HEAD collapse and the script exits 64 (loud, not silent) → F3 theoretical #1`

Not deferred, because triage itself found it did not reproduce or was already documented: the
oversized single commit (fallback sentence added in `ac1424d`), "one background Bash" vs split
provision (reconciled in the skill), the unpinned live-tree tradeoff (documented in Token
discipline), the split-slice verification premise, verdict-commit-postdates-range (inherent),
and the stage-5 `--pin` premise mismatch.
