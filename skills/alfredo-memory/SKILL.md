---
name: alfredo-memory
description: Record and recall durable project and user memory through the Alfredo CLI, using digests and search instead of reading raw memory files.
---

# Alfredo Memory

Use this skill whenever a task benefits from what was decided, learned, or attempted before. It covers recording new memory and recalling existing memory through `alfredo memory`. It is not a general note-taking guide and it never replaces reading the code itself.

## When to record

- Record a decision together with the reason it was chosen and the alternatives that were rejected. A decision without a rationale is not worth storing.
- Record non-obvious constraints: version pins, platform quirks, API limits, and anything that cost time to discover.
- Record one dated activity line per working session describing what actually changed, not what was planned.
- Prefer one durable fact per note. If a note needs the word "and" to describe its subject, it is two notes.

```bash
alfredo memory add "migrated the source registry to atomic writes"
alfredo memory add --kind note --title "Atomic registry writes" \
  "Registry writes stage to a temp file and rename, so a crash never truncates sources.json."
alfredo memory add -t android -t adb "captured a fleet screenshot baseline"
```

## When to recall

- At the start of a non-trivial task, read a digest first. It is the cheapest way to reload recent context.
- For a specific topic, search instead of listing. Search ranks by relevance; listing does not.
- Do not read `journal/` or `notes/` files directly. The journal grows without bound, and `MEMORY.md` is a derived pointer file, not a summary.

```bash
alfredo memory digest --since 14d --max-chars 1500
alfredo memory search "installation rollback" --limit 5
alfredo memory list --since 7d
```

## Command reference

| Command | Effect |
| --- | --- |
| `alfredo memory setup` | Create the store, configure recall, and install this package |
| `alfredo memory add <message>` | Append a journal entry, or write a note with `--kind note --title` |
| `alfredo memory search <query>` | Rank memory documents; falls back to keyword search |
| `alfredo memory list --since 7d` | Show recent journal entries, newest first |
| `alfredo memory digest --since 14d` | Render a compact, day-grouped briefing |
| `alfredo memory index` | Rebuild the embedding index after new entries |
| `alfredo memory capture` | Record the end of a working session |

## Token thrift

- Digest first, then search. Only fall back to `list` when the exact ordering of entries matters.
- Bound every recall: `--max-chars` for digests and `--limit` for searches.
- Never paste an entire memory file into context. Quote the one line that answers the question.
- Keep each entry between one and three sentences. Memory that is expensive to read stops being read.

## Scope

- The user store is the default. It holds cross-project practice: tool preferences, recurring pitfalls, and workflow decisions.
- Use `--scope project` for anything meaningful only inside the current repository: its architecture, its conventions, its incidents.
- When the correct scope is ambiguous, present both options and ask the user before writing. Do not guess; a fact filed in the wrong store is a fact nobody finds again.

## Safety

- Never record secrets, credentials, tokens, private keys, or personal data. Memory files are plain text on disk and are frequently synced.
- Never record the contents of `.env` files, even redacted.
- Record that a credential exists and where it is configured, never its value.
