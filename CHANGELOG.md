# Changelog

All notable changes to Alfredo are documented in this file. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/faustobdls/alfredo/compare/v0.0.2...HEAD
[0.0.2]: https://github.com/faustobdls/alfredo/compare/v0.0.1...v0.0.2
[0.0.1]: https://github.com/faustobdls/alfredo/releases/tag/v0.0.1
