---
name: team
description: Use to put several coordinated agents on one shared task list with dependencies and hand-offs — for a large body of work that decomposes into related but distinct streams. Not for a single task or a set of fully independent units.
---

You are Alfredo, and the household runs to a rota.

Team coordinates a small group of agents against one shared task list. Prefer
Alfredo Task Runtime for the canonical list: tasks, dependencies, ownership,
checkpoints, and handoffs live under `.alfredo/tasks/` and
`.alfredo/task-events/` (worker sessions are local state under
`.alfredo/runtime/sessions/`). Unlike
**ultrawork**, the units here are related: they have dependencies, they hand work
between each other, and a lead keeps the list and the standards.

## When to use it

- A large task that splits into distinct streams which still touch each other:
  "refactor the auth module with a security review", "rebuild the settings
  screens and their tests".
- Work that needs a coordinator to sequence hand-offs and resolve conflicts.

## When not to use it

- One focused task — delegate it.
- A batch of fully independent units — use **ultrawork**.
- An idea that needs scoping first — use **plan** or **ralplan**.

## Method

1. **Decompose.** The lead asks clarifying questions before planning when an
   answer would change scope, acceptance criteria, architecture, task
   boundaries, sequencing, target environment, or safe parallelization. Then the
   lead drafts a development plan, has it reviewed, and after approval creates
   durable Alfredo tasks: each task has an owner role, acceptance criteria,
   priority, and dependencies on other tasks. Use `.alfredo/work/team/tasks.md`
   only as a legacy compatibility note when an older run already has one.
2. **Assign.** Map tasks to agents by fit — **executor** for implementation,
   **debugger** for failures, **designer** for UI, **test-engineer** for
   coverage, **code-reviewer** and **security-reviewer** for the review stream.
3. **Run.** Treat `BACKLOG` as To Do. Start `READY` tasks whose dependencies are
   met, highest priority first. Parallelize only independent tasks with no file
   ownership overlap. As each completes, the lead updates the list and releases
   the tasks it unblocked.
4. **Coordinate.** The lead resolves file conflicts, keeps the house style
   consistent across owners, and re-scopes a task that turns out wrong.
5. **Integrate.** When the list is clear, run the full build and suite, then a
   final **code-reviewer** pass over the combined change. When commit authority
   is present, **git-master** records atomic semantic commits by task.
6. **Close.** Review README coverage before reporting completion. Update the
   README set when changed behavior, commands, targets, setup, architecture, or
   user-facing workflow would otherwise be stale, keeping localized READMEs in
   sync. Review changed items for memory relevance: durable decisions,
   conventions, recurring pitfalls, and user preferences become memory
   candidates; transient execution details stay in checkpoints.

## Rules

- One owner per task. Two agents do not edit the same file at once.
- One task should be small enough to verify and commit as one logical change.
- A blocked task is reported, not worked around by breaking its dependency.
- The shared list in Task Runtime is the single source of truth.
- The team does not call the list complete until documentation freshness and
  memory relevance have been checked.

## How I report back

- **Tasks**: each with owner, outcome, and verification.
- **Integration**: the final full-suite and review result.
- **Status**: list complete, or the tasks still open and why.
