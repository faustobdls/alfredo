import 'dart:io';

import 'package:path/path.dart' as p;

/// A package fixture definition for catalog, resolver, and installer tests.
class PackageFixture {
  /// Creates a package fixture.
  const PackageFixture({
    required this.id,
    this.version = '1.0.0',
    this.targets = const ['codex'],
    this.dependencies = const [],
    this.conflicts = const [],
    this.contents = const {
      'skills': ['skills/example/SKILL.md'],
    },
  });

  /// Package identifier.
  final String id;

  /// Package version.
  final String version;

  /// Supported targets.
  final List<String> targets;

  /// Raw YAML dependency entries.
  final List<Map<String, String>> dependencies;

  /// Conflicting package identifiers.
  final List<String> conflicts;

  /// Source-root-relative content paths grouped by kind.
  final Map<String, List<String>> contents;
}

/// Creates a complete local source whose package content paths use source root.
Future<Directory> createPackageSourceFixture(
  Directory parent, {
  required String sourceId,
  required List<PackageFixture> packages,
}) async {
  final source = await Directory(p.join(parent.path, sourceId)).create();
  await File(p.join(source.path, 'alfredo-source.yaml')).writeAsString('''
schema_version: 1
id: $sourceId
name: $sourceId source
kind: local
path: .
read_only: true
packages_path: packages
''');
  for (final fixture in packages) {
    final packageDirectory = await Directory(
      p.join(source.path, 'packages', fixture.id),
    ).create(recursive: true);
    final contents = fixture.contents.entries
        .map(
          (entry) {
            final paths = entry.value.map((path) => "'$path'").join(', ');
            return '${entry.key}: [$paths]';
          },
        )
        .join('\n  ');
    final dependencies = fixture.dependencies
        .map((entry) => '{id: ${entry['id']}, version: ${entry['version']}}')
        .join(', ');
    await File(p.join(packageDirectory.path, 'package.yaml')).writeAsString('''
schema_version: 1
id: ${fixture.id}
name: ${fixture.id}
version: ${fixture.version}
description: ${fixture.id} package.
targets: [${fixture.targets.join(', ')}]
contents:
  $contents
dependencies: [$dependencies]
conflicts: [${fixture.conflicts.join(', ')}]
''');
    for (final entry in fixture.contents.entries) {
      for (final path in entry.value) {
        final file = File(p.joinAll([source.path, ...p.posix.split(path)]));
        await file.parent.create(recursive: true);
        await file.writeAsString('${fixture.id}:$path\n');
      }
    }
  }
  return source;
}
