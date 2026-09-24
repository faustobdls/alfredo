import 'dart:io';

import 'package:alfredo_cli/src/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  late Directory temporary;
  late Logger logger;
  late AlfredoCliCommandRunner runner;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-hooks-test-');
    logger = _MockLogger();
    runner = AlfredoCliCommandRunner(logger: logger);
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('fails to install hooks when not a git repository', () async {
    final originalDir = Directory.current;
    try {
      Directory.current = temporary;
      final exitCode = await runner.run(['hooks', 'install']);
      expect(exitCode, ExitCode.usage.code);
      verify(() => logger.err(any(that: contains('Not a git repository'))))
          .called(1);
    } finally {
      Directory.current = originalDir;
    }
  });

  test('installs and uninstalls pre-commit hook in a git repository', () async {
    final originalDir = Directory.current;
    try {
      Directory.current = temporary;
      Directory(p.join(temporary.path, '.git')).createSync();

      // Install
      final installCode = await runner.run(['hooks', 'install']);
      expect(installCode, ExitCode.success.code);

      final hookFile = File(
        p.join(temporary.path, '.git', 'hooks', 'pre-commit'),
      );
      expect(hookFile.existsSync(), isTrue);
      expect(
        await hookFile.readAsString(),
        contains('Alfredo pre-commit hook'),
      );

      verify(() => logger.success(any(that: contains('Installed Git hooks'))))
          .called(1);

      // Uninstall
      final uninstallCode = await runner.run(['hooks', 'uninstall']);
      expect(uninstallCode, ExitCode.success.code);
      expect(hookFile.existsSync(), isFalse);
      verify(() => logger.success(any(that: contains('Uninstalled Git hooks'))))
          .called(1);
    } finally {
      Directory.current = originalDir;
    }
  });
}
