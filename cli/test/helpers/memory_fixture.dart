import 'dart:io';

import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:path/path.dart' as p;

/// Creates a local source that ships `memory-core` with its real content.
Future<Directory> createMemorySourceFixture(
  Directory parent, {
  String sourceId = 'memory-source',
}) async {
  final source = await Directory(p.join(parent.path, sourceId)).create();
  await File(p.join(source.path, 'alfredo-source.yaml')).writeAsString('''
schema_version: 1
id: $sourceId
name: Memory Source
kind: local
path: .
read_only: true
packages_path: packages
''');
  final package = await Directory(
    p.join(source.path, 'packages', 'memory-core'),
  ).create(recursive: true);
  await File(p.join(package.path, 'package.yaml')).writeAsString('''
schema_version: 1
id: memory-core
name: Memory Core
version: 0.1.0
description: Memory skills and rules.
license: MIT
targets: [codex, claude-code, cursor, antigravity, generic]
contents:
  skills:
    - skills/alfredo-memory
  rules:
    - rules/memory-usage.md
    - rules/memory-hygiene.md
dependencies: []
conflicts: []
''');
  final skill = await Directory(
    p.join(source.path, 'skills', 'alfredo-memory'),
  ).create(recursive: true);
  await File(p.join(skill.path, 'SKILL.md')).writeAsString('''
---
name: alfredo-memory
description: Record and recall Alfredo memory.
---

# Alfredo Memory
''');
  final rules = await Directory(p.join(source.path, 'rules')).create();
  await File(p.join(rules.path, 'memory-usage.md')).writeAsString(
    '# Memory usage\n',
  );
  await File(p.join(rules.path, 'memory-hygiene.md')).writeAsString(
    '# Memory hygiene\n',
  );
  return source;
}

/// A deterministic [EmbeddingsClient] that never touches the network.
///
/// Vectors count the occurrences of [terms] and end with a constant component,
/// so similarity is predictable and no vector has a zero magnitude.
class FakeEmbeddingsClient implements EmbeddingsClient {
  /// Creates a fake embedding provider.
  FakeEmbeddingsClient({
    this.model = 'fake-embed',
    this.reachable = true,
    this.installedModels = const ['fake-embed'],
  });

  /// Terms that define one vector component each.
  static const terms = <String>['alpha', 'beta', 'gamma', 'delta'];

  @override
  final String model;

  /// Whether [probe] reports the provider as reachable.
  final bool reachable;

  /// Models reported by [listModels].
  final List<String> installedModels;

  /// Number of [embed] invocations.
  int embedCalls = 0;

  /// Number of inputs passed to [embed].
  int embeddedInputs = 0;

  /// Number of [pull] invocations.
  int pullCalls = 0;

  int? _dimensions;

  @override
  int? get dimensions => _dimensions;

  @override
  Future<bool> probe() async => reachable;

  @override
  Future<List<String>> listModels() async => installedModels;

  @override
  Future<void> pull(
    String model, {
    void Function(String status)? onProgress,
  }) async {
    pullCalls++;
    onProgress?.call('success');
  }

  @override
  Future<List<List<double>>> embed(List<String> inputs) async {
    embedCalls++;
    embeddedInputs += inputs.length;
    final vectors = [for (final input in inputs) vectorFor(input)];
    if (vectors.isNotEmpty) _dimensions = vectors.first.length;
    return vectors;
  }

  /// Returns the deterministic vector of [input].
  static List<double> vectorFor(String input) {
    final lower = input.toLowerCase();
    return [
      for (final term in terms) (lower.split(term).length - 1).toDouble(),
      0.1,
    ];
  }
}
