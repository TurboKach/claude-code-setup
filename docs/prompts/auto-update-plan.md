# Auto-update for claude-code-setup

## Context

This kit installs by **copying** files into `~/.claude` (`install.sh`). Once copied, the
installed files have no link back to the repo — there is no version, no stamp, and no way
for an installed copy to know it's stale. Every user (including you, across machines) has
to remember to `git pull && ./install.sh` by hand, so improvements to `CLAUDE.md`, the
skills, and the agents silently rot in place.

Goal: borrow gstack's update loop — **notice on session start, one command to apply** —
without borrowing its weight (gstack ships `bin/gstack-config`, `bin/gstack-update-check`,
a VERSION file, CHANGELOG discipline, snooze-backoff state, and a migrations runner). For a
20-file copy-install kit, the whole mechanism is one hook script + one skill + a stamp file.

Decisions locked with you before planning:
- **Signal:** remote `master` HEAD SHA vs. the SHA `install.sh` stamped. No VERSION file,
  no bump discipline, cannot go stale.
- **Trigger:** a `SessionStart` hook. Prints nothing when up to date.
- **Behavior:** notify only. `/stack-update` applies it, and nothing touches `~/.claude`
  until you run it.

### The `CLAUDE.md` problem this has to solve

`install.sh:35-39` deliberately **never overwrites** an existing `~/.claude/CLAUDE.md` — it
just prints "merge by hand if you want it". So "update = re-run install.sh" would refresh
the skills and agents but silently skip the single most important file in the kit, and the
user would believe they were up to date. `/stack-update` therefore does a **three-way
diff**: `git show <old-sha>:global/CLAUDE.md` (what you last installed) vs the new
`global/CLAUDE.md` (what changed upstream) vs your live `~/.claude/CLAUDE.md` (your local
edits). That separates *upstream changes worth taking* from *your own customizations*,
which a plain two-way diff cannot do.

## Implementation

Every execution step is delegated to **`step-executor`** (sequential, one writer, no
worktree). The master commits per step and gates.

### Step 1 — `hooks/stack-update-check.sh` (new) → `step-executor`

The whole check. Must **never** break or slow a session start: silence stderr, always
`exit 0`, hard network timeout.

State lives in `$CLAUDE_HOME/.claude-code-setup/` (default `~/.claude/.claude-code-setup/`):
- `installed` — SHA `install.sh` last installed from
- `last-check` — epoch of the last remote poll (24h cache)
- `disabled` — presence of this file turns the check off entirely

Logic, in order:
1. No `installed` file (kit not installed by `install.sh`, e.g. a tarball) → exit silently.
   This is also the opt-out for anyone who copies files by hand.
2. `disabled` exists → exit silently.
3. `last-check` newer than 24h → exit silently.
4. Stamp `last-check` **before** the network call — a machine that's offline must not pay
   the timeout on every single session start. Cost of this: an update found while offline
   surfaces up to a day later. Correct trade for a startup hook.
5. Fetch the remote SHA with `curl -sfm 4 -H 'Accept: application/vnd.github.sha'
   https://api.github.com/repos/TurboKach/claude-code-setup/commits/master`.
   This header makes the API return the bare SHA as plain text — no `jq`, no JSON parsing,
   and `curl -m` gives a real timeout (`git ls-remote` has none, and macOS has no
   `timeout(1)`). Note the branch is **`master`**, not `main`.
   Override both via `CLAUDE_SETUP_REPO` / `CLAUDE_SETUP_BRANCH` env vars so a fork works.
6. Empty response, or SHA equal to `installed` → exit silently.
7. Otherwise print one line to stdout (SessionStart stdout is injected into session context):
   `claude-code-setup: update available (installed abc1234 → remote def5678) — run /stack-update`

### Step 2 — `skills/stack-update/SKILL.md` (new) → `step-executor`

Frontmatter `name: stack-update`, description covering "update/upgrade the stack/kit".
Prose instructions (this kit ships no runtime, so the skill is procedure, not code):

1. Read `installed` from the state dir. Force-refresh by deleting `last-check`.
2. Full `git clone` of the repo into the session scratchpad — full, not `--depth`, because
   step 4 needs `<old-sha>` reachable; the repo is ~20 files so depth buys nothing.
3. **What's new:** a bullet-list summary of the change vs the installed SHA, derived from
   `git log <installed>..HEAD` *and* `git diff --stat <installed>..HEAD`, grouped by the
   surfaces the user actually has installed (`global/CLAUDE.md`, `skills/*`, `agents/*`,
   `install.sh`/`settings.example.json`) in user-facing terms — not a commit-subject dump.
   If `<installed>` is unknown or unreachable (force-push), say so and fall back rather
   than inventing a range.
