import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/source/source.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../helpers/source_fixture.dart';

void main() {
  late Directory temporary;
  late File registryFile;
  late SourceRegistry registry;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-registry-');
    registryFile = File(p.join(temporary.path, 'config', 'sources.json'));
    registry = SourceRegistry(file: registryFile);
  });

  tearDown(() async {
    if (Platform.isWindows) {
      await Process.run('attrib', [
        '-R',
        p.join(temporary.path, '*'),
        '/S',
        '/D',
      ]);
    } else {
      await Process.run('chmod', ['-R', 'u+w', temporary.path]);
    }
    await temporary.delete(recursive: true);
  });

  test('persists and lists local sources in name order', () async {
    final sourceB = await createSourceFixture(
      temporary,
      sourceId: 'source-b',
    );
    final sourceA = await createSourceFixture(
      temporary,
      sourceId: 'source-a',
    );

    await registry.addLocal('beta', sourceB.path);
    await registry.addLocal('alpha', sourceA.path);

    expect((await registry.list()).map((source) => source.name), [
      'alpha',
      'beta',
    ]);
    final document = jsonDecode(await registryFile.readAsString()) as Map;
    expect(document['version'], 1);
    expect(document['sources'] as List, hasLength(2));
  });

  test('rejects duplicate names and canonical paths', () async {
    final source = await createSourceFixture(temporary);
    await registry.addLocal('primary', source.path);

    expect(
      () => registry.addLocal('primary', source.path),
      throwsA(isA<SourceException>()),
    );
    expect(
      () => registry.addLocal('alias', source.path),
      throwsA(isA<SourceException>()),
    );
  });

  test(
    'tests and removes a registration without changing its source',
    () async {
      final source = await createSourceFixture(temporary);
      final manifest = File(p.join(source.path, 'alfredo-source.yaml'));
      final before = await manifest.readAsString();
      await registry.addLocal('primary', source.path);

      final catalog = await registry.test('primary');
      final removed = await registry.remove('primary');

      expect(catalog.packages, hasLength(1));
      expect(removed.name, 'primary');
      expect(await registry.list(), isEmpty);
      expect(await manifest.readAsString(), before);
    },
  );

  test(
    'leaves the registry unchanged when removing an unknown source',
    () async {
      final source = await createSourceFixture(temporary);
      await registry.addLocal('primary', source.path);
      final before = await registryFile.readAsString();

      expect(
        () => registry.remove('missing'),
        throwsA(isA<SourceException>()),
      );
      expect(await registryFile.readAsString(), before);
    },
  );

  group('refresh', () {
    late SourceRegistry cachedRegistry;

    setUp(() {
      cachedRegistry = SourceRegistry(
        file: registryFile,
        snapshots: SourceSnapshotCache(
          directory: Directory(p.join(temporary.path, 'cache')),
        ),
      );
    });

    test('reports a local source as live without rewriting', () async {
      final source = await createSourceFixture(temporary);
      await cachedRegistry.addLocal('primary', source.path);
      final before = await registryFile.readAsString();

      final refresh = await cachedRegistry.refresh('primary');

      expect(refresh.kind, SourceRefreshKind.live);
      expect(await registryFile.readAsString(), before);
    });

    test('reports an archive source as pinned', () async {
      final source = await createSourceFixture(temporary, sourceId: 'bundle');
      final archive = Archive()
        ..add(
          ArchiveFile.string(
            'bundle/alfredo-source.yaml',
            await File(
              p.join(source.path, 'alfredo-source.yaml'),
            ).readAsString(),
          ),
        )
        ..add(
          ArchiveFile.string(
            'bundle/packages/android-core/package.yaml',
            await File(
              p.join(source.path, 'packages', 'android-core', 'package.yaml'),
            ).readAsString(),
          ),
        );
      final file = File(p.join(temporary.path, 'bundle.zip'));
      await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
      final digest = sha256.convert(await file.readAsBytes()).toString();
      await cachedRegistry.addArchive(
        'bundle',
        url: file.uri,
        sha256: digest,
      );

      final refresh = await cachedRegistry.refresh('bundle');

      expect(refresh.kind, SourceRefreshKind.pinned);
    });

    test('advances a Git source when its branch moved', () async {
      final source = await createSourceFixture(temporary, sourceId: 'repo');
      await _git(['init', '-b', 'main', source.path]);
      await _git(['-C', source.path, 'config', 'user.email', 'a@test']);
      await _git(['-C', source.path, 'config', 'user.name', 'Alfredo']);
      await _git(['-C', source.path, 'add', '.']);
      await _git(['-C', source.path, 'commit', '-m', 'one']);
      await cachedRegistry.addGit(
        'remote',
        url: source.uri,
        revision: 'main',
      );
      final firstResolved = (await cachedRegistry.get(
        'remote',
      )).transport!.resolvedRevision;

      expect(
        (await cachedRegistry.refresh('remote')).kind,
        SourceRefreshKind.unchanged,
      );

      await File(p.join(source.path, 'CHANGES.md')).writeAsString('two\n');
      await _git(['-C', source.path, 'add', '.']);
      await _git(['-C', source.path, 'commit', '-m', 'two']);

      final refresh = await cachedRegistry.refresh('remote');

      expect(refresh.kind, SourceRefreshKind.updated);
      expect(refresh.previousRevision, firstResolved);
      expect(refresh.newRevision, isNot(firstResolved));
      expect(
        (await cachedRegistry.get('remote')).transport!.resolvedRevision,
        refresh.newRevision,
      );
    });
  });
}

Future<void> _git(List<String> arguments) async {
  final result = await Process.run('git', arguments);
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}
