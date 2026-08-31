# Alfredo CLI

![coverage][coverage_badge]
[![style: very good analysis][very_good_analysis_badge]][very_good_analysis_link]
[![License: MIT][license_badge]][license_link]

Built from the [Very Good CLI][very_good_cli_link] template.

Cross-platform manager for Alfredo skills, rules, packages, and tools.

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

# Bootstrap the official source and install for every supported agent
$ alfredo setup --all

# Or install for one or more selected agents
$ alfredo setup --cursor
$ alfredo setup --codex --claude
$ alfredo setup --antigravity --scope project

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
```

Set `ALFREDO_CONFIG_HOME` to override the platform-specific configuration
directory. Set `ALFREDO_USER_ROOT` or `ALFREDO_PROJECT_ROOT` to redirect an
installation root, which is also useful in CI. Sources are consumed read-only:
Git revisions are resolved to commits and archives require a SHA-256 digest.

Supported targets are `codex`, `claude-code`, `cursor`, `antigravity`, and
`generic`. Installation is fail-closed on unmanaged or locally modified files;
uninstall preserves modified managed files.

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
