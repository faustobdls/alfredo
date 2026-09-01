# Alfredo

[Português do Brasil](README.pt-BR.md) · [Español](README.es.md)

Alfredo is local-first infrastructure for durable, portable AI-assisted
engineering.

Your agent is temporary. Your work is not.

Claude Code, Codex, Cursor, Antigravity, and future tools all have their own
context windows, session limits, conventions, and extension formats. Without an
independent layer, long-running work gets trapped in the current chat:
continuity is fragile, handoff is expensive, and task state is hard to audit.

Alfredo puts a portable layer between developers and AI agents. Agents become
disposable workers. Alfredo owns the durable work state, memory, skills, rules,
agents, and context references under developer-controlled local files.

## What Alfredo Provides

- Agent portability: canonical skills, rules, personas, and sub-agents rendered
  through adapters for Codex, Claude Code, Cursor, Antigravity, and generic
  targets.
- Durable memory: project and user knowledge outside the current chat.
- Durable task state: tasks, dependencies, owners, sessions, checkpoints,
  blockers, validations, and next actions outside the current chat.
- Context engineering: deterministic context packages for a specific task.
- Progressive disclosure: small `SKILL.md` entry points with deeper references
  loaded only when needed.
- Multi-agent coordination: claim, release, handoff, dependency-aware ready
  work, and resumable sessions.
- Local-first operation: state remains readable, versionable, recoverable, and
  inspectable on the developer machine.
- Provider independence: current and future agents consume Alfredo state instead
  of owning it.

## Core Model

```text
canonical state
      |
      v
.alfredo/
      |
      v
adapters
      |
      v
Claude Code / Codex / Cursor / Antigravity / future agents
```

Provider-specific directories such as `.claude/`, `.cursor/`, `.agents/`, and
`.gemini/` are adapter interfaces. They must not become independent boards or
task stores.

## Memory vs Task Runtime

Memory answers: "what do we know?"

Examples: durable decisions, facts, conventions, lessons, and relevant history.

Task Runtime answers: "what are we doing now?"

Examples: tasks, dependencies, status, ownership, sessions, checkpoints,
blockers, validations, changed files, and next action.

These are separate systems. Task Runtime may leave a compact memory reference at
the end of a session, but it does not duplicate its full state into memory.
That capture can be requested explicitly or enabled through project memory
configuration.

## Task Runtime

A project keeps durable work state under `.alfredo/`; machine- and
process-local state lives in `.alfredo/runtime/` and is git-ignored:

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
├── personas/                # versioned, seeded once by setup
│   ├── alfredo.md
│   └── user.md
├── memory/                  # versioned
└── runtime/                 # local only, git-ignored
    ├── sessions/
    │   └── SES-01K....json
    ├── locks/
    ├── cache/
    └── tmp/
```

The three runtime entities are:

- Run: a larger objective or orchestration unit.
- Task: a durable unit of work with acceptance criteria and dependencies.
- Session: one temporary worker instance using any supported adapter/provider.

`READY` is derived, not persisted. A task is ready when it is in `BACKLOG`, has
no owner, is not blocked or terminal, and all required dependencies are `DONE`.
Task events are append-only `alfredo.task-event/v1` documents, and local lock
files can be recovered after a bounded stale-lock timeout.

## Install The CLI

macOS and Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.sh | sh
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.ps1 | iex
```

The installer downloads the latest GitHub release for the current platform,
validates the SHA-256 checksum, installs into `~/.alfredo/bin`, and updates the
current shell PATH. Set `ALFREDO_INSTALL_DIR` to choose another destination.

## CLI

Install official packages for supported agents:

```sh
alfredo setup --all
```

Create and coordinate durable work:

```sh
alfredo task create --title "Implement reconnect support"
alfredo task list
alfredo task ready

alfredo session start --adapter claude
alfredo task claim ALF-... --adapter claude --session SES-...
alfredo task start ALF-...
alfredo task checkpoint ALF-... \
  --completed "protocol" \
  --current "client reconnect" \
  --remaining "tests" \
  --file lib/reconnect.dart \
  --validation unit_tests=pending \
  --next-action "write tests"

alfredo session close SES-... --reason context-limit --capture-memory
alfredo task resume ALF-...
alfredo context build ALF-...
```

Most runtime commands support `--json` for agents and tools.

Existing lifecycle commands remain available:

```sh
alfredo init source ./my-source
alfredo source add canonical --local ..
alfredo package install android-core --target codex --scope user
alfredo update --dry-run
alfredo upgrade --check
```

## Memory

Alfredo keeps durable, local memory in `.alfredo/memory/` and
`~/.alfredo/memory/`. Memory remains append-only by construction: journals grow,
notes are never overwritten, and only derived indexes are regenerated.

Recall works offline with keyword ranking. Optional local Ollama embeddings can
improve ranking and silently fall back to keywords when unavailable.

```sh
alfredo memory setup
alfredo memory add "documented the task runtime"
alfredo memory add --kind note --title "Runtime decision" "tasks are canonical"
alfredo memory list --since 30d
alfredo memory search "task handoff"
alfredo memory digest --since 14d
alfredo memory capture
```

`memory list` shows recent activity and durable notes. Use
`--kind activity` or `--kind note` when an agent needs only one class of memory.
`memory digest` remains a compact briefing of recent activity.

