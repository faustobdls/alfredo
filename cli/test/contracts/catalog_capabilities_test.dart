import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final repoRoot = Directory.current.parent.path;
  const skills = <String>[
    'capability-authoring',
    'agent-instruction-review',
    'prompt-refiner',
    'visual-verdict',
    'grill-me',
  ];

  test('skills core declares the generic workflow capabilities', () async {
    final manifest = await File(
      p.join(repoRoot, 'packages', 'skills-core', 'package.yaml'),
    ).readAsString();

    for (final skill in skills) {
      expect(manifest, contains('- skills/$skill'));
      final document = await File(
        p.join(repoRoot, 'skills', skill, 'SKILL.md'),
      ).readAsString();
      expect(document, contains('name: $skill'));
      expect(document, contains('description: Use '));
      expect(document, contains('. Not for '));
    }
  });

  test('instruction reviewer is a canonical read-only agent', () async {
    final document = await File(
      p.join(repoRoot, 'agents', 'agent-instruction-reviewer.md'),
    ).readAsString();

    expect(document, contains('name: agent-instruction-reviewer'));
    expect(document, contains('tools: Read, Grep, Glob, Bash'));
    expect(document, contains('## Standards'));
    expect(document, contains('## Method'));
    expect(document, contains('## What I will not do'));
    expect(document, contains('## How I report back'));
  });

  test('visual verdict reports when inspection is unavailable', () async {
    final document = await File(
      p.join(repoRoot, 'skills', 'visual-verdict', 'SKILL.md'),
    ).readAsString();

    expect(document, contains('"status": "assessed"'));
    expect(document, contains('"status": "blocked"'));
    expect(document, contains('image-viewing capability'));
  });
}
