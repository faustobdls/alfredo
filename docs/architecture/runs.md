# Runs

A run is a durable objective that groups tasks.

Example:

```text
RUN-01K... Implement multiplayer MVP
├── ALF-01K... Protocol
├── ALF-01K... Server
├── ALF-01K... Client
└── ALF-01K... Tests
```

Runs do not own execution. Tasks own work state and sessions own temporary
worker state. A run provides orchestration context, grouping, and eventual
summaries.

Runs use `alfredo.run/v1` and are persisted under `.alfredo/runs/`.
