import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/source/source.dart';
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
}
