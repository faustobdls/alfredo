import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

/// Scaffolds new Alfredo artifacts, starting with source repositories.
class InitCommand extends Command<int> {
  /// Creates the init command group.
  InitCommand({required Logger logger}) {
    addSubcommand(_InitSourceCommand(logger: logger));
  }

  @override
  String get description => 'Scaffold Alfredo repositories and artifacts.';

  @override
  String get name => 'init';
}

/// Identifier accepted by the source and package schemas.
final _idPattern = RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$');

class _InitSourceCommand extends Command<int> {
  _InitSourceCommand({required this.logger}) {
    argParser
      ..addOption(
        'id',
        help: 'Source identifier. Defaults to the target directory name.',
        valueHelp: 'id',
      )
      ..addOption(
        'name',
        help: 'Human-readable source name. Defaults to a title-cased id.',
        valueHelp: 'name',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Allow scaffolding into a non-empty directory.',
      );
  }

  /// User-facing command logger.
  final Logger logger;

  @override
  String get description =>
      'Create a new Alfredo source repository skeleton at a path.';

  @override
  String get name => 'source';

  @override
  String get invocation => 'alfredo init source <path>';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one target path.', usage);
    }
    final target = Directory(p.normalize(p.absolute(argResults!.rest.single)));
    final id =
        (argResults!['id'] as String?)?.trim() ??
        _slugify(p.basename(target.path));
    if (!_idPattern.hasMatch(id)) {
      throw UsageException(
        'Source id "$id" must match ${_idPattern.pattern}. Pass --id.',
        usage,
      );
    }
    final name = (argResults!['name'] as String?)?.trim() ?? _titleCase(id);
    final force = argResults!['force'] as bool;

    if (target.existsSync() && target.listSync().isNotEmpty && !force) {
      throw UsageException(
        '${target.path} is not empty. Re-run with --force to scaffold anyway.',
        usage,
      );
    }

    final files = _skeleton(id: id, name: name);
    final existing = [
      for (final relative in files.keys)
        if (File(p.join(target.path, relative)).existsSync()) relative,
    ];
    if (existing.isNotEmpty) {
      throw UsageException(
        'Refusing to overwrite existing files: ${existing.join(', ')}.',
        usage,
      );
    }

    for (final entry in files.entries) {
      final file = File(p.join(target.path, entry.key));
      await file.parent.create(recursive: true);
      await file.writeAsString(entry.value);
    }

    logger
      ..success('Scaffolded Alfredo source "$id" at ${target.path}.')
      ..info('Next steps:')
      ..info(
        '  1. Replace skills/hello and packages/example-core with real '
        'content.',
      )
      ..info('  2. Commit and push, or keep it local.')
      ..info('  3. Register it: alfredo source add $id --local ${target.path}');
    return ExitCode.success.code;
  }

  Map<String, String> _skeleton({required String id, required String name}) {
    return {
      'alfredo-source.yaml':
          '''
schema_version: 1
id: $id
name: $name
description: $name — an Alfredo source repository.
kind: local
path: .
read_only: true
packages_path: packages
profiles_path: profiles
''',
      'packages/example-core/package.yaml': '''
schema_version: 1
id: example-core
name: Example Core
version: 0.1.0
description: Replace this with your first real package.
license: MIT
targets:
  - codex
  - claude-code
  - cursor
  - antigravity
  - generic
contents:
  skills:
    - skills/hello
  rules: []
  agents: []
dependencies: []
conflicts: []
''',
      'skills/hello/SKILL.md': '''
---
name: hello
description: Sample skill. Replace it with a real one or delete it.
---

# Hello

Replace this file with a real skill. Each skill is one directory under `skills/`
with a required `SKILL.md`. See the Alfredo repository for the format.
''',
      'rules/.gitkeep': '',
      'agents/.gitkeep': '',
      'profiles/.gitkeep': '',
      'AGENTS.md':
          '''
# $name Bootstrap

This repository uses Alfredo.

- Canonical work state lives in `.alfredo/`.
- Claim a task before changing implementation state.
- Load only context relevant to the task.
- Persist compact checkpoints as work progresses.
- Verify before marking work done.
- Provider directories are adapter outputs, not canonical state.
''',
      '.gitignore': '''
.DS_Store
.alfredo/runtime/
.alfredo-state/
''',
      'README.md':
          '''
# $name

An Alfredo source repository. It publishes skills, rules, agents, and packages
that the `alfredo` CLI installs into agent environments. Alfredo only ever reads
from here.

## Layout

- `alfredo-source.yaml` — the source manifest.
- `packages/` — versioned bundles (`<id>/package.yaml`).
- `skills/` — one directory per skill, each with `SKILL.md`.
- `rules/` — canonical behavioural rules.
- `agents/` — one Markdown file per sub-agent persona.
- `profiles/` — declarative environment definitions.

## Use it

```sh
alfredo source add $id --local "\$(pwd)"
alfredo package list
alfredo setup --all
```

Or publish it and register the Git origin:

```sh
alfredo source add $id --git <repo-url> --revision <tag-or-commit>
```
''',
      'CHANGELOG.md': '''
# Changelog

All notable changes to this source are documented in this file. The format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Initial source skeleton.
''',
    };
  }

  static String _slugify(String value) {
    final lower = value.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
    return lower.replaceAll(RegExp(r'^-+|-+$'), '');
  }

  static String _titleCase(String id) => id
      .split('-')
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1))
      .join(' ');
}
