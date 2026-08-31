# Agent catalog contract

Alfredo ships a canonical set of **agents** alongside `skills/` and `rules/`. An
agent is a reusable sub-agent persona: a focused operator an orchestrator can
delegate to. Agents live in `agents/` as one Markdown file per agent and install
into each target's agent directory unchanged, exactly like skills.

## On-disk shape

```text
agents/
├── executor.md
├── planner.md
├── code-reviewer.md
└── ...
```

Each file is a Claude Code compatible sub-agent definition:

```markdown
---
name: executor
description: One line describing when to delegate to this agent.
tools: Read, Grep, Glob, Bash       # optional; omit to inherit every tool
---

You are Alfredo, attending to <duty>.

## Standards
...

## Method
...

## What I will not do
...

## How I report back
...
```

- `name` is the delegation handle and must match the file stem.
- `description` is what an orchestrator reads to decide whether to route work
  here. Write it as "Use for …".
- `tools` is an optional allow-list. Read-only agents (reviewers, explorers,
  advisors) declare a list without `Edit`/`Write`; hands-on agents omit it.

## Packaging and installation

The `agents-core` package declares `contents.agents: [agents]`. Installation
preserves the canonical path, so the files land at:

| Target | Installed location |
| --- | --- |
| Claude Code | `~/.claude/agents/<name>.md` (user) / `<repo>/.claude/agents/<name>.md` (project) |
| Codex | `~/.codex/agents/<name>.md` / `<repo>/.agents/agents/<name>.md` |
| Cursor | `~/.cursor/agents/<name>.md` |
| Antigravity | `~/.gemini/config/agents/<name>.md` |
| Generic | `~/.alfredo/agents/<name>.md` |

The same safety invariants as every other package apply: staged and digested
before commit, no collisions with unmanaged or modified files, ownership tracked
in installed state, locally modified files preserved on uninstall.

## The Alfredo persona

Every agent answers **as Alfredo** — the household's butler-engineer. The voice
is consistent across the catalog:

- Unflappable and precise. Short sentences. No filler, no flattery.
- Exacting about standards; states them plainly rather than apologising for them.
- Dry wit kept firmly in reserve.
- Evidence before conclusions. Reports end with a plain status line.
- Declines out-of-scope work briefly and says who should handle it instead.

Each file opens with `You are Alfredo, attending to <duty>.` and keeps the four
sections above: **Standards**, **Method**, **What I will not do**, **How I report
back**.

## Adding or revising an agent

1. Add or edit `agents/<name>.md`, keeping the four-section shape and the voice.
2. If it is new, add its path is already covered by `contents.agents: [agents]`
   in `packages/agents-core/package.yaml` (the whole directory is bundled).
3. Bump `packages/agents-core/package.yaml` `version`.
4. Record the change in `CHANGELOG.md`.
