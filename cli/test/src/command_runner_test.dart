import 'dart:io';

import 'package:alfredo_cli/src/command_runner.dart';
import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:alfredo_cli/src/version.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  group('AlfredoCliCommandRunner', () {
    late Logger logger;
    late AlfredoCliCommandRunner commandRunner;

    setUp(() {
      logger = _MockLogger();
      commandRunner = AlfredoCliCommandRunner(logger: logger);
    });

    test('uses the Very Good completion command runner', () {
      expect(commandRunner, isA<CompletionCommandRunner<int>>());
    });

    test('can be instantiated with default dependencies', () {
      expect(AlfredoCliCommandRunner(), isNotNull);
    });

    test('does not expose the generated sample command', () {
      expect(commandRunner.usage, isNot(contains('sample')));
    });

    test('exposes setup, source, package, and memory management commands', () {
      expect(commandRunner.usage, contains('setup'));
      expect(commandRunner.usage, contains('source'));
      expect(commandRunner.usage, contains('package'));
      expect(commandRunner.usage, contains('memory'));
    });

    test('documents the memory command group', () async {
      final result = await commandRunner.run(['memory', '--help']);
      final memory = commandRunner.commands['memory']!;

      expect(result, ExitCode.success.code);
      expect(memory.invocation, contains('memory'));
      expect(
        memory.subcommands.keys,
        containsAll(<String>[
          'setup',
          'add',
          'search',
          'list',
          'digest',
          'index',
          'capture',
        ]),
      );
    });

    test('maps a MemoryException to a configuration exit code', () async {
      final temporary = await Directory.systemTemp.createTemp(
        'alfredo-runner-memory-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final memory = Directory(p.join(temporary.path, 'memory'));
      await MemoryStore(directory: memory).ensureSkeleton();

      final result = await AlfredoCliCommandRunner(
        logger: logger,
        memoryRoots: MemoryRoots(
          userDirectory: memory,
          projectDirectory: Directory(p.join(temporary.path, 'project')),
        ),
      ).run(['memory', 'index', '--scope', 'user']);

      expect(result, ExitCode.config.code);
      verify(
        () => logger.err(any(that: contains('Embeddings are disabled'))),
      ).called(1);
    });

    test('exposes the update and upgrade lifecycle commands', () {
      expect(commandRunner.usage, contains('update'));
      expect(commandRunner.usage, contains('upgrade'));
    });

    test('handles FormatException', () async {
      const exception = FormatException('oops!');
      var firstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (firstInvocation) {
          firstInvocation = false;
          throw exception;
        }
      });

      final result = await commandRunner.run(['--version']);

      expect(result, ExitCode.usage.code);
      verify(() => logger.err(exception.message)).called(1);
      verify(() => logger.detail(any())).called(1);
    });

    test('handles UsageException', () async {
      final exception = UsageException('oops!', 'exception usage');
      var firstInvocation = true;
      when(() => logger.info(any())).thenAnswer((_) {
        if (firstInvocation) {
          firstInvocation = false;
          throw exception;
        }
      });

      final result = await commandRunner.run(['--version']);

      expect(result, ExitCode.usage.code);
      verify(() => logger.err(exception.message)).called(1);
      verify(() => logger.info('exception usage')).called(1);
    });

    test('--version outputs the current version', () async {
      final result = await commandRunner.run(['--version']);

      expect(result, ExitCode.success.code);
      verify(() => logger.info(packageVersion)).called(1);
    });

    test('--verbose enables detailed logging', () async {
      final result = await commandRunner.run(['--verbose']);

      expect(result, ExitCode.success.code);
      verify(() => logger.detail('Argument information:')).called(1);
      verify(() => logger.detail('  Top level options:')).called(1);
      verify(() => logger.detail('  - verbose: true')).called(1);
      verify(() => logger.info(commandRunner.usage)).called(1);
    });
  });
}
