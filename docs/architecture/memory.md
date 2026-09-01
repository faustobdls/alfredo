# Memory subsystem

Alfredo memory gives an agent a durable, local record of what was decided and
what was done. It is append-only by construction: the CLI concatenates new
bytes onto existing files and never rewrites history.

Memory answers: "what do we know?"

Task Runtime answers: "what are we doing now?"

These systems are deliberately separate. Memory stores durable facts,
decisions, conventions, lessons, and relevant historical summaries. Task
Runtime stores active work, ownership, dependencies, checkpoints, blockers, and
validations. A session close may write a compact memory note pointing at a task,
but the canonical checkpoint remains under `.alfredo/tasks/`.

## Overview

Memory has two independent stores. The user store holds cross-project practice;
the project store holds facts that only make sense inside one repository. Both
share the same on-disk layout, the same configuration contract, and the same
commands.

Recall is a two-tier system. Keyword ranking always works and never needs a
network. Embedding ranking is optional, is backed by a local Ollama daemon, and
degrades silently to keyword ranking whenever the provider is missing, slow, or
wrong. `alfredo memory search` never fails because of an embedding error.

## On-disk layout

```text
<memoryDir>/
├── config.json                 # versioned settings for this scope
├── MEMORY.md                   # derived index; the only regenerated file
├── journal/
│   └── 2026/
│       └── 2026-08-31.md       # append-only day file
├── notes/
│   └── 2026-08-31-decision.md  # one durable fact; never overwritten
└── index/
    └── embeddings.json         # generated vectors, excluded from search
```

A journal entry is a heading and a body:

```markdown
## 12:30:45 activity [release]

shipped the installer
```

Notes carry a dated, slugged filename derived from their title. Writing a note
whose slug already exists is refused rather than merged.

## Listing, Search, and Digest

`alfredo memory list` is an inventory view. It lists recent journal activities
and durable notes by default, newest first. Use `--kind activity` to preserve a
journal-only view or `--kind note` to inspect durable notes only.

`alfredo memory search` ranks complete searchable documents, including notes and
journals. `alfredo memory digest` is intentionally narrower: it renders a
bounded briefing from recent activity entries for handoff context.

## Scopes

| Scope | Directory | Resolution |
| --- | --- | --- |
| User | `~/.alfredo/memory` | `ALFREDO_MEMORY_HOME`, then `ALFREDO_HOME/memory`, then `$HOME`/`%USERPROFILE%` |
| Project | `<repo>/.alfredo/memory` | `ALFREDO_PROJECT_ROOT`, else the nearest ancestor containing `.git` |

Commands that read from memory default to `--scope all` and merge both stores.
Commands that write default to the `defaultScope` recorded in the user store's
`config.json`.

## Embeddings and fallback

`alfredo memory setup` probes `GET /api/tags` once. A download is attempted only
when the operator explicitly confirms it; no command ever pulls a model on its
own. `alfredo memory index` embeds only documents whose SHA-256 changed, reuses
every unchanged vector, and prunes vectors whose file was deleted. Changing the
model re-embeds everything.

Vectors are compared with a hand-rolled cosine similarity that returns `0` for
mismatched lengths and zero-magnitude vectors, so a corrupt index produces "no
match" rather than an error.

## Capture hook

`alfredo memory setup` can register `alfredo memory capture` on the Claude Code
`Stop` and `SessionEnd` events. The merge into `settings.json` is additive and
idempotent: unrelated keys survive, an already-present command is detected by
exact string match, and the previous file is copied to `settings.json.alfredo-bak`
before the first modification. A settings file that is not a JSON object is
refused, never replaced.

`capture` records that the session ended, optionally appends the first twenty
lines of `git diff --stat`, and appends a `todo`-tagged line for the agent to
replace with a real summary. Missing Git degrades silently.

Task Runtime session close can additionally append a compact project memory
entry with the session ID, close reason, worked tasks, and the fact that task
checkpoints were persisted. It does not duplicate the checkpoint payload.

## Safety invariants

- Append by concatenation; never truncate a journal or note file.
- Regenerate only `MEMORY.md`; every other file is owned by its author.
- Write through a temporary file and an atomic rename, and delete the temporary
  file on every path.
- Revalidate `config.json` on every read and reject unknown keys and versions.
- Keep `index/` and dot-prefixed paths out of search results.
- Never fail a search because an embedding provider failed.
- Never record secrets; that invariant is enforced by the shipped rules, not by
  the CLI, so it belongs in every review of memory content.
