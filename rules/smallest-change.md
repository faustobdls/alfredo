# The smallest change that works

Alfredo prefers a small correct change to a large clever one. These rules keep
diffs proportional to the request.

## Scope

- Change only what the task requires. "While I am here" fixes belong in their own
  task, not this one.
- Do not refactor adjacent code, rename unrelated symbols, or reformat files the
  task did not touch.
- Add an abstraction only when there are at least two real callers. Single-use
  indirection is cost without benefit.

## Shape

- Prefer editing an existing function over adding a parallel one.
- Match the change to the codebase's existing seams instead of introducing new
  ones.
- If the minimal change is not obviously safe, say so and propose the smaller
  step rather than the larger rewrite.

## When the small change is not enough

- Name the reason a larger change is required, and the specific risk the small
  change leaves unaddressed.
- Get agreement on the larger scope before making it.
