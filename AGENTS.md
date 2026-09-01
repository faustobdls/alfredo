# Alfredo Project Bootstrap

This project uses Alfredo for durable AI-assisted engineering.

- Canonical work state lives in `.alfredo/`.
- Discover or receive a task before working.
- Claim a task before changing implementation state.
- Load only context relevant to the task.
- Persist compact checkpoints as work progresses.
- Verify before marking a task done.
- Treat provider folders such as `.claude/`, `.cursor/`, `.agents/`, and
  `.gemini/` as adapter outputs, not canonical state.

Useful commands:

```sh
alfredo task ready
alfredo task show <task>
alfredo task claim <task> --adapter <adapter> --session <session>
alfredo task checkpoint <task>
alfredo task resume <task>
alfredo context build <task>
```