## Context Engineering

Projects can declare lightweight context topics:

```yaml
contexts:
  multiplayer:
    description: Multiplayer architecture and protocol
    files:
      - docs/architecture/multiplayer.md
      - shared/protocol/**
```

A task can reference topics and files. `alfredo context build ALF-...` returns a
deterministic `alfredo.context/v1` package with grouped sources and a cheap token
budget estimate. The initial estimator is `ceil(characters / 4)`, which is
explicitly approximate and provider-independent.

Markdown files in `.alfredo/personas/` are included in the `personas` source
group automatically. Use them for voice and communication preferences that
should influence generated text, notices, summaries, and handoffs without
becoming behavioral rules.

## Canonical Catalogs

Alfredo distributes reusable agent capability through canonical catalogs:

- `skills/`: on-demand capability guides, including Android domain skills and
  workflow strategies such as `team`, `ultrawork`, `ralph`, and `autopilot`.
- `rules/`: compact behavioral policies. Only a small core should stay
  always-on; specialized policies should become conditional as adapters and
  context routing mature.
- `personas/`: seed files for Alfredo's voice and the user's durable
  communication preferences. Installed personas are created when absent and
  preserved across future updates.
- `agents/`: sub-agent personas in Alfredo's voice.
- `packages/`: installable bundles such as `android-core`, `skills-core`,
  `rules-core`, `personas-core`, `agents-core`, and `memory-core`.

Adapters render these catalogs into provider-specific locations. The canonical
content remains in Alfredo.

## Repository Structure

```text
alfredo/
├── adapters/            # Agent-specific installation and rendering adapters
├── agents/              # Canonical sub-agent personas
├── apps/
│   └── hud/             # Experimental visual interface, not runtime owner
├── cli/                 # Cross-platform Dart CLI
├── docs/                # Architecture documentation
├── packages/            # Installable bundles of skills, rules, agents, assets
├── personas/            # Seed voice and user preference files
├── profiles/            # Reproducible environment definitions
├── rules/               # Canonical behavioral and engineering rules
├── schemas/             # Versioned source, package, profile, runtime, and event schemas
└── skills/              # Canonical portable AI-agent skills
```

## Source Model

Alfredo sources are read-only from the CLI's perspective:

- Source CRUD changes only the local source registry.
- Git sources resolve to immutable commit snapshots.
- Archive sources require SHA-256 integrity metadata.
- Package installs produce deterministic lockfiles and installed-state records.
- Persona files are seed content: created when absent, then left untouched by
  future updates.
- Adapters render canonical content into each agent environment.

### Consuming a third-party skill

A skill written for another agent — for example the `nidhinjs/prompt-master`
Claude skill — is consumed as an Alfredo source, not vendored into this repo. The
upstream repo must expose an `alfredo-source.yaml` and a package; if it does not,
maintain a thin wrapper source that packages its `skills/<name>` directory.

```sh
alfredo source add prompt-master --git <wrapper-repo-url> --revision <commit>
alfredo package install prompt-master --target claude-code --scope user
```

The Git origin resolves to that immutable commit, and `alfredo update` is the
only thing that moves it. A third-party skill that drifts stays pinned until you
choose to pull the change.

## Development

Requirements:

- Dart 3.12 or newer for CLI development.
- Python 3.13 for the experimental HUD.
- Git.
- Platform-specific build tools when producing native release artifacts.

CLI checks:

```sh
cd cli
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos --fatal-warnings
dart test
dart run bin/alfredo.dart --help
```

Compile a native executable on the current platform:

```sh
cd cli
mkdir -p build
dart compile exe bin/alfredo.dart -o build/alfredo
./build/alfredo --version
```

## Experimental Interfaces

`apps/hud/` contains an existing local FastAPI HUD and browser frontend. It is
kept working as an application boundary, but it is no longer the center of the
main Alfredo narrative. Future visual interfaces should consume Task Runtime
state instead of owning independent work state.

## Architectural Influences

Alfredo is inspired by ideas from context engineering, just-in-time context,
progressive disclosure, durable agent memory, task graphs, dependency graphs,
Spec Driven Development, GitHub Spec Kit, Beads, agent handoff, resumable
workflows, fan-out/fan-in coordination, and local-first tooling.

These are conceptual influences. Alfredo is not a fork, wrapper, or
implementation of those projects.

## Security Principles

- Keep secrets, credentials, runtime caches, and generated binaries out of Git.
- Do not expose a generic shell to an AI model.
- Validate source content and paths before installation.
- Stage changes, preserve backups, and update state atomically.
- Keep provider behavior and remote execution explicit.
- Treat authorization boundaries as hard constraints.

## Documentation

- [Task Runtime](docs/architecture/task-runtime.md)
- [Sessions](docs/architecture/sessions.md)
- [Runs](docs/architecture/runs.md)
- [Context Engine](docs/architecture/context-engine.md)
- [Memory](docs/architecture/memory.md)
- [Skills](docs/architecture/skills.md)
- [Rules](docs/architecture/rules.md)
- [Personas](docs/architecture/personas.md)
- [Agents](docs/architecture/agents.md)
- [Agent Adapters](docs/architecture/agent-adapters.md)
