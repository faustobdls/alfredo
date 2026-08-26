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
- The existing FastAPI HUD, moved into its own application boundary under `apps/hud/`.
- Empty, versioned roots for the upcoming skills, packages, rules, adapters, schemas, and profiles.
- CI workflows for the Dart CLI on macOS, Linux, and Windows, plus the Python HUD test suite.

Source management, package installation, agent adapters, and Android commands are planned next and are not implemented yet.

## Repository structure

```text
alfredo/
├── .github/             # CI, dependency updates, and repository templates
├── adapters/            # Agent-specific installation and rendering adapters
├── apps/
│   └── hud/             # Existing local FastAPI HUD and browser frontend
├── cli/                 # Cross-platform Dart CLI and native binary entry point
├── docs/                # Architecture decisions and cross-project documentation
├── packages/            # Installable bundles of skills, rules, scripts, and assets
├── profiles/            # Reproducible personal, work, and project configurations
├── rules/               # Canonical behavioral and engineering rules
├── schemas/             # Versioned source, package, profile, and lockfile contracts
└── skills/              # Canonical portable AI-agent skills
```

### `.github/`

Contains repository automation. `alfredo_cli.yaml` formats, analyzes, tests, and compiles the Dart CLI on all three target operating-system families. `alfredo_hud.yaml` installs and tests the Python HUD. Dependabot is configured to resolve Dart packages from `cli/`.

### `cli/`

Contains the pure-Dart `alfredo_cli` package and the `alfredo` executable. This component will own:

- Source registration and local source CRUD.
- Read-only source downloads and immutable snapshots.
- Catalog search and package resolution.
- Installation, update, diff, rollback, and removal.
- User and project scopes.
- Agent detection and adapter selection.
- Future `alfredo android` multi-device commands.

The CLI has no Flutter runtime dependency. Native binaries will be compiled on each target operating system.

### `skills/`

The canonical home for reusable agent skills. Each skill will be a directory containing a required `SKILL.md` and optional `scripts/`, `references/`, and `assets/` directories. Skills describe specialized workflows and domain knowledge, such as Android kernel internals, native Android development, diagnostics, security assessment, and ADB fleet operation.

Agent-specific copies must be generated from this canonical content instead of being maintained independently.

### `packages/`

Contains installable bundles. A package may group multiple skills, rules, scripts, references, and adapter requirements into one versioned unit, such as `android-core`, `adb-device-fleet`, or `android-security`.

Packages will declare dependencies, conflicts, supported targets, and semantic versions. They are different from skills: a skill teaches one capability, while a package is a distributable collection of capabilities.

### `rules/`

Contains canonical instructions that shape how an agent works across tasks: coding standards, safety requirements, authorization boundaries, evidence collection, and project conventions. Rules are transformed into each agent's native format by adapters.

### `adapters/`

Contains target-specific installation logic and templates for Codex, Claude Code, Cursor, Antigravity, and generic directory-based targets. Adapters know where a target stores skills and rules and how canonical Alfredo content must be rendered there. They do not own the canonical knowledge.

### `schemas/`

Will contain machine-readable, versioned contracts for source manifests, packages, profiles, installed-state manifests, and lockfiles. Validation must happen before the CLI writes into any agent environment.

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

1. Define source, package, profile, and lockfile schemas.
2. Implement local and Git source registration and read-only downloads.
3. Add deterministic package resolution and transactional installation.
4. Implement Codex, Claude Code, Cursor, and Antigravity adapters.
5. Add update, diff, rollback, profiles, and offline bundles.
6. Publish signed native CLI binaries for macOS, Windows, and Linux.
7. Build Android and ADB multi-device commands.
8. Populate the initial Android internals, native development, diagnostics, and security skills.

## Documentation languages

- English: [README.md](README.md)
- Português do Brasil: [README.pt-BR.md](README.pt-BR.md)
- Español: [README.es.md](README.es.md)
