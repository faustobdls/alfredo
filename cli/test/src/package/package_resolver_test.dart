import 'dart:io';

import 'package:alfredo_cli/src/package/package_catalog.dart';
import 'package:alfredo_cli/src/package/package_models.dart';
import 'package:alfredo_cli/src/package/package_resolver.dart';
import 'package:alfredo_cli/src/source/source_registry.dart';
import 'package:test/test.dart';

import '../../helpers/package_fixture.dart';

void main() {
  late Directory temporary;
  late SourceRegistry registry;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-resolver-');
    registry = SourceRegistry(file: File('${temporary.path}/sources.json'));
  });

  tearDown(() async => temporary.delete(recursive: true));

  Future<PackageResolver> resolverFor(List<PackageFixture> fixtures) async {
    final source = await createPackageSourceFixture(
      temporary,
      sourceId: 'catalog',
      packages: fixtures,
    );
    await registry.addLocal('local', source.path);
    return PackageResolver(PackageCatalog(registry: registry));
  }

  test(
    'resolves dependencies before dependents with a reproducible lock',
    () async {
      final resolver = await resolverFor(const [
        PackageFixture(id: 'base'),
        PackageFixture(
          id: 'app',
          dependencies: [
            {'id': 'base', 'version': '1.0.0'},
          ],
        ),
      ]);

      final resolution = await resolver.resolve(
        packageIds: ['app'],
        target: 'codex',
      );

      expect(resolution.packages.map((item) => item.manifest.id), [
        'base',
        'app',
      ]);
      expect(
        PackageLockfile.fromResolution(
          resolution,
        ).packages.map((item) => item.id),
        ['app', 'base'],
      );
    },
  );

  test('rejects dependency cycles', () async {
    final resolver = await resolverFor(const [
      PackageFixture(
        id: 'a',
        dependencies: [
          {'id': 'b', 'version': '1.0.0'},
        ],
      ),
      PackageFixture(
        id: 'b',
        dependencies: [
          {'id': 'a', 'version': '1.0.0'},
        ],
      ),
    ]);
    await expectLater(
      resolver.resolve(packageIds: ['a'], target: 'codex'),
      throwsA(isA<PackageException>()),
    );
  });

  test('rejects declared conflicts', () async {
    final resolver = await resolverFor(const [
      PackageFixture(id: 'a', conflicts: ['b']),
      PackageFixture(id: 'b'),
    ]);

    await expectLater(
      resolver.resolve(packageIds: ['a', 'b'], target: 'codex'),
      throwsA(isA<PackageException>()),
    );
  });

  test(
    'rejects incompatible dependency versions across requested packages',
    () async {
      final first = await createPackageSourceFixture(
        temporary,
        sourceId: 'first',
        packages: const [
          PackageFixture(id: 'base'),
          PackageFixture(
            id: 'app-one',
            dependencies: [
              {'id': 'base', 'version': '1.0.0'},
            ],
          ),
        ],
      );
      final second = await createPackageSourceFixture(
        temporary,
        sourceId: 'second',
        packages: const [
          PackageFixture(id: 'base', version: '2.0.0'),
          PackageFixture(
            id: 'app-two',
            dependencies: [
              {'id': 'base', 'version': '2.0.0'},
            ],
          ),
        ],
      );
      await registry.addLocal('first', first.path);
      await registry.addLocal('second', second.path);
      final resolver = PackageResolver(PackageCatalog(registry: registry));

      await expectLater(
        resolver.resolve(packageIds: ['app-one', 'app-two'], target: 'codex'),
        throwsA(isA<PackageException>()),
      );
    },
  );

  test(
    'rejects a package that does not support the requested target',
    () async {
      final resolver = await resolverFor(const [
        PackageFixture(id: 'android-core', targets: ['claude-code']),
      ]);

      await expectLater(
        resolver.resolve(packageIds: ['android-core'], target: 'codex'),
        throwsA(isA<PackageException>()),
      );
    },
  );

  test('restricts resolution to the selected source', () async {
    final first = await createPackageSourceFixture(
      temporary,
      sourceId: 'first-source',
      packages: const [PackageFixture(id: 'android-core')],
    );
    final second = await createPackageSourceFixture(
      temporary,
      sourceId: 'second-source',
      packages: const [
        PackageFixture(id: 'android-core', version: '2.0.0'),
      ],
    );
    await registry.addLocal('first', first.path);
    await registry.addLocal('second', second.path);
    final resolver = PackageResolver(PackageCatalog(registry: registry));

    final resolution = await resolver.resolve(
      packageIds: ['android-core'],
      target: 'codex',
      sourceName: 'second',
    );

    expect(resolution.packages.single.sourceName, 'second');
    expect(resolution.packages.single.manifest.version, '2.0.0');
  });
}
