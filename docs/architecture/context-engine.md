# Context Engine

The Context Engine answers: "what context does this task need now?"

This phase establishes contracts, not a RAG system. Context selection is
deterministic and file-based.

## Context Index

Projects can declare micro-contexts in `.alfredo/context/index.yaml`:

```yaml
contexts:
  multiplayer:
    description: Multiplayer architecture and protocol
    files:
      - docs/architecture/multiplayer.md
      - shared/protocol/**
```

A task can reference topics:

```json
{
  "context": {
    "topics": ["multiplayer"],
    "files": ["client/reconnect.ts"]
  }
}
```

`alfredo context build ALF-...` resolves explicit files plus files declared by
topic and returns an `alfredo.context/v1` package. Direct files must exist.
Simple directory globs ending in `/**` are expanded recursively in stable order.
More complex glob patterns are retained as references for future routing.

Markdown files under `.alfredo/personas/` are included automatically in the
`personas` source group. They keep voice and communication preferences separate
from behavioral rules and task-specific files.

## Budget

The initial estimator is deliberately cheap and deterministic:

```text
estimated_tokens = ceil(characters / 4)
```

It is an estimate, not model-specific tokenization. The context package includes
`target_tokens`, `hard_limit_tokens`, `estimated_tokens`, and the estimator
name.

## Progressive Disclosure

Skills remain on-demand capabilities. `SKILL.md` should contain triggers,
anti-triggers, the main procedure, and a map to deeper references. Agents should
not eagerly load every file under `references/`.

The context engine can later add rules, skills, memory digests, and decisions to
the same context package without changing the task runtime state model.
