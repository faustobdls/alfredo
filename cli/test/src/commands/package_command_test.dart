import 'dart:io';

import 'package:alfredo_cli/src/command_runner.dart';
import 'package:alfredo_cli/src/package/package.dart';
import 'package:alfredo_cli/src/source/source.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../helpers/package_fixture.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  late Directory temporary;
  late Logger logger;
  late AlfredoCliCommandRunner runner;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'alfredo-package-command-',
    );
    logger = _MockLogger();
    runner = AlfredoCliCommandRunner(
      logger: logger,
      sourceRegistry: SourceRegistry(
        file: File(p.join(temporary.path, 'config', 'sources.json')),
      ),
      targetRoots: AgentTargetRoots(
        userRoot: Directory(p.join(temporary.path, 'user')),
        projectRoot: Directory(p.join(temporary.path, 'project')),
      ),
    );
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('runs package discovery and installation lifecycle', () async {
    final source = await createPackageSourceFixture(
      temporary,
      sourceId: 'command-source',
      packages: const [
        PackageFixture(
          id: 'android-core',
          targets: ['codex', 'generic'],
        ),
      ],
    );

    expect(
      await runner.run(['source', 'add', 'primary', '--local', source.path]),
      ExitCode.success.code,
    );
    expect(await runner.run(['package', 'list']), ExitCode.success.code);
    expect(
      await runner.run(['package', 'search', 'android']),
      ExitCode.success.code,
    );
    expect(
      await runner.run(['package', 'show', 'android-core']),
      ExitCode.success.code,
    );
    expect(
      await runner.run([
        'package',
        'install',
        'android-core',
        '--target',
        'codex',
        '--scope',
        'user',
      ]),
      ExitCode.success.code,
    );

    final installed = File(
      p.join(
        temporary.path,
        'user',
        '.codex',
        'skills',
        'example',
        'SKILL.md',
      ),
    );
    expect(installed.existsSync(), isTrue);
    expect(
      await runner.run([
        'package',
        'status',
        '--target',
        'codex',
        '--scope',
        'user',
      ]),
      ExitCode.success.code,
    );
    expect(
      await runner.run([
        'package',
        'diff',
        '--target',
        'codex',
        '--scope',
        'user',
      ]),
      ExitCode.success.code,
    );
    expect(
      await runner.run([
        'package',
        'uninstall',
        'android-core',
        '--target',
        'codex',
        '--scope',
        'user',
      ]),
      ExitCode.success.code,
    );
    expect(installed.existsSync(), isFalse);

    verify(
      () => logger.success(any(that: contains('Installed 1 package'))),
    ).called(1);
    verify(() => logger.info('No managed file changes.')).called(1);
    verify(
      () => logger.success(any(that: contains('0 modified file'))),
    ).called(1);
  });

  test('returns a configuration exit code for an unknown package', () async {
    expect(
      await runner.run([
        'package',
        'install',
        'missing',
        '--target',
        'generic',
      ]),
      ExitCode.config.code,
    );
    verify(() => logger.err(any(that: contains('not available')))).called(1);
  });
}
