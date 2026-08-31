import 'dart:io';

import 'package:alfredo_cli/src/source/source.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../helpers/source_fixture.dart';

void main() {
  const loader = SourceManifestLoader();
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-loader-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('loads the source and discovers package manifests', () async {
    final source = await createSourceFixture(temporary);

    final catalog = await loader.load(source.path);

    expect(catalog.id, 'test-source');
    expect(catalog.packages, hasLength(1));
    expect(catalog.packages.single.id, 'android-core');
    expect(catalog.packages.single.version, '1.2.3');
    expect(catalog.packages.single.path, 'packages/android-core/package.yaml');
  });

  test('rejects an unsupported source schema version', () async {
    final source = await createSourceFixture(temporary);
    final manifest = File(p.join(source.path, 'alfredo-source.yaml'));
    await manifest.writeAsString(
      (await manifest.readAsString()).replaceFirst(
        'schema_version: 1',
        'schema_version: 2',
      ),
    );

    expect(
      () => loader.load(source.path),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          contains('schema version'),
        ),
      ),
    );
  });

  test('rejects package directory traversal', () async {
    final source = await createSourceFixture(temporary);
    final manifest = File(p.join(source.path, 'alfredo-source.yaml'));
    await manifest.writeAsString(
      (await manifest.readAsString()).replaceFirst(
        'packages_path: packages',
        'packages_path: ../packages',
      ),
    );

    expect(
      () => loader.load(source.path),
      throwsA(isA<SourceException>()),
    );
  });

  test('rejects traversal in the local source path', () async {
    final source = await createSourceFixture(temporary);
    final manifest = File(p.join(source.path, 'alfredo-source.yaml'));
    await manifest.writeAsString(
      (await manifest.readAsString()).replaceFirst(
        'path: .',
        'path: ../escape',
      ),
    );

    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));
  });

  test('rejects traversal in the profiles path', () async {
    final source = await createSourceFixture(temporary);
    final manifest = File(p.join(source.path, 'alfredo-source.yaml'));
    await manifest.writeAsString(
      '${await manifest.readAsString()}profiles_path: ../profiles\n',
    );

    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));
  });

  test('rejects an absolute packages path', () async {
    final source = await createSourceFixture(temporary);
    final manifest = File(p.join(source.path, 'alfredo-source.yaml'));
    await manifest.writeAsString(
      (await manifest.readAsString()).replaceFirst(
        'packages_path: packages',
        'packages_path: /tmp/packages',
      ),
    );

    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));
  });

  test('rejects a package directory without a manifest', () async {
    final source = await createSourceFixture(temporary);
    await Directory(p.join(source.path, 'packages', 'missing')).create();

    expect(
      () => loader.load(source.path),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          contains('missing its manifest'),
        ),
      ),
    );
  });

  test('rejects duplicate package ids', () async {
    final source = await createSourceFixture(temporary);
    final duplicate = await Directory(
      p.join(source.path, 'packages', 'duplicate-directory'),
    ).create();
    final original = File(
      p.join(source.path, 'packages', 'android-core', 'package.yaml'),
    );
    await original.copy(p.join(duplicate.path, 'package.yaml'));

    expect(
      () => loader.load(source.path),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          contains('Duplicate package id'),
        ),
      ),
    );
  });

  test('rejects ids that do not start with a letter', () async {
    final source = await createSourceFixture(temporary);
    final manifest = File(p.join(source.path, 'alfredo-source.yaml'));
    await manifest.writeAsString(
      (await manifest.readAsString()).replaceFirst(
        'id: test-source',
        'id: 1-test-source',
      ),
    );

    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));
  });

  test('rejects a package id that does not start with a letter', () async {
    final source = await createSourceFixture(temporary);
    final manifest = File(
      p.join(source.path, 'packages', 'android-core', 'package.yaml'),
    );
    await manifest.writeAsString(
      (await manifest.readAsString()).replaceFirst(
        'id: android-core',
        'id: 1-android-core',
      ),
    );

    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));
  });

  test('rejects whitespace around patterned fields', () async {
    final source = await createSourceFixture(temporary);
    final manifest = File(
      p.join(source.path, 'packages', 'android-core', 'package.yaml'),
    );
    final valid = await manifest.readAsString();
    await manifest.writeAsString(
      valid.replaceFirst('id: android-core', 'id: " android-core "'),
    );
    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));

    await manifest.writeAsString(
      valid.replaceFirst('version: 1.2.3', 'version: " 1.2.3 "'),
    );
    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));
  });

  test('rejects unknown source and package properties', () async {
    final source = await createSourceFixture(temporary);
    final sourceManifest = File(p.join(source.path, 'alfredo-source.yaml'));
    await sourceManifest.writeAsString(
      '${await sourceManifest.readAsString()}unsupported: true\n',
    );
    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));

    await sourceManifest.writeAsString(
      (await sourceManifest.readAsString()).replaceFirst(
        'unsupported: true\n',
        '',
      ),
    );
    final packageManifest = File(
      p.join(source.path, 'packages', 'android-core', 'package.yaml'),
    );
    await packageManifest.writeAsString(
      '${await packageManifest.readAsString()}unsupported: true\n',
    );
    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));
  });

  test('rejects invalid and duplicate package targets', () async {
    final source = await createSourceFixture(temporary);
    final manifest = File(
      p.join(source.path, 'packages', 'android-core', 'package.yaml'),
    );
    final valid = await manifest.readAsString();
    await manifest.writeAsString(
      valid.replaceFirst('targets: [codex]', 'targets: [unknown]'),
    );
    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));

    await manifest.writeAsString(
      valid.replaceFirst('targets: [codex]', 'targets: [codex, codex]'),
    );
    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));
  });

  test('rejects unknown nested properties', () async {
    final source = await createSourceFixture(temporary);
    final manifest = File(
      p.join(source.path, 'packages', 'android-core', 'package.yaml'),
    );
    final valid = await manifest.readAsString();
    await manifest.writeAsString(
      valid.replaceFirst('  rules: []', '  rules: []\n  unknown: []'),
    );
    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));

    await manifest.writeAsString(
      valid.replaceFirst(
        'dependencies: []',
        'dependencies: [{id: core, version: 1.0.0, unknown: true}]',
      ),
    );
    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));
  });

  test('rejects null dependency and conflict lists', () async {
    final source = await createSourceFixture(temporary);
    final manifest = File(
      p.join(source.path, 'packages', 'android-core', 'package.yaml'),
    );
    final valid = await manifest.readAsString();
    await manifest.writeAsString(
      valid.replaceFirst('dependencies: []', 'dependencies: null'),
    );
    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));

    await manifest.writeAsString(
      valid.replaceFirst('conflicts: []', 'conflicts: null'),
    );
    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));
  });

  test('rejects duplicate package content paths', () async {
    final source = await createSourceFixture(temporary);
    final manifest = File(
      p.join(source.path, 'packages', 'android-core', 'package.yaml'),
    );
    await manifest.writeAsString(
      (await manifest.readAsString()).replaceFirst(
        '  skills: []',
        '  skills: [skills/a, skills/a]',
      ),
    );

    expect(() => loader.load(source.path), throwsA(isA<SourceException>()));
  });

  for (final contentKind in [
    'skills',
    'rules',
    'scripts',
    'assets',
    'references',
  ]) {
    test('rejects traversal in package $contentKind paths', () async {
      final source = await createSourceFixture(temporary);
      final manifest = File(
        p.join(source.path, 'packages', 'android-core', 'package.yaml'),
      );
      var contents = await manifest.readAsString();
      if (contentKind == 'skills' || contentKind == 'rules') {
        contents = contents.replaceFirst(
          '  $contentKind: []',
          '  $contentKind: [../escape]',
        );
      } else {
        contents = contents.replaceFirst(
          '  rules: []',
          '  rules: []\n  $contentKind: [../escape]',
        );
      }
      await manifest.writeAsString(contents);

      expect(() => loader.load(source.path), throwsA(isA<SourceException>()));
    });
  }

  test('reports malformed YAML as a source error', () async {
    final source = await createSourceFixture(temporary);
    await File(
      p.join(source.path, 'alfredo-source.yaml'),
    ).writeAsString('schema_version: [');

    expect(
      () => loader.load(source.path),
      throwsA(isA<SourceException>()),
    );
  });

  test('rejects an invalid package version', () async {
    final source = await createSourceFixture(temporary, version: 'latest');

    expect(
      () => loader.load(source.path),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          contains('semantic version'),
        ),
      ),
    );
  });

  test('rejects a packages directory symlink outside the source', () async {
    if (Platform.isWindows) return;
    final source = await createSourceFixture(temporary);
    final packages = Directory(p.join(source.path, 'packages'));
    await packages.delete(recursive: true);
    final outside = await Directory(
      p.join(temporary.path, 'outside'),
    ).create();
    await Link(packages.path).create(outside.path);

    expect(
      () => loader.load(source.path),
      throwsA(isA<SourceException>()),
    );
  });
}
