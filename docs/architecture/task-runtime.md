# Task Runtime

Alfredo Task Runtime answers: "what are we doing now?"

It is separate from memory. Memory records durable knowledge, decisions, and
lessons. Task Runtime records current work: tasks, dependencies, ownership,
sessions, checkpoints, blockers, validations, changed files, and next actions.

## Entities

- Run: a larger objective or orchestration unit.
- Task: a durable unit of work with acceptance criteria and dependencies.
- Session: one temporary worker instance using any supported adapter/provider.

Agents are workers. Alfredo owns the work.

## Disk layout

```text
.alfredo/
├── tasks/
│   └── ALF-01K....json
├── task-events/
│   └── EVT-01K....-ALF-01K....json
├── sessions/
│   └── SES-01K....json
├── runs/
│   ├── RUN-01K....json
│   └── RUN-01K..../
│       └── manifest.json
├── context/
│   └── index.yaml
└── locks/
    └── task-ALF-01K....lock
```

JSON is used for persisted runtime documents because the existing CLI already
uses deterministic JSON for source, lockfile, and installed-state contracts.
YAML is accepted for `context/index.yaml` because it is usually authored by
humans.

## IDs

Runtime IDs use a prefix plus a 20-character Crockford-base32, ULID-like value:

- `ALF-...` for tasks.
- `SES-...` for sessions.
- `RUN-...` for runs.
- `EVT-...` for task events.

This avoids a global incremental counter and is safer when multiple local
workers create files concurrently. Human incremental display IDs can be added
later as a separate field if needed.

## Task State Machine

Persisted states:

- `BACKLOG`
- `CLAIMED`
- `DOING`
- `VERIFYING`
- `BLOCKED`
- `DONE`
- `CANCELLED`

`READY` is derived, not persisted. A task is ready when it is `BACKLOG`, has no
owner, is not blocked or terminal, and all required dependencies are `DONE`.
Persisting `READY` would duplicate dependency state and make stale data likely.

Allowed transitions:

- `BACKLOG -> CLAIMED | BLOCKED | CANCELLED`
- `CLAIMED -> DOING | BACKLOG | BLOCKED | CANCELLED`
- `DOING -> VERIFYING | BLOCKED | BACKLOG | CANCELLED`
- `VERIFYING -> DONE | DOING | BLOCKED | BACKLOG | CANCELLED`
- `BLOCKED -> BACKLOG | CANCELLED`

`DONE` and `CANCELLED` are terminal.

Ownership rules:

- A task must be claimed before `DOING` or `VERIFYING`.
- A task cannot be claimed when dependencies are unsatisfied.
- A claim must name an existing active session whose adapter matches the claim.
- A second claim is rejected while an owner exists.
- Releasing a task clears `owner`, records `previous_owner`, and returns it to
  `BACKLOG`.
- Closing a session releases its non-terminal claimed tasks for handoff.

## Dependencies

Dependencies form a DAG. Alfredo rejects unknown dependencies and circular
dependencies. `alfredo task ready` returns only claimable tasks whose dependency
closure is satisfied.

A task may belong to a run. Referencing an unknown run is rejected so the task
graph does not accumulate orphan orchestration pointers.

## Checkpoints

Checkpoints are compact operational summaries. They may include completed work,
current focus, remaining work, changed files, validation outcomes, blockers, and
next action. They must not include private reasoning, full transcripts, large
logs, or raw tool output unless summarized.

The current task file is the efficient snapshot. `task-events/` records
append-only event documents for a minimal audit trail. This is intentionally
smaller than full event sourcing: recovery reads the snapshot, while audits can
inspect key transitions and checkpoint updates.

## Concurrency

The runtime uses exclusive lock files under `.alfredo/locks/`. Creating a file
with exclusive mode is atomic on macOS, Linux, and Windows, which makes it
portable enough for local multi-process coordination. Writes use temporary files
with flushed content and atomic rename into place.

Protected operations include claim, release, state transitions, dependency
updates, checkpoints, and session close.

## Memory Relationship

Task Runtime does not copy itself into memory. At session close, memory capture
may record a compact statement such as: session `SES-X` ended, worked on
`ALF-Y`, checkpoint persisted. The checkpoint remains canonical in `.alfredo/`.
