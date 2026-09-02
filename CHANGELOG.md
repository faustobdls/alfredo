# Changelog

All notable changes to Alfredo are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.7] - 2026-09-01

### Added

- `personas-core` package with seed `personas/alfredo.md` and
  `personas/user.md` files for Alfredo's voice and durable user communication
  preferences.
- `personas` package content kind, installed-state seed mode, and context
  package `personas` sources so persona files are created when absent and
  preserved across updates.
- Templates subsystem: a new canonical content type `templates/` for output
  contracts — the voice, structure, length, format, and constraints of an
  authored artifact (email, slide deck, memo). Adds `schemas/template.schema.json`,
  a `templates` key to the package `contents` contract, and an `alfredo template`
  command group (`list`, `show`, `new`, `validate`, `match`). `alfredo context
  build` folds a resolved template into `sources.templates` when a task sets
  `context.template`. Alfredo ships no templates; teams author and distribute
  their own. See `docs/architecture/templates.md`.
- `use-templates` rule in `rules-core`: resolve a template with
  `alfredo template match <kind>` before producing an authored artifact and
  follow its contract; never invent one. Loaded conditionally.
- `compose-from-template` workflow skill in `skills-core`: shape existing source
  material — an outline, a roteiro, notes — into the finished artifact under a
  resolved template, then verify the result against the contract in a separate
  pass. Renderer-agnostic: the template names the target, the agent uses
  whatever tool the session has.
- `web-research` workflow skill in `skills-core`: fetch external content through
  whatever tool tier the session has, record provenance (URL, date, content
  hash), and fold the findings into memory or a context topic. Names scrapers
  like Scrapling, ScrapeGraphAI, and Agent-Reach only as examples of each tier,
  never as dependencies.
- `external-content-provenance` rule in `rules-core`: content fetched from
  outside the machine is a dated, hashed snapshot, not live truth; re-fetch
  deliberately. Loaded conditionally when `web-research` runs.
- Source Model docs now show consuming a third-party skill (for example the
  `nidhinjs/prompt-master` Claude skill) as a pinned Git source rather than
  vendoring it, plus a self-contained-skill authoring principle in
  `docs/architecture/skills.md`.

## [0.0.6] - 2026-09-01

### Changed

- Bump `cli_completion` from 0.5.1 to 0.6.0 and `yaml` from 3.1.3 to 3.1.4 in
  the CLI.
- Bump CI and release GitHub Actions: `actions/checkout` 4 to 7,
  `actions/setup-python` 5 to 7, `actions/upload-artifact` 4 to 7,
  `actions/download-artifact` 4 to 8, and `dart-lang/setup-dart` 1.8.0 to 1.8.1.

## [0.0.5] - 2026-08-31

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

- `alfredo memory list` now includes durable notes by default as well as recent
  journal activity; use `--kind activity` or `--kind note` to filter.
- Task Runtime CLI commands now discover the repository runtime root from nested
  directories instead of writing accidental subdirectory `.alfredo/` stores.
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

[Unreleased]: https://github.com/faustobdls/alfredo/compare/v0.0.7...HEAD
[0.0.7]: https://github.com/faustobdls/alfredo/compare/v0.0.6...v0.0.7
[0.0.6]: https://github.com/faustobdls/alfredo/compare/v0.0.5...v0.0.6
[0.0.5]: https://github.com/faustobdls/alfredo/compare/v0.0.4...v0.0.5
[0.0.4]: https://github.com/faustobdls/alfredo/compare/v0.0.3...v0.0.4
[0.0.3]: https://github.com/faustobdls/alfredo/compare/v0.0.2...v0.0.3
[0.0.2]: https://github.com/faustobdls/alfredo/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/faustobdls/alfredo/releases/tag/v0.0.1
