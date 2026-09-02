import 'dart:io';

import 'package:alfredo_cli/src/command_runner.dart';
import 'package:alfredo_cli/src/template/template.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  late Directory temporary;
  late Logger logger;
  late AlfredoCliCommandRunner runner;
  final printed = <String>[];

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-template-cmd-');
    logger = _MockLogger();
    printed.clear();
    when(() => logger.info(any())).thenAnswer((invocation) {
      printed.add(invocation.positionalArguments.first as String);
    });
    runner = AlfredoCliCommandRunner(
      logger: logger,
      templateRoots: TemplateRoots(
        projectRoot: temporary,
        userRoot: temporary,
      ),
    );
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  File templateFile(String name) =>
      File(p.join(temporary.path, 'templates', name, 'TEMPLATE.md'));

  test('new scaffolds a valid template that validate accepts', () async {
    expect(
      await runner.run([
        'template',
        'new',
        'bank-email',
        '--kind',
        'email',
        '--description',
        'Use for client email. Not for internal chat.',
        '--format-target',
        'email',
      ]),
      ExitCode.success.code,
    );
    expect(templateFile('bank-email').existsSync(), isTrue);
    expect(
      templateFile('bank-email').readAsStringSync(),
      contains('kind: email'),
    );
    expect(
      templateFile('bank-email').readAsStringSync(),
      contains('description: Use for client email. Not for internal chat.'),
    );
    expect(
      templateFile('bank-email').readAsStringSync(),
      contains('target: email'),
    );

    expect(
      await runner.run(['template', 'validate', 'bank-email']),
      ExitCode.success.code,
    );
  });

  test('new refuses an existing template without --force', () async {
    templateFile('bank-email')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('keep me');

    expect(
      await runner.run([
        'template',
        'new',
        'bank-email',
        '--kind',
        'email',
        '--description',
        'Use for client email.',
        '--format-target',
        'email',
      ]),
      ExitCode.usage.code,
    );
    expect(templateFile('bank-email').readAsStringSync(), 'keep me');
  });

  test('new rejects an invalid kind', () async {
    expect(
      await runner.run([
        'template',
        'new',
        'bank-email',
        '--kind',
        'Email!',
        '--description',
        'Use for client email.',
        '--format-target',
        'email',
      ]),
      ExitCode.usage.code,
    );
  });

  test('new requires description and format target', () async {
    expect(
      await runner.run(['template', 'new', 'bank-email', '--kind', 'email']),
      ExitCode.usage.code,
    );
    expect(templateFile('bank-email').existsSync(), isFalse);

    expect(
      await runner.run([
        'template',
        'new',
        'bank-email',
        '--kind',
        'email',
        '--description',
        'Use for client email.',
      ]),
      ExitCode.usage.code,
    );
    expect(templateFile('bank-email').existsSync(), isFalse);
  });

  test('new accepts project-defined format targets', () async {
    expect(
      await runner.run([
        'template',
        'new',
        'ledger-note',
        '--kind',
        'note',
        '--description',
        'Use for ledger notes.',
        '--format-target',
        'custom-ledger-file',
      ]),
      ExitCode.success.code,
    );

    expect(
      templateFile('ledger-note').readAsStringSync(),
      contains('target: custom-ledger-file'),
    );
  });

  test('list and match resolve an authored template', () async {
    await runner.run([
      'template',
      'new',
      'bank-email',
      '--kind',
      'email',
      '--description',
      'Use for client email. Not for internal chat.',
      '--format-target',
      'email',
    ]);

    expect(
      await runner.run(['template', 'list', '--json']),
      ExitCode.success.code,
    );
    expect(printed.join(), contains('"name": "bank-email"'));

    printed.clear();
    expect(
      await runner.run(['template', 'match', 'email', '--json']),
      ExitCode.success.code,
    );
    expect(printed.join(), contains('"reason": "exact-kind"'));
    expect(printed.join(), contains('"name": "bank-email"'));
  });

  test('validate fails when a template is malformed', () async {
    templateFile('broken')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('''
---
schema_version: 1
name: broken
kind: email
description: missing closing fence
''');

    expect(
      await runner.run(['template', 'validate']),
      ExitCode.config.code,
    );
  });

  test('match reports no result cleanly', () async {
    expect(
      await runner.run(['template', 'match', 'nothing-here']),
      ExitCode.success.code,
    );
    expect(printed.join(), contains('No template matches'));
  });
}
