# Alfredo CLI

![coverage][coverage_badge]
[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

Built from the [Very Good CLI][very_good_cli_link] template.

Cross-platform manager for Alfredo skills, rules, packages, and tools.
It also owns the local-first Task Runtime used to persist tasks, sessions,
runs, checkpoints, ownership, and resumable handoffs outside any one agent
conversation.

---

## Getting Started 🚀

Durante o desenvolvimento, execute diretamente pelo SDK Dart:

```sh
dart pub get
dart run bin/alfredo.dart --help
```

## Usage

```sh
# Show CLI version
$ alfredo --version

# Show usage help
$ alfredo --help

# Bootstrap the official source and install for every configured declared target
$ alfredo setup --all

# Or install for one or more selected agents
$ alfredo setup --cursor
$ alfredo setup --codex --gemini-cli
$ alfredo setup --devin --via
$ alfredo setup --antigravity --scope project

# Scaffold a new Alfredo source repository
$ alfredo init source ./my-source
$ alfredo init source ./my-source --id team-tools --name "Team Tools" --force

# Register and validate this repository as a local, read-only source
$ alfredo source add canonical --local /path/to/alfredo
$ alfredo source add upstream --git https://github.com/example/skills.git --revision v1.0.0
$ alfredo source add bundle --archive file:///path/to/skills.zip --sha256 DIGEST
$ alfredo source list
$ alfredo source show canonical
$ alfredo source test canonical
$ alfredo source remove canonical

# Discover and install packages
$ alfredo package list
$ alfredo package search android
$ alfredo package show android-core
$ alfredo package install android-core --target codex --scope user
$ alfredo package status --target codex --scope user
$ alfredo package diff --target codex --scope user
$ alfredo package uninstall android-core --target codex --scope user

# Author project-root output templates
$ alfredo template new client-email --kind email --description "Use for client email. Not for internal chat." --format-target email
$ alfredo template validate client-email
$ alfredo template match email

# Coordinate durable work
$ alfredo run create --title "Implement multiplayer MVP"
$ alfredo task create --title "Implement reconnect support"
$ alfredo task ready
$ alfredo session start --adapter codex
$ alfredo task claim ALF-... --adapter codex --session SES-...
$ alfredo task checkpoint ALF-... --next-action "write tests"
$ alfredo session close SES-... --reason context-limit --capture-memory
$ alfredo task resume ALF-...
$ alfredo context build ALF-...

# Refresh installed packages from their sources
$ alfredo update
$ alfredo update --dry-run
$ alfredo update --target codex --scope user --package android-core
$ alfredo update --no-refresh-sources

# Update the CLI binary itself
$ alfredo upgrade --check
$ alfredo upgrade
```

Set `ALFREDO_CONFIG_HOME` to override the platform-specific configuration
directory. Set `ALFREDO_USER_ROOT` or `ALFREDO_PROJECT_ROOT` to redirect an
installation root, which is also useful in CI. Sources are consumed read-only:
Git revisions are resolved to commits and archives require a SHA-256 digest.

`alfredo update` re-resolves every installed target and scope, advances Git
sources to their newest revision (skip with `--no-refresh-sources`), and
reinstalls only packages whose content changed; locally modified managed files
are reported and left untouched. `alfredo upgrade` downloads the matching
release asset, verifies it against `SHA256SUMS`, and swaps the running
executable. Override the release origin with `ALFREDO_GITHUB_REPOSITORY` or
`ALFREDO_DOWNLOAD_BASE_URL`.

Supported targets are `codex`, `claude-code`, `cursor`, `antigravity`, `devin`,
`generic`, `gemini-cli`, and `via`. `setup --all` installs only targets that
are both declared by the discovered official packages and already configured in
the selected local scope. Installation is fail-closed on unmanaged or locally
modified files; uninstall preserves modified managed files.

## Running Tests with coverage 🧪

To run all unit tests use the following command:

```sh
$ dart pub global activate coverage 1.15.0
$ dart test --coverage=coverage
$ dart pub global run coverage:format_coverage --lcov --in=coverage --out=coverage/lcov.info
```

To view the generated coverage report you can use [lcov](https://github.com/linux-test-project/lcov)
.

```sh
# Generate Coverage Report
$ genhtml coverage/lcov.info -o coverage/

# Open Coverage Report
$ open coverage/index.html
```

---

[coverage_badge]: coverage_badge.svg
[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
[very_good_analysis_badge]: https://img.shields.io/badge/style-very_good_analysis-B22C89.svg
[very_good_analysis_link]: https://pub.dev/packages/very_good_analysis
[very_good_cli_link]: https://github.com/VeryGoodOpenSource/very_good_cli
