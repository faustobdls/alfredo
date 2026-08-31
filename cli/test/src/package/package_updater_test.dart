import 'dart:io';

import 'package:alfredo_cli/src/package/package.dart';
import 'package:alfredo_cli/src/source/source.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../helpers/package_fixture.dart';

void main() {
  late Directory temporary;
  late Directory source;
  late AgentTargetRoots roots;
  late SourceRegistry registry;
  late PackageUpdater updater;
  late File sourceSkill;
  late File installedSkill;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-updater-');
    roots = AgentTargetRoots(
      userRoot: Directory(p.join(temporary.path, 'user')),
      projectRoot: Directory(p.join(temporary.path, 'project')),
    );
    source = await createPackageSourceFixture(
      temporary,
      sourceId: 'catalog',
      packages: const [
        PackageFixture(id: 'android-core'),
        PackageFixture(
          id: 'extra-core',
          contents: {
            'skills': ['skills/extra/SKILL.md'],
          },
        ),
      ],
    );
    registry = SourceRegistry(
      file: File(p.join(temporary.path, 'config', 'sources.json')),
    );
    await registry.addLocal('local', source.path);

    final catalog = PackageCatalog(registry: registry);
    final resolver = PackageResolver(catalog);
    const installer = PackageInstaller();
    updater = PackageUpdater(
      registry: registry,
      catalog: catalog,
      resolver: resolver,
      installer: installer,
      roots: roots,
    );

    final resolution = await resolver.resolve(
      packageIds: const ['android-core'],
      target: 'codex',
    );
    await installer.install(
      resolution: resolution,
      roots: roots,
      scope: InstallationScope.user,
    );

    sourceSkill = File(
      p.join(source.path, 'skills', 'example', 'SKILL.md'),
    );
    installedSkill = File(
      p.join(temporary.path, 'user', '.codex', 'skills', 'example', 'SKILL.md'),
    );
  });

  tearDown(() async => temporary.delete(recursive: true));

  test('reinstalls a package when its source content changed', () async {
    await sourceSkill.writeAsString('android-core:UPDATED\n');

    final report = await updater.run();

    expect(report.changed, isTrue);
    expect(report.updatedPackages, 1);
    final row = report.packages.single;
    expect(row.packageId, 'android-core');
    expect(row.status, PackageUpdateStatus.updated);
    expect(await installedSkill.readAsString(), 'android-core:UPDATED\n');
  });

  test('is a no-op on the second run', () async {
    await sourceSkill.writeAsString('android-core:UPDATED\n');
    await updater.run();

    final report = await updater.run();

    expect(report.changed, isFalse);
    expect(report.packages.single.status, PackageUpdateStatus.upToDate);
  });

  test(
    'marks a package that vanished from its source as unavailable',
    () async {
      await Directory(
        p.join(source.path, 'packages', 'android-core'),
      ).delete(recursive: true);

      final report = await updater.run();

      expect(report.packages.single.status, PackageUpdateStatus.unavailable);
    },
  );

  test('skips a package with a locally modified managed file', () async {
    await installedSkill.writeAsString('HAND EDIT\n');
    await sourceSkill.writeAsString('android-core:UPDATED\n');

    final report = await updater.run();

    expect(report.packages.single.status, PackageUpdateStatus.skippedModified);
    expect(await installedSkill.readAsString(), 'HAND EDIT\n');
  });

  test('dry run reports changes without writing them', () async {
    await sourceSkill.writeAsString('android-core:UPDATED\n');

    final report = await updater.run(dryRun: true);

    expect(report.packages.single.status, PackageUpdateStatus.updated);
    expect(report.sources.single.kind, SourceRefreshKind.unchanged);
    expect(
      await installedSkill.readAsString(),
      'android-core:skills/example/SKILL.md\n',
    );
  });
}
