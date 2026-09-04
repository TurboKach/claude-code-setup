# References

Sources this kit's doctrine is built on. Facts you can't infer from the code —
not a reading list.

> **Doctrine validated against Claude Code v2.1.260 — 2026-09-04.**
> Re-check when `claude --version` has moved: read the changelog from the stamped
> version forward, decide what it means for the pipeline, then re-stamp this line.
> The claims in *Harness* below are version-dependent; the rest are not.

## Harness — authoritative, version-dependent

Anything about how Claude Code itself behaves (spawn semantics, settings, agent
frontmatter, worktrees, permissions) comes from here and nowhere else.

- What's new, weekly digest — <https://code.claude.com/docs/en/whats-new>
  (per-week detail at `.../whats-new/2026-wNN`)
- Changelog — <https://code.claude.com/docs/en/changelog>
  (raw source, easier to diff: <https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md>)
- Docs index for agents — <https://code.claude.com/docs/llms.txt>
- Subagents — <https://code.claude.com/docs/en/agents>
- Worktrees — <https://code.claude.com/docs/en/worktrees>

### Version-dependent claims encoded in this kit

| Claim | Since | Encoded in |
|---|---|---|
| `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` required for the task tools | 2.1.233 | `settings.example.json` |
| Teammate-model `/config` setting removed | 2.1.234 | `global/CLAUDE.md` |
| Subagent concurrency caps at 20 | 2.1.217 | `global/CLAUDE.md`, `skills/agent-teams/` |
| A `maxTurns` stop returns partial output, resumable via `SendMessage` | 2.1.246 | `global/CLAUDE.md` |
| `CLAUDE_CODE_SUBAGENT_MODEL` is a default; pins and agent `model:` win | 2.1.251 | `settings.example.json`, `global/CLAUDE.md` |
| Claude Fable 5.1 is the default `fable` model; the alias is deliberately unpinned | 2.1.257 | `agents/team-planner.md`, `agents/team-plan-reviewer.md`, `README.md` |
| `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` overrides every pin — never set it | 2.1.257 | `global/CLAUDE.md` |
| Subagents auto-continue after a mid-stream cutoff (sleep, dropped connection, server error) | 2.1.257 | `global/CLAUDE.md` |
| Built-in `Explore` runs on the session model capped at Opus | 2.1.198 | `global/CLAUDE.md` |
| Auto mode prompts once before the first file read outside the working directories (`permissions.blockReadsOutsideWorkingDirectories`, changelog only, untested against pinned review worktrees) | 2.1.257 | nothing yet — hypothesis |
| Frontmatter `model:` on skills and commands is honored in interactive sessions (was silently ignored); no kit skill sets one | 2.1.259 | nothing yet — lever, not doctrine |
| No mode auto-approves the plan prompt in an interactive session; bypassPermissions only stops plan mode blocking edits, `--permission-prompts none` is print-mode only, and only the user leaves plan mode without approving (Shift+Tab) — docs `permission-modes`, `cli-reference` | 2.1.260 | `global/CLAUDE.md` AFK gate, delegated-approval branches |
| Background commands started by subagents no longer stop at one hour (was `CLAUDE_SUBAGENT_BG_SHELL_MAX_MS`) | 2.1.260 | nothing — the codex run and full suite already live in the master |

## Model behavior — what the pipeline is tuned against

- Opus 5 prompting guide —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5>
  Over-verifies when the prompt also demands verification; delegates to subagents
  readily (cap it); review accuracy holds at medium/low effort; review prompts
  should ask for everything and filter in triage.
- Prompting Claude Fable 5.1 —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1>
  Start at `high`; `medium` ≈ Fable 5; `low` often beats Opus/Sonnet on cost per
  task (untested here — the planning-role experiment is the first measurement).
  Fable 5 prompts should perform well unchanged per the guide's own qualifier,
  though it documents several behavior shifts worth checking (see next entry).
  Hypothesis, unverified: Claude Code already injects this guide's snippets
  (progress updates, tool-call batching, finish-the-whole-task, delivering-work
  scope), so the kit does not repeat them.
- What's new in Claude Fable 5.1 —
  <https://platform.claude.com/docs/en/models/fable-5-1/whats-new-fable-5-1>
  Cache reads $0.25/MTok; behavior shifts vs Fable 5 (fewer progress updates,
  one tool call per turn in coding loops, whole-file rewrites, extra tests and
  scope).
- Deliberate deviation: this kit keeps per-unit disposable agents because
  measured burn grows with agent lifetime (see the token-discipline rules).
  Evidence-backed, not an oversight.
- The new rules of context engineering for Claude 5 —
  <https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models>
  Trust the model's judgment over prescriptive style rules; keep `CLAUDE.md` to
  gotchas.

## Patterns — priors and measured tradeoffs, not harness facts

The [Claude Cookbook](https://platform.claude.com/cookbook/) is API / Agent SDK /
Managed Agents territory. Read it for orchestration shapes and cost evidence;
**never** cite it for how Claude Code behaves — a Managed Agents field is not a
subagent setting. (No `llms.txt`; fetch the index page.)

- [`plan-big-execute-small`](https://platform.claude.com/cookbook/managed-agents-cma-plan-big-execute-small)
  — frontier coordinator + cheap workers vs. a rigor-matched solo-frontier
  control, with real bills. This kit's Opus-planner / Sonnet-executor split, tested.
- [`patterns-agents-orchestrator-workers`](https://platform.claude.com/cookbook/patterns-agents-orchestrator-workers)
  — the delegate-and-synthesize pattern behind the fan-out.
- [`patterns-agents-async-multi-agent-orchestration`](https://platform.claude.com/cookbook/patterns-agents-async-multi-agent-orchestration)
  — peer messaging through a hub, and spawned async subagents.
- [`tool-use-context-engineering-context-engineering-tools`](https://platform.claude.com/cookbook/tool-use-context-engineering-context-engineering-tools)
  — memory / compaction / tool-clearing, and what each costs. The token-discipline rules.
- [`patterns-agents-evaluator-optimizer`](https://platform.claude.com/cookbook/patterns-agents-evaluator-optimizer)
  — generator + evaluator loop. The review → fixer cycle.
- [`managed-agents-cma-verify-with-outcome-grader`](https://platform.claude.com/cookbook/managed-agents-cma-verify-with-outcome-grader)
  — grade-and-revise until it passes. The shape of the codex gate.
- [`cost-optimization-cost-optimization`](https://platform.claude.com/cookbook/cost-optimization-cost-optimization)
  — eval-driven cost levers, applied one measured change at a time.
- [`claude-agent-sdk-08-dynamic-workflows`](https://platform.claude.com/cookbook/claude-agent-sdk-08-dynamic-workflows)
  — parallel verifier/skeptic subagents; the Workflow tool's shape.

## Checking these links

All URLs above returned 200 on 2026-09-02. A 404 in a references file is worse
than no references file, so re-check with the stamp:

```sh
grep -oE 'https?://[^)> ]+' docs/references.md | sort -u \
  | while read -r u; do printf '%s %s\n' "$(curl -s -o /dev/null -w '%{http_code}' -L "$u")" "$u"; done
```
