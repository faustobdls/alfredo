import 'dart:io';

import 'package:alfredo_cli/src/command_runner.dart';
import 'package:alfredo_cli/src/source/source.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../helpers/source_fixture.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  late Directory temporary;
  late Logger logger;
  late AlfredoCliCommandRunner runner;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-command-');
    logger = _MockLogger();
    runner = AlfredoCliCommandRunner(
      logger: logger,
      sourceRegistry: SourceRegistry(
        file: File(p.join(temporary.path, 'config', 'sources.json')),
      ),
    );
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('runs the complete local source lifecycle', () async {
    final source = await createSourceFixture(temporary);

    expect(
      await runner.run(['source', 'add', 'primary', '--local', source.path]),
      ExitCode.success.code,
    );
    expect(
      await runner.run(['source', 'list']),
      ExitCode.success.code,
    );
    expect(
      await runner.run(['source', 'show', 'primary']),
      ExitCode.success.code,
    );
    expect(
      await runner.run(['source', 'test', 'primary']),
      ExitCode.success.code,
    );
    expect(
      await runner.run(['source', 'remove', 'primary']),
      ExitCode.success.code,
    );

    verify(
      () => logger.success(any(that: contains('Added source primary'))),
    ).called(1);
    verify(() => logger.info(any(that: contains('primary\tlocal')))).called(1);
    verify(
      () => logger.info(any(that: contains('source_id: test-source'))),
    ).called(1);
    verify(
      () => logger.success(any(that: contains('is valid (1 packages)'))),
    ).called(1);
    verify(() => logger.success('Removed source primary.')).called(1);
  });

  test('returns a configuration exit code for an invalid source', () async {
    final result = await runner.run([
      'source',
      'add',
      'missing',
      '--local',
      p.join(temporary.path, 'does-not-exist'),
    ]);

    expect(result, ExitCode.config.code);
    verify(() => logger.err(any(that: contains('does not exist')))).called(1);
  });

  test('requires one source name and a local path', () async {
    expect(
      await runner.run(['source', 'add', 'primary']),
      ExitCode.usage.code,
    );
    verify(() => logger.err(any(that: contains('--local')))).called(1);
  });
}
