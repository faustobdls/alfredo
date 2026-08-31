# Alfredo

[Português do Brasil](README.pt-BR.md) · [Español](README.es.md)

Alfredo is a local-first ecosystem for distributing reusable AI-agent knowledge and building reproducible Android engineering workflows. The project is organized as a monorepo so the command-line installer, portable skills, agent-specific adapters, and the existing local HUD can evolve independently while sharing one versioned foundation.

## Goals

- Keep the same skills, rules, and workflows available across personal and work environments.
- Install selected capabilities into Codex, Claude Code, Cursor, Antigravity, and future agents without requiring MCP.
- Treat external skill repositories as read-only sources and install immutable snapshots from them.
- Provide a cross-platform Dart CLI distributed as native binaries for macOS, Windows, and Linux.
- Build a safe Android and ADB automation layer that can coordinate multiple devices by serial number.
- Keep private data and local execution under explicit user control.

## Current status

The repository currently contains:

- The initial Dart CLI generated from the Very Good Ventures Dart CLI template.
- A native `alfredo` executable entry point with help, version, and shell-completion support.
- Versioned v1 contracts for source, package, and profile manifests.
- Validated local, Git, and checksum-pinned archive sources backed by immutable snapshots.
- Deterministic package discovery, dependency resolution, lockfiles, and installed-state tracking.
- Transactional install, status, diff, and safe uninstall commands for user and project scopes.
- Adapters for Codex, Claude Code, Cursor, Antigravity, and a generic target.
- An `android-core` package containing five validated Android engineering skills.
- An append-only `alfredo memory` subsystem with keyword recall, optional local embeddings, and a `memory-core` package.
- The existing FastAPI HUD, moved into its own application boundary under `apps/hud/`.
- Versioned roots for skills, packages, rules, adapters, schemas, and profiles.
- CI workflows for the Dart CLI on macOS, Linux, and Windows, plus the Python HUD test suite.

Profiles, signed binary releases, and device-executing Android commands remain future stages.

## Install the CLI

macOS and Linux (x64 or ARM64):

```sh
curl -fsSL https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.sh | sh
```

Windows PowerShell (x64):

```powershell
irm https://raw.githubusercontent.com/faustobdls/alfredo/main/scripts/install.ps1 | iex
```

The installer downloads the correct binary from the latest GitHub Release,
verifies its SHA-256 checksum, installs it under `~/.alfredo/bin`, and adds that
directory to the current shell's user PATH. Set `ALFREDO_INSTALL_DIR` to use a
different destination.

Install the official packages for every supported agent:

```sh
alfredo setup --all
```

Or select one or more agents:

```sh
alfredo setup --cursor
alfredo setup --codex --claude
alfredo setup --antigravity
```

`setup` bootstraps the official source associated with the installed CLI
release and installs into the user scope by default. Pass `--scope project` to
install into the current project instead.

Maintainers create a release by updating `cli/pubspec.yaml`, running
`dart run build_runner build` inside `cli/`,
updating this changelog, and merging the change into `main`. The release
workflow validates the version, runs the CLI checks, builds every supported
artifact, creates the annotated `vX.Y.Z` tag, generates release notes from
Conventional Commits, and publishes the checksums and binaries to GitHub
Releases. A matching manually pushed tag remains supported.

## Repository structure

```text
alfredo/
├── .github/             # CI, dependency updates, and repository templates
├── adapters/            # Agent-specific installation and rendering adapters
├── agents/              # Canonical sub-agent personas, answering as Alfredo
├── apps/
│   └── hud/             # Existing local FastAPI HUD and browser frontend
├── cli/                 # Cross-platform Dart CLI and native binary entry point
├── docs/                # Architecture decisions and cross-project documentation
├── packages/            # Installable bundles of skills, rules, agents, and assets
├── profiles/            # Reproducible personal, work, and project configurations
├── rules/               # Canonical behavioral and engineering rules
├── schemas/             # Versioned source, package, profile, and lockfile contracts
└── skills/              # Canonical portable AI-agent skills
```

### `.github/`

Contains repository automation. `alfredo_cli.yaml` formats, analyzes, tests, and compiles the Dart CLI on all three target operating-system families. `alfredo_hud.yaml` installs and tests the Python HUD. Dependabot is configured to resolve Dart packages from `cli/`.