3b. **Approval gate — before any write.** `AskUserQuestion`: Apply / show the full diff
   first / Cancel. The clone is read-only reconnaissance until Apply is picked; Cancel
   writes nothing and leaves the state dir untouched so the notice correctly reappears.
   Silence is not approval. All state-dir writes happen after this gate, never before.
4. **`CLAUDE.md` three-way diff** (the step `install.sh` can't do): diff
   `git show <installed>:global/CLAUDE.md` → new `global/CLAUDE.md` to isolate the upstream
   change, then show it against the live `~/.claude/CLAUDE.md`. `AskUserQuestion`: apply the
   upstream hunks (backing up first, preserving local edits) / show the full diff / skip.
   Never rewrite `~/.claude/CLAUDE.md` without an explicit answer — this is a taste gate, and
   silence is not approval.
5. Run `./install.sh` from the clone (it already backs up skills/agents to
   `~/.claude/.backup-<stamp>` and merges settings keys — reuse it, don't reimplement).
6. Stamp the new SHA into `installed`; delete `last-check`.
7. Tell the user to **restart Claude Code** — skills, agents, hooks, and settings `env` are
   all read at session start, so nothing applied here is live in the current session.

### Step 3 — `install.sh` wiring → `step-executor`

Four additions, each following the file's existing `backup()`-then-copy idiom:
- Add `stack-update` to the skill loop at `install.sh:42` (`for skill in agent-teams
  feature-workflow stack-update`).
- Copy `hooks/stack-update-check.sh` → `$DEST/hooks/` (`mkdir -p`, back up, `chmod +x`).
- Stamp the state dir: `git -C "$SRC" rev-parse HEAD` → `.claude-code-setup/installed`.
  Guard it — if `$SRC` isn't a git checkout, skip the stamp and say so; the check then
  stays permanently silent (step 1, rule 1) rather than misfiring.
- Extend the existing `python3` settings-merge block (`install.sh:62-82`) to register the
  `SessionStart` hook. Two hard requirements, both tested in Step 5:
  - **Idempotent** — match on the command string; running `install.sh` twice must leave
    exactly one entry, not two.
  - **Non-destructive** — append into the existing matcher-`""` SessionStart group. Your
    live settings already run `peon-ping` on `SessionStart`; it must survive untouched.

### Step 4 — Docs → `step-executor`

- `settings.example.json`: add the `SessionStart` hook block so the file still shows
  everything the installer merges.
- `README.md`: table rows for `hooks/stack-update-check.sh` and `skills/stack-update/`, plus
  a short **Staying up to date** section — how the check works, the 24h cache, and the
  `touch ~/.claude/.claude-code-setup/disabled` opt-out.
- `INSTALL.md`: the wizard's Step 2 core-kit block copies the hook and writes the stamp; its
  settings-merge snippet registers the hook. Keep it consistent with `install.sh`.

### Step 5 — Verification → `step-executor`, evidence pasted back

Unit-level green is not done here; the hook has to be exercised for real.

Against a throwaway `CLAUDE_HOME=$(mktemp -d)`:
1. `install.sh` → hook present and executable, `skills/stack-update` present, `installed`
   holds the real `git rev-parse HEAD`, settings.json has the SessionStart entry.
2. Run `install.sh` **twice** → still exactly one SessionStart hook entry (idempotency).
3. Pre-seed the throwaway settings.json with the real peon-ping SessionStart block, install,
   confirm **both** hooks are present (non-destructive merge).
4. Check-script matrix — stale stamp → prints the notice; current stamp → silent; `disabled`
   present → silent; fresh `last-check` → silent; `CLAUDE_SETUP_REPO` pointed at a
   nonexistent repo → silent, `exit 0`, completes in **under 5s**.
5. **End-to-end:** with a stale stamp in the throwaway home, start a real session
   (`CLAUDE_HOME=<tmp> claude -p "say hi"`) and confirm the notice actually reaches the
   model's context — not just that the script prints to a terminal.
6. `/stack-update` dry-run against the throwaway home from an artificially old stamp:
   confirm the commit list, the three-way `CLAUDE.md` diff, and the re-stamp.

Nothing in the real `~/.claude` is touched during verification.

## Review + ship

`/codex review` on each step's diff before merge (hard gate — internal reviewers don't
satisfy it). No push without your explicit go-ahead.

## Out of scope

Deliberately not borrowed from gstack: VERSION/CHANGELOG files, snooze backoff, an
auto-apply config flag, a migrations runner, vendored/team-mode install detection. Each is
worth adding only if the simple loop proves insufficient.
