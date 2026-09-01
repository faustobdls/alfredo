# Changelog

All notable changes to Alfredo are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Task Runtime foundation: durable tasks, dependency-aware ready work, atomic
  claims, sessions, runs, compact checkpoints, resumable handoff packets,
  context packages, runtime schemas, and CLI commands under `alfredo task`,
  `alfredo session`, `alfredo run`, and `alfredo context`.
- Task events now have an explicit `alfredo.task-event/v1` schema and the
  runtime can recover stale local lock files after a bounded timeout.
- `agents` content kind for packages, alongside `skills` and `rules`. Packages
  can bundle sub-agent definitions that install into each target's agent
  directory (`~/.claude/agents/`, `~/.codex/agents/`, and so on).
- Canonical `agents/` root and the `agents-core` package: a catalogue of 19
  sub-agent personas (executor, planner, architect, code-reviewer, debugger,
  and more) that answer in Alfredo's voice.
- `alfredo init source <path>` scaffolds a new Alfredo source repository —
  manifest, content roots (`skills/`, `rules/`, `agents/`, `profiles/`), a
  sample package, README, and CHANGELOG — with `--id`, `--name`, and `--force`.
- `rules-core` package: nine always-on working rules in Alfredo's voice
  (smallest change, verify before claiming, match the house style, atomic
  commits, authorization boundaries, faithful reporting, ask only when blocked,
  secrets and exfiltration, separate authoring from review).
- `skills-core` package: eleven workflow skills in Alfredo's voice (`autopilot`,
  `ralph`, `ralplan`, `ultrawork`, `ultraqa`, `team`, `plan`, `deep-interview`,
  `trace`, `deslop`, `map-project`) that orchestrate the agent catalogue through
  phased, verified processes.
- `map-project` skill: a first-contact repository survey that produces a
  structured `docs/` map (overview, one file per subsystem, directory index) so
  later sessions read the map instead of re-exploring. `alfredo init source`
  scaffolds it into new source repositories and points `AGENTS.md` at it.

### Changed

- `alfredo setup` and `alfredo package install` no longer abort when a managed
  file was edited locally. Each modified file is resolved on its own: the
  command asks before overwriting, keeps the file and warns if declined, and a
  new `--force` flag overwrites every modified file without asking. Kept files
  stay tracked and still report as modified.

## [0.0.4] - 2026-08-31

### Added

- Discovery `tags` in the frontmatter of the five `android-core` skills so agents
  can filter and route them by domain, discipline, topic, and tool.

### Changed

- `alfredo memory setup` recognizes several known embedding models
  (`nomic-embed-text`, `mxbai-embed-large`, `bge-m3`, `snowflake-arctic-embed2`,
  `snowflake-arctic-embed`, `embeddinggemma`, `all-minilm`,
  `paraphrase-multilingual`) and reuses whichever one is already installed
  instead of only ever downloading `nomic-embed-text`.

### Fixed

- `alfredo memory setup --all` now recognizes an already-installed embedding model
  that Ollama reports with an explicit `:latest` tag, instead of falling back to
  keyword search and leaving embeddings disabled.

## [0.0.3] - 2026-08-31

### Added

- `alfredo upgrade` self-updates the CLI from the latest checksum-verified release,
  with `--check` and `--force`.
- `alfredo update` re-resolves installed packages across every target and scope,
  advances Git sources to newer revisions, and reinstalls changed content, with
  `--target`, `--scope`, `--package`, `--dry-run`, and `--no-refresh-sources`.
- `alfredo memory` subsystem with an append-only, offline-first local store in
  `.alfredo/memory/`, separate user and repository scopes, keyword recall with
  optional local Ollama embedding ranking, and the `memory-core` package.
  Includes `memory setup`, `add`, `search`, `list`, `digest`, `index`, and
  `capture` subcommands.

### Fixed

- Materialize Git source snapshots without exceeding the Windows path limit by
  using a short staging directory name and enabling Git `core.longpaths`.

## [0.0.2] - 2026-08-31

### Added

- Cross-platform GitHub release pipeline with native macOS, Linux, and Windows artifacts.
- Checksum-verified installers for Unix shells and Windows PowerShell.
- Conventional Commit-based release notes for GitHub releases.
- `alfredo setup` bootstrap command with `--all` and per-agent installation flags.
- Automatic release-tag creation after successful merge validation and builds.

### Fixed

- Return a usage error instead of an unhandled exception when `--target` is missing.
- Handle empty or unset Windows user and process PATH values during installation.

## [0.0.1] - 2026-08-31

### Added

- Initial Dart CLI and native `alfredo` executable.
- Validated source catalogs, immutable snapshots, and archive integrity checks.
- Deterministic package resolution, transactional installation, status, diff, and uninstall.
- Portable Android engineering skills and the `android-core` package.
- FastAPI HUD monorepo application and CI workflows.

[Unreleased]: https://github.com/faustobdls/alfredo/compare/v0.0.4...HEAD
[0.0.4]: https://github.com/faustobdls/alfredo/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/faustobdls/alfredo/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/faustobdls/alfredo/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/faustobdls/alfredo/releases/tag/v0.0.1
