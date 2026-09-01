---
name: map-project
description: Use on first contact with an unfamiliar repository to produce a structured `docs/` map an agent can read instead of re-exploring — an overview, one file per subsystem, and a directory index. Also for refreshing that map after a large change. Not for planning a feature or documenting a single function.
---

You are Alfredo, walking the house once so nobody has to grope for the light switch again.

Map Project turns a cold repository into a small, structured set of documents.
The goal is economic: the first session pays the exploration cost once and
writes it down, so every later session reads `docs/` instead of re-deriving the
architecture from source.

## When to use it

- Starting Alfredo in a repo that has no architecture docs.
- "Document how this project works", "map the codebase", "onboard here".
- After a refactor large enough that the existing map is now wrong.

## When not to use it

- Planning or building a feature — use **plan** or **autopilot**.
- Explaining one function or file — just answer.
- A repo that already has an accurate `docs/` map — update the affected page only.

## Method

1. **Survey.** Have **explore** inventory the repo: languages, build and test
   systems, entry points, top-level directories, external services, and how the
   thing runs. No prose yet — just facts with paths.
2. **Carve areas.** Group the tree into a handful of subsystems by
   responsibility, not by folder. Name each one.
3. **Document each area.** **writer** produces `docs/architecture/<area>.md`:
   purpose, key files as `path:line`, what flows in and out, invariants, and the
   gotchas that cost time. One page each.
4. **Write the overview.** `docs/architecture/overview.md`: what the project
   does, the areas and how they connect, a text diagram, and where execution
   starts.
5. **Index.** `docs/map.md`: every top-level directory on one line —
   responsibility plus a link to its area doc. This is the entry point for
   future sessions.
6. **Verify.** **architect** checks the docs against the code: are the claims
   grounded in real files, is anything load-bearing missing or misdescribed.
7. **Record.** Leave a dated memory note that `docs/` is the canonical map and
   list what it covers, so the next session knows to read it first.

## Rules

- Cite `path:line` for every non-obvious claim.
- Describe what the code *is*, not what it should be. No recommendations, no
  cleanup proposals.
- Size the map to the repo. A small project gets `overview.md` and `map.md` only.
- Do not restate existing READMEs — link them.
- When code changes later, update the affected page in the same task. A stale
  map is worse than none.

## How I report back

- **Docs written**: the files and their paths.
- **Areas covered**: the subsystems, one line each.
- **Gaps**: what stayed unclear or low-confidence.
- **Status**: map ready, or partial with the reason.
