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
  late SourceRegistry registry;
  late AgentTargetRoots roots;
  late AlfredoCliCommandRunner runner;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-setup-command-');
    logger = _MockLogger();
    registry = SourceRegistry(
      file: File(p.join(temporary.path, 'config', 'sources.json')),
    );
    roots = AgentTargetRoots(
      userRoot: Directory(p.join(temporary.path, 'user')),
      projectRoot: Directory(p.join(temporary.path, 'project')),
    );
    final source = await createPackageSourceFixture(
      temporary,
      sourceId: 'alfredo',
      packages: const [
        PackageFixture(
          id: 'android-core',
          targets: ['codex', 'claude-code', 'cursor', 'antigravity'],
        ),
      ],
    );
    await registry.addLocal('canonical', source.path);
    runner = AlfredoCliCommandRunner(
      logger: logger,
      sourceRegistry: registry,
      targetRoots: roots,
    );
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('--all installs official packages for every agent', () async {
    expect(await runner.run(['setup', '--all']), ExitCode.success.code);

    for (final directory in [
      '.codex',
      '.claude',
      '.cursor',
      p.join('.gemini', 'config'),
    ]) {
      expect(
        File(
          p.join(
            roots.userRoot.path,
            directory,
            'skills',
            'example',
            'SKILL.md',
          ),
        ).existsSync(),
        isTrue,
      );
    }
    verify(
      () => logger.success(any(that: contains('Installed 1 package'))),
    ).called(4);
  });

  test('an individual flag installs only its selected agent', () async {
    expect(await runner.run(['setup', '--cursor']), ExitCode.success.code);

    expect(
      File(
        p.join(
          roots.userRoot.path,
          '.cursor',
          'skills',
          'example',
          'SKILL.md',
        ),
      ).existsSync(),
      isTrue,
    );
    expect(
      Directory(p.join(roots.userRoot.path, '.codex')).existsSync(),
      false,
    );
  });

  test('accepts multiple agents and the claude-code alias', () async {
    expect(
      await runner.run(['setup', '--codex', '--claude-code']),
      ExitCode.success.code,
    );

    expect(Directory(p.join(roots.userRoot.path, '.codex')).existsSync(), true);
    expect(
      Directory(p.join(roots.userRoot.path, '.claude')).existsSync(),
      true,
    );
    expect(
      Directory(p.join(roots.userRoot.path, '.cursor')).existsSync(),
      false,
    );
  });

  test('requires all or at least one individual agent flag', () async {
    expect(await runner.run(['setup']), ExitCode.usage.code);
    verify(
      () => logger.err(any(that: contains('Select --all'))),
    ).called(1);
  });

  test('rejects all combined with an individual agent flag', () async {
    expect(
      await runner.run(['setup', '--all', '--cursor']),
      ExitCode.usage.code,
    );
    verify(
      () => logger.err(any(that: contains('cannot be combined'))),
    ).called(1);
  });

  test('keeps a locally modified managed file and warns', () async {
    when(
      () => logger.confirm(any(), defaultValue: any(named: 'defaultValue')),
    ).thenReturn(false);
    expect(await runner.run(['setup', '--codex']), ExitCode.success.code);
    final installed = File(
      p.join(roots.userRoot.path, '.codex', 'skills', 'example', 'SKILL.md'),
    );
    await installed.writeAsString('hand edited\n');

    expect(await runner.run(['setup', '--codex']), ExitCode.success.code);

    expect(await installed.readAsString(), 'hand edited\n');
    verify(
      () => logger.warn(any(that: contains('locally modified'))),
    ).called(1);
  });

  test('--force overwrites a locally modified managed file', () async {
    expect(await runner.run(['setup', '--codex']), ExitCode.success.code);
    final installed = File(
      p.join(roots.userRoot.path, '.codex', 'skills', 'example', 'SKILL.md'),
    );
    final pristine = await installed.readAsString();
    await installed.writeAsString('hand edited\n');

    expect(
      await runner.run(['setup', '--codex', '--force']),
      ExitCode.success.code,
    );

    expect(await installed.readAsString(), pristine);
    verifyNever(() => logger.warn(any(that: contains('locally modified'))));
  });
}
