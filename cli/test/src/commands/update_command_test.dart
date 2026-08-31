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
  late Directory source;
  late File sourceSkill;
  late File installedSkill;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'alfredo-update-command-',
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
    source = await createPackageSourceFixture(
      temporary,
      sourceId: 'catalog',
      packages: const [PackageFixture(id: 'android-core')],
    );
    sourceSkill = File(p.join(source.path, 'skills', 'example', 'SKILL.md'));
    installedSkill = File(
      p.join(temporary.path, 'user', '.codex', 'skills', 'example', 'SKILL.md'),
    );
  });

  tearDown(() async => temporary.delete(recursive: true));

  Future<void> install() async {
    expect(
      await runner.run(['source', 'add', 'local', '--local', source.path]),
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
  }

  test('reinstalls changed packages and reports a summary', () async {
    await install();
    await sourceSkill.writeAsString('android-core:NEW\n');

    final code = await runner.run(['update']);

    expect(code, ExitCode.success.code);
    expect(await installedSkill.readAsString(), 'android-core:NEW\n');
    verify(
      () => logger.success(any(that: contains('Updated 1 package'))),
    ).called(1);
  });

  test('dry run leaves files untouched', () async {
    await install();
    await sourceSkill.writeAsString('android-core:NEW\n');

    final code = await runner.run(['update', '--dry-run']);

    expect(code, ExitCode.success.code);
    expect(
      await installedSkill.readAsString(),
      'android-core:skills/example/SKILL.md\n',
    );
    verify(
      () => logger.info(any(that: contains('would refresh content'))),
    ).called(1);
  });

  test('reports when nothing is installed', () async {
    final code = await runner.run(['update']);

    expect(code, ExitCode.success.code);
    verify(
      () => logger.info('No installed Alfredo packages found.'),
    ).called(1);
  });
}
