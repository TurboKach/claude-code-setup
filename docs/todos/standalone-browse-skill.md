### Own browse skill in the kit, then remove gstack — deferred 2026-10-04

**What.** Ship a short `skills/browse/SKILL.md` in this kit (the browse command reference, without
gstack's shared preamble) that drives gstack's compiled browse binary, then uninstall gstack.

**Why.** `/browse` is the only gstack skill the workflow uses (global CLAUDE.md, Tooling), yet the
whole 1.1 GB gstack checkout stays installed for it, and 61 of its skills are switched off through
`skillOverrides`. About half of `browse/SKILL.md` (gstack 1.68.2.0, lines 20-564) is gstack's shared
preamble: it calls 12 `gstack/bin/` scripts (config, telemetry, update check, learnings log,
timeline, brain sync), adds a learnings-log step to every run, and can offer to write gstack's
skill-routing block into a repo's CLAUDE.md. A prompt audit on 2026-10-04 flagged these as conflicts
with "nothing else in gstack is part of the workflow". Stop-gap applied the same day on the owner's
laptop: `gstack-config` `routing_declined true` (already set), `proactive false`, `telemetry off`
(already set), `update_check false`.

**Context.**
- The binary lives in `~/.claude/skills/gstack/browse/dist/` (`browse`, `find-browse`,
  `server-node.mjs`, `bun-polyfill.cjs`, ~120 MB), built by gstack's `./setup` with `bun`; it uses
  the Playwright Chromium under `~/Library/Caches/ms-playwright`.
- The skill's SETUP block resolves `$B` to `<repo>/.claude/skills/gstack/browse/dist/browse`, else
  `~/.claude/skills/gstack/browse/dist/browse`.
- gstack's `./setup` has no option to install a single skill.
- The browse-specific reference is `browse/SKILL.md` lines 565-1080; its `Headed Mode` examples call
  a bare `browse` command that is not on PATH (use `$B`).

**Open decisions.** Where the binary lives and how it updates (vendored `dist/` copy vs. a pinned
gstack build step in `install.sh`); whether `install.sh` uninstalls gstack or leaves that manual;
the global CLAUDE.md Tooling line.

**Effort.** One planned arc (pipeline): plan, skill text, install path, uninstall, docs.
