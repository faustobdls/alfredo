# Alfredo

[Português do Brasil](README.pt-BR.md) · [Español](README.es.md)

Alfredo is local-first infrastructure for durable, portable AI-assisted engineering.

Agents and chats are temporary. Project memory, task state, skills, rules, templates, and context should not be. Alfredo keeps that durable layer in developer-controlled files, then renders the right pieces into whichever agent target you explicitly choose.

## What Alfredo Provides

- Portable agent setup for Codex, Claude Code, Cursor, Antigravity/GCA, Devin, Gemini CLI, Via, and generic directory targets.
- Durable memory for project and user knowledge outside the current chat.
- Deterministic context packages for a specific task.
- Portable skills, rules, personas, sub-agents, templates, scripts, assets, and references.
- Durable task runtime with tasks, dependencies, owners, sessions, checkpoints, blockers, validations, and next actions.
- Read-only package sources, dependency resolution, lockfiles, transactional installation, status, diff, update, and safe uninstall.
- Local-first operation: state remains readable, versionable, recoverable, and inspectable on the developer machine.

## How It Works

```text
canonical Alfredo state
        |
        v
sources, packages, memory, tasks, context
        |
        v
target adapters
        |
        v
Codex / Claude Code / Cursor / Antigravity / Devin / Gemini CLI / Via / generic
```

Provider directories such as `.codex/`, `.claude/`, `.cursor/`, `.gemini/`, `.devin/`, `.via/`, `.agents/`, and `.alfredo/` are adapter outputs. They are not the canonical board, memory, or source of truth.

## Core Concepts

### Memory

Memory answers: "what do we know?"

It stores durable decisions, facts, conventions, lessons, and relevant history in user and project scopes:

- `~/.alfredo/memory/` for knowledge that applies across projects.
- `<repo>/.alfredo/memory/` for knowledge that only applies to one repository.

Memory is append-only by design. Journals grow over time, notes are written once, and derived indexes can be regenerated. Search works offline with keyword ranking. Optional local Ollama embeddings improve ranking when available and fall back to keywords when unavailable.

### Context

Context answers: "what should this task load right now?"

Projects can declare named context topics in `.alfredo/config.yaml`. A task can reference topics and files. `alfredo context build ALF-...` returns a deterministic `alfredo.context/v1` package with grouped sources and an approximate token estimate, so agents load relevant material instead of rediscovering the project every session.

### Skills

Skills are portable capability guides. Each skill lives in `skills/<name>/SKILL.md`, with optional references, scripts, and assets loaded only when needed. Skills keep agent behavior teachable without dumping every detail into every prompt.

### Rules

Rules are always-on constraints and standards. They live in `rules/` and are rendered by adapters into each selected target. Use rules for behavior that must apply broadly; use skills for task-specific procedures.

### Personas

Personas are lightweight voice and preference files. They live in `personas/` and can be seeded into targets without overwriting local user edits on future updates.

### Templates

Templates describe the desired shape of an output artifact: voice, structure, length, format, and constraints. Alfredo provides the schema and commands; teams create and package their own templates.

When creating a template, ask or provide its kind, what it is for, and output
format. The format is open: known targets are suggestions, and a project can
define a pure-text, custom-file, or renderer-specific target. New blank
templates are written to the repository under
`templates/<name>/TEMPLATE.md`, not to the user profile, so they can later be
packaged or exported.

### Packages And Sources

Packages group canonical content into versioned installable units. A package declares its supported targets, dependencies, conflicts, and content paths. Sources are read-only catalogs, either local, Git-backed, or archive-backed. Installing packages writes to target adapters, never to the source.

### Targets And Adapters

A target is an explicit agent environment such as `codex`, `claude-code`, `cursor`, `antigravity`, `devin`, `gemini-cli`, `via`, or `generic`. An adapter maps canonical Alfredo content into that target's directory layout.

`alfredo setup --all` installs only targets that are both declared by the discovered official packages and already configured in the selected local scope. It does not install into every built-in adapter just because Alfredo knows about it.

### Task Runtime

Task Runtime answers: "what are we doing now?"

Projects keep durable work state in `.alfredo/` and machine-local state in `.alfredo/runtime/`. The core entities are:

- Run: a larger objective or orchestration unit.
- Task: a durable unit of work with acceptance criteria and dependencies.
- Session: one temporary worker instance using a supported adapter/provider.

`READY` is derived, not persisted. A task is ready when it is in `BACKLOG`, has no owner, is not blocked or terminal, and all dependencies are `DONE`.

Larger development flows end with a closure check: review the README set for
stale behavior or setup notes, then review changed items for memory relevance
before reporting the master task complete.

## Install

macOS and Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.sh | sh
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.ps1 | iex
```

The installer downloads the latest GitHub release for the current platform, validates the SHA-256 checksum, installs into `~/.alfredo/bin`, and updates the current shell PATH. Set `ALFREDO_INSTALL_DIR` to choose another destination.

## Setup Targets

Install official packages into every configured target declared by those packages:

```sh
alfredo setup --all
```

Install only selected targets:

```sh
alfredo setup --codex
alfredo setup --cursor --gemini-cli
alfredo setup --devin --via
alfredo setup --claude-code
alfredo setup --antigravity
alfredo setup --generic
```

Use `--scope project` to install into the current project instead of the user scope, and `--force` to overwrite locally modified managed files.

## Common Commands

```sh
alfredo init source ./my-source
alfredo source add canonical --local ./my-source
alfredo package list
alfredo package install android-core --target codex --scope user
alfredo package status --target codex
alfredo update --dry-run
alfredo upgrade --check
alfredo template new client-email --kind email --description "Use for client email. Not for internal chat." --format-target email
alfredo template validate client-email
```

```sh
alfredo memory setup --target codex
alfredo memory add "documented the task runtime"
alfredo memory add --kind note --title "Runtime decision" "tasks are canonical"
alfredo memory list --since 30d
alfredo memory search "task handoff"
alfredo memory digest --since 14d
alfredo memory capture
```

```sh
alfredo task create --title "Implement reconnect support"
alfredo task ready
alfredo session start --adapter codex
alfredo task claim ALF-... --adapter codex --session SES-...
alfredo task start ALF-...
alfredo task checkpoint ALF-... --completed "protocol" --current "tests"
alfredo task verify ALF-...
alfredo task done ALF-...
alfredo task resume ALF-...
alfredo context build ALF-...
```

Most runtime commands support `--json` for agents and tools.

## Repository Layout

```text
alfredo/
├── .github/             # CI, dependency updates, and repository templates
├── adapters/            # Agent-specific installation and rendering adapters
├── agents/              # Canonical sub-agents
├── cli/                 # Cross-platform Dart CLI and native executable entrypoint
├── docs/                # Architecture and migration documentation
├── packages/            # Installable bundles of canonical content
├── personas/            # Voice and durable preference seeds
├── profiles/            # Reproducible personal, work, and project selections
├── rules/               # Canonical always-on behavior and engineering rules
├── schemas/             # Versioned JSON contracts
└── skills/              # Canonical portable skills
```

## Architecture Notes

- [Agent Adapters](docs/architecture/agent-adapters.md)
- [Agents](docs/architecture/agents.md)
- [Context Engine](docs/architecture/context-engine.md)
- [Memory](docs/architecture/memory.md)
- [Personas](docs/architecture/personas.md)
- [Rules](docs/architecture/rules.md)
- [Skills](docs/architecture/skills.md)
- [Task Runtime](docs/architecture/task-runtime.md)
- [Templates](docs/architecture/templates.md)

## Development

```sh
cd cli
dart pub get
dart format .
dart analyze
dart test
```
