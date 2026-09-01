# Sessions

A session is a temporary worker instance. It is not a task and it is not a run.

One task can move across many sessions:

```text
Claude session A -> Claude session B -> Codex session C -> Cursor session D
```

The task remains canonical in `.alfredo/tasks/`. The session records who worked,
when it started and ended, which tasks were claimed or worked, and why it
closed.

## Schema

Sessions use `alfredo.session/v1` and are persisted under
`.alfredo/runtime/sessions/SES-....json`. A session tracks a live worker, so it
is local/runtime state and is not committed; the task it worked on stays
canonical and versioned in `.alfredo/tasks/`.

Fields include:

- `id`
- `adapter`
- `agent`
- `started_at`
- `ended_at`
- `status`
- `tasks_claimed`
- `tasks_worked`
- `last_checkpoint`
- `close_reason`

Close reasons are intentionally provider-neutral:

- `completed`
- `manual`
- `context-limit`
- `provider-limit`
- `crash-recovery`
- `handoff`
- `unknown`

## Handoff

Closing a session releases any non-terminal task still owned by that session.
The task keeps `previous_owner`, checkpoint, validations, files, blocker, and
next action so another worker can resume without the previous chat transcript.

`alfredo session close --capture-memory` can append a compact project memory
entry with the session ID, close reason, worked tasks, and a pointer back to the
task runtime. The same compact capture happens automatically when project
memory config has `capture.sessionEndHook: true`. It does not copy checkpoint
content into memory.
