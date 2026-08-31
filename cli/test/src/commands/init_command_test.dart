import 'dart:io';

import 'package:alfredo_cli/src/command_runner.dart';
import 'package:alfredo_cli/src/source/source.dart';
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
    temporary = await Directory.systemTemp.createTemp('alfredo-init-');
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

  test('scaffolds a source that registers and validates', () async {
    final target = p.join(temporary.path, 'my-source');

    expect(
      await runner.run(['init', 'source', target]),
      ExitCode.success.code,
    );

    expect(File(p.join(target, 'alfredo-source.yaml')).existsSync(), isTrue);
    expect(
      File(
        p.join(target, 'packages', 'example-core', 'package.yaml'),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(target, 'skills', 'hello', 'SKILL.md')).existsSync(),
      isTrue,
    );
    expect(File(p.join(target, 'agents', '.gitkeep')).existsSync(), isTrue);
    expect(
      File(p.join(target, 'alfredo-source.yaml')).readAsStringSync(),
      contains('id: my-source'),
    );

    expect(
      await runner.run(['source', 'add', 'mine', '--local', target]),
      ExitCode.success.code,
    );
    expect(
      await runner.run(['source', 'test', 'mine']),
      ExitCode.success.code,
    );
  });

  test('honours --id and --name overrides', () async {
    final target = p.join(temporary.path, 'Weird Name!');

    expect(
      await runner.run([
        'init',
        'source',
        target,
        '--id',
        'team-tools',
        '--name',
        'Team Tools',
      ]),
      ExitCode.success.code,
    );

    final manifest = File(
      p.join(target, 'alfredo-source.yaml'),
    ).readAsStringSync();
    expect(manifest, contains('id: team-tools'));
    expect(manifest, contains('name: Team Tools'));
  });

  test('rejects an unusable derived id without --id', () async {
    final target = p.join(temporary.path, '123 not valid');

    expect(
      await runner.run(['init', 'source', target]),
      ExitCode.usage.code,
    );
    expect(Directory(target).existsSync(), isFalse);
  });

  test('refuses a non-empty directory unless forced', () async {
    final target = Directory(p.join(temporary.path, 'occupied'))
      ..createSync(recursive: true);
    File(p.join(target.path, 'keep.txt')).writeAsStringSync('mine');

    expect(
      await runner.run(['init', 'source', target.path]),
      ExitCode.usage.code,
    );
    expect(
      File(p.join(target.path, 'alfredo-source.yaml')).existsSync(),
      isFalse,
    );

    expect(
      await runner.run(['init', 'source', target.path, '--force']),
      ExitCode.success.code,
    );
    expect(
      File(p.join(target.path, 'alfredo-source.yaml')).existsSync(),
      isTrue,
    );
    expect(File(p.join(target.path, 'keep.txt')).readAsStringSync(), 'mine');
  });

  test('refuses to overwrite an existing scaffold file', () async {
    final target = Directory(p.join(temporary.path, 'partial'))
      ..createSync(recursive: true);
    File(p.join(target.path, 'README.md')).writeAsStringSync('do not touch');

    expect(
      await runner.run(['init', 'source', target.path, '--force']),
      ExitCode.usage.code,
    );
    expect(
      File(p.join(target.path, 'README.md')).readAsStringSync(),
      'do not touch',
    );
  });
}
