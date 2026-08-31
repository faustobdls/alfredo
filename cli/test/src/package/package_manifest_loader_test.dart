import 'dart:io';

import 'package:alfredo_cli/src/package/package_manifest_loader.dart';
import 'package:alfredo_cli/src/package/package_models.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../helpers/package_fixture.dart';

void main() {
  late Directory temporary;
  late PackageManifestLoader loader;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'alfredo-package-loader-',
    );
    loader = const PackageManifestLoader();
  });

  tearDown(() async => temporary.delete(recursive: true));

  test(
    'loads and digests source-root-relative content deterministically',
    () async {
      final source = await createPackageSourceFixture(
        temporary,
        sourceId: 'catalog',
        packages: const [PackageFixture(id: 'android-core')],
      );
      final packageRoot = p.join(source.path, 'packages', 'android-core');
      final manifest = await loader.load(packageRoot);

      final first = await loader.digest(
        packageDirectory: packageRoot,
        contentRoot: source.path,
        manifest: manifest,
      );
      await File(
        p.join(source.path, 'skills', 'example', 'SKILL.md'),
      ).writeAsString(
        'changed\n',
      );
      final second = await loader.digest(
        packageDirectory: packageRoot,
        contentRoot: source.path,
        manifest: manifest,
      );

      expect(first, hasLength(64));
      expect(second, isNot(first));
      final files = await loader.filesForContents(source.path, manifest);
      expect(
        files.single.path,
        endsWith(p.join('skills', 'example', 'SKILL.md')),
      );
    },
  );

  test('rejects a missing declared source-root content path', () async {
    final source = await createPackageSourceFixture(
      temporary,
      sourceId: 'catalog',
      packages: const [PackageFixture(id: 'android-core')],
    );
    final packageRoot = p.join(source.path, 'packages', 'android-core');
    final manifest = await loader.load(packageRoot);
    await File(p.join(source.path, 'skills', 'example', 'SKILL.md')).delete();

    expect(
      () => loader.filesForContents(source.path, manifest),
      throwsA(isA<PackageException>()),
    );
  });
}
