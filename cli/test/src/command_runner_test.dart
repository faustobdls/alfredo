import 'package:alfredo_cli/src/command_runner.dart';
import 'package:alfredo_cli/src/version.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
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
