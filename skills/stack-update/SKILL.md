---
name: stack-update
description: Apply a pending claude-code-setup update — fetches upstream, shows what changed, three-way-diffs CLAUDE.md against your local edits, and re-runs install.sh. Invoke on "update the stack", "upgrade the kit", "update claude-code-setup", "is there an update", or the SessionStart hook's update notice.
---

# Stack update

This kit installs by **copying** files into `~/.claude` — once copied, an installed file has
no link back to the repo. This skill is the manual apply step for the update the SessionStart
hook noticed: fetch upstream, show what changed, gate on approval, and (critically) reconcile
`CLAUDE.md`, which `install.sh` never overwrites once it exists.

State dir: `${CLAUDE_HOME:-$HOME/.claude}/.claude-code-setup/` — `installed` (SHA last
installed), `last-check` (epoch of last poll), `disabled` (presence silences the SessionStart
check entirely; `touch` it to opt out).

Repo: `https://github.com/TurboKach/claude-code-setup.git`, default branch **`master`** (not
`main`).

## Procedure

Steps 1–3 are read-only reconnaissance — nothing outside the scratchpad clone is touched, and
no state-dir file is written, until the approval gate in step 4 passes.

1. **Read state.** Read `installed` from the state dir — this is the SHA to diff against. Do
   not modify any state file yet.

2. **Clone.** Full `git clone` (not `--depth`) of the repo into the session scratchpad. Full
   history, because step 3 needs `<installed>` reachable to diff against; the repo is ~20
   files, so a shallow clone buys nothing here. The clone is read-only reconnaissance — nothing
   is copied out of it until approval.

3. **Summarize what's new, grouped by surface.** Derive the summary from both
   `git log --oneline <installed>..HEAD` and `git diff --stat <installed>..HEAD` — raw commit
   subjects are not the deliverable, a "what changes for me" bullet list is. If `<installed>`
   is empty, unknown, or unreachable (e.g. upstream force-pushed and rewrote history), say so
   explicitly at the top of the summary and base the bullets on `git diff --stat` against the
   current working tree instead of a guessed range.

   Group bullets by the surfaces the user actually has installed, each stated in user-facing
   terms (not a hash dump):
   - `global/CLAUDE.md` → their always-on rules — what changed, in a sentence.
   - `skills/*` → which skills are new or changed.
   - `agents/*` → which role agents changed.
   - `install.sh` / `settings.example.json` → what the installer will now do differently.
   Omit a group with no changes.

4. **Approval gate #1 — apply the update at all?** `AskUserQuestion`: "Apply this update?" with
   options *Apply* / *Show the full diff first* / *Cancel*.
   - *Show the full diff first* → show it, then re-ask this same question; it is not itself an
     answer.
   - *Cancel* → stop here. **Nothing is written and the state dir is left exactly as it was** —
     do not touch `installed` or `last-check`, so the update notice correctly reappears next
     session.
   - Silence, or the question going unanswered, is not approval — never infer Apply from a
     default or from the user being away.
   - Only *Apply* proceeds past this point.

5. **The `CLAUDE.md` three-way diff and approval gate #2 — this is the step that justifies the
   skill.** `install.sh` deliberately never overwrites an existing `~/.claude/CLAUDE.md` (see
   `install.sh:35-39`) — it just prints a reminder to merge by hand. So step 6's install
   refreshes skills and agents but silently skips the single most important file, and a
   two-way diff can't tell an upstream improvement apart from the user's own customization. Do
   it properly:
   - `git show <installed>:global/CLAUDE.md` — what the user last installed.
   - the clone's `global/CLAUDE.md` — what upstream has now.
   - the live `~/.claude/CLAUDE.md` — the user's file, possibly hand-edited.
   Diff the first two to isolate what actually changed upstream, then show that upstream
   change against the live file. Then a **separate** `AskUserQuestion` — approving the bundle
   in gate #1 is not approval to rewrite `CLAUDE.md`, it's a distinct decision because the
   live file may carry local edits — with three choices: apply the upstream hunks (back up the
   live file first, preserve any local edits that don't conflict) / show the full diff and let
   the user decide by hand / skip `CLAUDE.md` entirely. **Never** rewrite
   `~/.claude/CLAUDE.md` without an explicit answer to this question — silence is not approval.

6. **Install.** Run `./install.sh` from the clone. It already backs up skills and agents to
   `~/.claude/.backup-<stamp>` and merges settings.json keys — reuse it, don't reimplement its
   logic here.

7. **Update state.** Only now write to the state dir: write the clone's new HEAD SHA into
   `installed`, and delete `last-check` so the next session re-polls fresh instead of trusting
   the 24h cache.

8. **Tell the user to restart Claude Code.** Skills, agents, hooks, and settings `env` are all
   read at session start — nothing applied by this run is live in the current session until
   it's restarted.

## Opt-out

`touch ~/.claude/.claude-code-setup/disabled` silences the SessionStart update check
permanently (delete the file to re-enable).
