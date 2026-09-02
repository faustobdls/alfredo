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
├── config.yaml              # versioned
├── tasks/                   # versioned
│   └── ALF-01K....json
├── task-events/             # versioned
│   └── EVT-01K....-ALF-01K....json
├── runs/                    # versioned
│   ├── RUN-01K....json
│   └── RUN-01K..../
│       └── manifest.json
├── context/                 # versioned
│   └── index.yaml
└── runtime/                 # local only, git-ignored
    ├── sessions/
    │   └── SES-01K....json
    ├── locks/
    │   └── task-ALF-01K....lock
    ├── cache/
    └── tmp/
```

Everything above `runtime/` is durable project state and is committed. The
`runtime/` subtree is machine- and process-local (locks hold a PID, sessions
track a live worker) and is excluded from version control.

JSON is used for persisted runtime documents because the existing CLI already
uses deterministic JSON for source, lockfile, and installed-state contracts.
YAML is accepted for `context/index.yaml` because it is usually authored by
humans.

CLI commands discover the runtime project root by walking upward from the
current directory until they find `.alfredo/` or `.git/`. That keeps state in the
repository root even when a worker invokes `alfredo` from a subdirectory.

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

Ready work is ordered by priority first and creation time second. Recognized
high-to-low labels are `critical`/`urgent`/`p0`, `high`/`p1`,
`normal`/`medium`/`p2`, and `low`/`p3`; unknown labels sort after the known
bands but remain valid user labels.

## Master Task Flow

When a user request is larger than one direct edit, the work runs as a master
flow:

1. Convert the request into a development plan grounded in the repository.
   Before writing that plan, ask clarifying questions whenever the answer would
   change scope, acceptance criteria, architecture, task boundaries, sequencing,
   target environment, or safe parallelization.
2. Review the plan for missing acceptance criteria, risky dependencies,
   unclear ownership, and tasks that are too large or entangled.
3. After approval, create durable Alfredo tasks under the run. Each task must be
   atomic: one logical change, clear acceptance criteria, explicit dependencies,
   and a path to one semantic commit.
4. Move approved tasks into `BACKLOG`, which is the runtime's To Do state.
5. Claim and run every `READY` task that can proceed without file or dependency
   conflict. Independent tasks may run in parallel; dependent or overlapping
   tasks wait.
6. Checkpoint each task as it progresses, move it through `VERIFYING`, and mark
   it `DONE` only after evidence passes.
7. Before final completion, review the README set and update it when changed
   behavior, commands, targets, setup, architecture, or user-facing workflow
   would otherwise leave the docs stale. When localized READMEs exist, keep
   their structure and content aligned.
8. Review the changed items for memory relevance. Durable decisions, project
   conventions, recurring pitfalls, and user preferences should be proposed for
   project or user memory; transient execution details stay only in task
   checkpoints.
9. Commit completed work atomically using the repository's message convention
   before taking the next ready task, when the workflow has commit authority.
10. Continue until the master run has no open tasks, then report completion and
   any deliberate follow-ups.

## Checkpoints

Checkpoints are compact operational summaries. They may include completed work,
current focus, remaining work, changed files, validation outcomes, blockers, and
next action. They must not include private reasoning, full transcripts, large
logs, or raw tool output unless summarized.

The current task file is the efficient snapshot. `task-events/` records
append-only `alfredo.task-event/v1` documents for a minimal audit trail. This
is intentionally smaller than full event sourcing: recovery reads the snapshot,
while audits can inspect key transitions and checkpoint updates.

Task events are operational facts, not transcripts. Their `data` payload should
stay compact and must not contain private reasoning, raw logs, or unbounded tool
output.

## Concurrency

The runtime uses exclusive lock files under `.alfredo/runtime/locks/`. Creating a file
with exclusive mode is atomic on macOS, Linux, and Windows, which makes it
portable enough for local multi-process coordination. Writes use temporary files
with flushed content and atomic rename into place.

Protected operations include claim, release, state transitions, dependency
updates, checkpoints, and session close.

Lock recovery is deliberately small: a lock older than the runtime stale-lock
timeout is treated as abandoned and may be removed before retrying the atomic
create. Fresh locks fail fast with a clear error. This handles local crash
recovery without adding a daemon or distributed coordinator.

## Memory Relationship

Task Runtime does not copy itself into memory. At session close, explicit
`--capture-memory` or project memory config with `capture.sessionEndHook: true`
may record a compact statement such as: session `SES-X` ended, worked on
`ALF-Y`, checkpoint persisted. The checkpoint remains canonical in `.alfredo/`.
