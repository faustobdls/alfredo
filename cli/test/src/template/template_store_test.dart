import 'dart:io';

import 'package:alfredo_cli/src/template/template.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late TemplateRoots roots;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-template-');
    roots = TemplateRoots(projectRoot: temporary, userRoot: temporary);
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Future<void> writeTemplate(
    String dir,
    String name, {
    required String kind,
    String description = 'Use for something. Not for something else.',
    String body = 'Prose contract.',
  }) async {
    final file = File(
      p.join(temporary.path, dir, name, 'TEMPLATE.md'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('''
---
schema_version: 1
name: $name
kind: $kind
description: $description
---

$body
''');
  }

  test('parses and lists canonical templates', () async {
    await writeTemplate('templates', 'bank-email', kind: 'email');
    await writeTemplate('templates', 'bank-slides', kind: 'slides');

    final templates = await TemplateStore(roots: roots).list();

    expect(templates.map((t) => t.name), ['bank-email', 'bank-slides']);
    expect(templates.first.kind, 'email');
    expect(templates.first.origin, TemplateOrigin.canonical);
    expect(templates.first.body, 'Prose contract.');
  });

  test(
    'canonical templates win over installed copies of the same name',
    () async {
      await writeTemplate(
        'templates',
        'bank-email',
        kind: 'email',
        description: 'Canonical copy.',
      );
      await writeTemplate(
        '.claude/templates',
        'bank-email',
        kind: 'email',
        description: 'Installed copy.',
      );

      final templates = await TemplateStore(roots: roots).list();

      expect(templates, hasLength(1));
      expect(templates.single.description, 'Canonical copy.');
      expect(templates.single.origin, TemplateOrigin.canonical);
    },
  );

  test('matches by exact name, then exact kind, then keywords', () async {
    await writeTemplate('templates', 'bank-email', kind: 'email');
    await writeTemplate(
      'templates',
      'newsletter',
      kind: 'email',
      description: 'Use for the monthly newsletter blast.',
    );

    final store = TemplateStore(roots: roots);

    expect((await store.match('newsletter'))?.reason, 'name');
    final byKind = await store.match('email');
    expect(byKind?.reason, 'exact-kind');
    expect(byKind?.template.name, 'bank-email');
    final byKeyword = await store.match('monthly blast');
    expect(byKeyword?.reason, 'keyword');
    expect(byKeyword?.template.name, 'newsletter');
    expect(await store.match('nonexistent-artifact'), isNull);
  });

  test('rejects a template with invalid frontmatter', () async {
    final file = File(
      p.join(temporary.path, 'templates', 'broken', 'TEMPLATE.md'),
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('''
---
schema_version: 1
name: Broken Name
kind: email
description: bad name
---

body
''');

    expect(
      () => TemplateStore(roots: roots).list(),
      throwsA(isA<TemplateException>()),
    );
  });
}