### `cli/`

Contains the pure-Dart `alfredo_cli` package and the `alfredo` executable. It owns:

- Read-only Git/archive snapshots and source registry CRUD.
- Catalog search and deterministic package resolution.
- Transactional installation, status, diff, and safe removal.
- User and project scopes.
- Explicit adapter selection for five targets.
- Future `alfredo android` multi-device commands.

The CLI has no Flutter runtime dependency. Native binaries will be compiled on each target operating system.

### `skills/`

The canonical home for reusable agent skills — on-demand capability guides, each a directory with a required `SKILL.md`. Two families: **domain skills** (`android-core`: kernel internals, platform internals, native development, app security, ADB device-fleet operation) and **workflow skills** (`skills-core`: `autopilot`, `ralph`, `ralplan`, `ultrawork`, `ultraqa`, `team`, `plan`, `deep-interview`, `trace`, `deslop` — phased, verified orchestration methods in Alfredo's voice). See [docs/architecture/skills.md](docs/architecture/skills.md).

Agent-specific copies must be generated from this canonical content instead of being maintained independently.

### `agents/`

The canonical sub-agent catalogue. One Markdown file per agent, in Claude Code sub-agent format, all answering **as Alfredo** — the household's butler-engineer: precise, unflappable, and exacting about standards. The `agents-core` package ships them; `alfredo setup` installs them into each target's agent directory. See [docs/architecture/agents.md](docs/architecture/agents.md).

### `packages/`

Contains installable bundles. A package may group multiple skills, rules, scripts, references, and adapter requirements into one versioned unit, such as `android-core`, `adb-device-fleet`, or `android-security`.

Packages will declare dependencies, conflicts, supported targets, and semantic versions. They are different from skills: a skill teaches one capability, while a package is a distributable collection of capabilities.

### `rules/`

Always-on constraints and standards — one Markdown file per rule, meant to be in an agent's context for every task. The `rules-core` package ships nine in Alfredo's voice (smallest change, verify before claiming, match the house style, atomic commits, authorization boundaries, faithful reporting, ask only when blocked, secrets and exfiltration, separate authoring from review); `memory-core` adds two scoped to the memory subsystem. Adapters transform them into each agent's native format. See [docs/architecture/rules.md](docs/architecture/rules.md).

### `adapters/`

Contains target-specific installation logic and templates for Codex, Claude Code, Cursor, Antigravity, and generic directory-based targets. Adapters know where a target stores skills and rules and how canonical Alfredo content must be rendered there. They do not own the canonical knowledge.

### `schemas/`

Contains machine-readable v1 contracts for source, package, profile, installed-state, and lockfile documents. Validation happens before the CLI persists a source registration or writes into an agent environment.

### `profiles/`

Will contain declarative environment definitions such as `personal`, `work`, or project-specific profiles. A profile selects sources, packages, versions, scopes, and targets. Combined with a lockfile, it will make separate machines resolve the same installation.

### `apps/hud/`

Contains the existing local-first Alfredo HUD:

- `app/`: FastAPI backend, providers, routing, memory, tools, and voice support.
- `web/`: static browser interface served by FastAPI.
- `tests/`: Python regression suite.
- `docs/`: HUD-specific implementation notes.
- `pyproject.toml`: Python package and dependency configuration.

The HUD can call local or controlled remote providers. It remains separate from the Dart CLI so either product can run, test, and ship independently. See [apps/hud/README.md](apps/hud/README.md) for its API, privacy model, and setup.

### `docs/`

Contains documentation that applies to the whole ecosystem, including migration records and future architecture decisions. Application-specific documentation stays with its application.

## Source model

Alfredo sources are designed to be read-only from the CLI's perspective:

- Source CRUD changes only the local source registry.
- Downloading a Git source resolves content to a commit snapshot.
- Downloading an archive requires integrity metadata such as SHA-256.
- Installing or updating a package never commits, pushes, merges, tags, or edits the remote source.
- Installed versions will be recorded in a deterministic lockfile.

Source repositories are maintained and published through their own workflows. Alfredo only consumes them.

Start a new one with:

```sh
alfredo init source ./my-source
```

This scaffolds the manifest, the content roots (`skills/`, `rules/`, `agents/`, `profiles/`), a sample package, and a README. `--id` and `--name` override the defaults; `--force` allows a non-empty directory.

## Memory

Alfredo keeps a durable, local record of what was decided and what was done, so an agent can reload context in a later session instead of re-deriving it.

Memory lives in `.alfredo/memory/` and exists in two independent scopes: `~/.alfredo/memory/` for cross-project practice and `<repo>/.alfredo/memory/` for facts that only make sense inside one repository. Each store contains an append-only `journal/` of dated session files, a `notes/` directory holding one durable fact per file, a generated `index/`, and a derived `MEMORY.md`. Only `MEMORY.md` is ever regenerated; journals grow by concatenation and notes are never overwritten.

Recall works without a network. Keyword ranking is always available. When a local Ollama daemon is reachable, `alfredo memory setup` can enable embedding ranking, and search silently falls back to keywords whenever the provider is unavailable. Setup reuses any known embedding model you have already pulled (`nomic-embed-text`, `mxbai-embed-large`, `bge-m3`, `snowflake-arctic-embed2`, `embeddinggemma`, and more); a model is downloaded only when the operator explicitly confirms it.

| Command | Effect |
| --- | --- |
| `alfredo memory setup` | Create the store, configure recall, and install `memory-core` |
| `alfredo memory add <message>` | Append a journal entry, or write a note with `--kind note --title` |
| `alfredo memory search <query>` | Rank memory documents, falling back to keyword search |
| `alfredo memory list --since 7d` | Show recent journal entries, newest first |
| `alfredo memory digest --since 14d` | Render a compact, day-grouped briefing |
| `alfredo memory index` | Embed new and changed documents and prune deleted ones |
| `alfredo memory capture` | Record the end of a working session |

Set `ALFREDO_MEMORY_HOME` to relocate the user store. See [docs/architecture/memory.md](docs/architecture/memory.md) for the on-disk contract and safety invariants.

## Development

### Requirements

- Dart 3.12 or newer for CLI development.
- Python 3.13 for HUD development.
- Git.
- Platform-specific build tools when producing native release artifacts.

### Dart CLI

```bash
cd cli
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos --fatal-warnings
dart test
dart run bin/alfredo.dart --help
dart run bin/alfredo.dart source add canonical --local ..
dart run bin/alfredo.dart source test canonical
dart run bin/alfredo.dart package install android-core --target codex --scope user
dart run bin/alfredo.dart package status --target codex --scope user
dart run bin/alfredo.dart update --dry-run
dart run bin/alfredo.dart update
dart run bin/alfredo.dart upgrade --check
dart run bin/alfredo.dart memory setup --all --source canonical
dart run bin/alfredo.dart memory add "explored the source registry"
dart run bin/alfredo.dart memory digest --since 14d
```

Compile a native executable on the current platform:

```bash
cd cli
mkdir -p build
dart compile exe bin/alfredo.dart -o build/alfredo
./build/alfredo --version
```

### Python HUD

Create the shared development environment from the repository root:

```bash
python3.13 -m venv .venv
source .venv/bin/activate
python -m pip install -e "apps/hud[dev]"
cp apps/hud/.env.example apps/hud/.env
```

Run tests and start the server:

```bash
cd apps/hud
../../.venv/bin/python -m pytest -q
../../.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 8765 --reload
```

Open `http://127.0.0.1:8765` after the server starts.

## Security principles

- Never commit `.env` files, credentials, runtime caches, or generated binaries.
- Do not expose a generic shell to an AI model.
- Address Android devices explicitly by serial number.
- Separate observation, application changes, privileged system actions, and authorized security-lab operations.
- Validate source content and paths before installation.
- Stage changes, preserve backups, and update installation state atomically.
- Keep remote execution and fallback behavior explicit to the user.

## Roadmap

1. Add declarative profiles, package update, rollback, and offline bundles.
2. Publish signed native CLI binaries for macOS, Windows, and Linux.
3. Build device-executing Android and ADB multi-device commands.
4. Expand Android skills with versioned references, scripts, and lab fixtures.

## Documentation languages

- English: [README.md](README.md)
- Português do Brasil: [README.pt-BR.md](README.pt-BR.md)
- Español: [README.es.md](README.es.md)
