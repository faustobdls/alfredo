import 'dart:io';

import 'package:alfredo_cli/src/package/installation_adapters.dart';
import 'package:alfredo_cli/src/package/package_installer.dart';
import 'package:alfredo_cli/src/package/package_manifest_loader.dart';
import 'package:alfredo_cli/src/package/package_models.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../helpers/package_fixture.dart';

void main() {
  late Directory temporary;
  late AgentTargetRoots roots;
  late PackageResolution resolution;
  late PackageInstaller installer;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-installer-');
    roots = AgentTargetRoots(
      userRoot: Directory(p.join(temporary.path, 'user')),
      projectRoot: Directory(p.join(temporary.path, 'project')),
    );
    final source = await createPackageSourceFixture(
      temporary,
      sourceId: 'catalog',
      packages: const [
        PackageFixture(
          id: 'android-core',
          targets: ['codex', 'claude-code', 'cursor', 'antigravity', 'generic'],
        ),
      ],
    );
    const loader = PackageManifestLoader();
    final packageRoot = p.join(source.path, 'packages', 'android-core');
    final manifest = await loader.load(packageRoot);
    resolution = PackageResolution(
      target: 'codex',
      packages: [
        PackageCandidate(
          sourceName: 'local',
          sourceRoot: source.path,
          packageRoot: packageRoot,
          manifest: manifest,
          digest: await loader.digest(
            packageDirectory: packageRoot,
            contentRoot: source.path,
            manifest: manifest,
          ),
        ),
      ],
    );
    installer = const PackageInstaller();
  });

  tearDown(() async => temporary.delete(recursive: true));

  test('installs canonical source-root skills for every adapter', () async {
    for (final target in [
      'codex',
      'claude-code',
      'cursor',
      'antigravity',
      'generic',
    ]) {
      final targetResolution = PackageResolution(
        target: target,
        packages: resolution.packages,
      );
      await installer.install(
        resolution: targetResolution,
        roots: roots,
        scope: InstallationScope.user,
      );
      final adapter = TargetAdapters.forId(target);
      const sourcePath = 'skills/example/SKILL.md';
      final file = File(
        p.joinAll([
          adapter.targetRoot(roots, InstallationScope.user).path,
          ...p.posix.split(sourcePath),
        ]),
      );
      expect(file.existsSync(), isTrue, reason: target);
    }
  });

  test('preserves native Cursor skill directories and references', () async {
    final cursorResolution = PackageResolution(
      target: 'cursor',
      packages: resolution.packages,
    );
    await installer.install(
      resolution: cursorResolution,
      roots: roots,
      scope: InstallationScope.user,
    );

    expect(
      File(
        p.join(roots.userRoot.path, '.cursor', 'skills', 'example', 'SKILL.md'),
      ).existsSync(),
      isTrue,
    );
  });

  test(
    'rejects symbolic-link parents instead of writing outside target root',
    () async {
      final outside = await Directory(
        p.join(temporary.path, 'outside'),
      ).create();
      final codex = await Directory(
        p.join(roots.userRoot.path, '.codex'),
      ).create(recursive: true);
      await Link(p.join(codex.path, 'skills')).create(outside.path);

      await expectLater(
        installer.install(
          resolution: resolution,
          roots: roots,
          scope: InstallationScope.user,
        ),
        throwsA(
          isA<PackageException>().having(
            (error) => error.message,
            'message',
            contains('symbolic link'),
          ),
        ),
      );
      expect(await outside.list().isEmpty, isTrue);
    },
    skip: Platform.isWindows
        ? 'Creating symlinks requires elevated privileges on Windows.'
        : false,
  );

  test(
    'does not commit content or state when lockfile writing fails',
    () async {
      await roots.userRoot.create(recursive: true);
      await File(
        p.join(roots.userRoot.path, '.alfredo'),
      ).writeAsString('blocked');

      await expectLater(
        installer.install(
          resolution: resolution,
          roots: roots,
          scope: InstallationScope.user,
        ),
        throwsA(isA<PackageException>()),
      );
      expect(
        File(
          p.join(
            roots.userRoot.path,
            '.codex',
            'skills',
            'example',
            'SKILL.md',
          ),
        ).existsSync(),
        isFalse,
      );
      expect(
        TargetAdapters.codex
            .stateFile(roots, InstallationScope.user)
            .existsSync(),
        isFalse,
      );
    },
  );

  test('fails closed for an unmanaged collision', () async {
    final collision = File(
      p.join(roots.userRoot.path, '.codex', 'skills', 'example', 'SKILL.md'),
    );
    await collision.parent.create(recursive: true);
    await collision.writeAsString('user owned\n');

    await expectLater(
      installer.install(
        resolution: resolution,
        roots: roots,
        scope: InstallationScope.user,
      ),
      throwsA(isA<PackageException>()),
    );
    expect(await collision.readAsString(), 'user owned\n');
  });

  test(
    'reports modified files and never uninstalls their changed content',
    () async {
      await installer.install(
        resolution: resolution,
        roots: roots,
        scope: InstallationScope.user,
      );
      final installed = File(
        p.join(roots.userRoot.path, '.codex', 'skills', 'example', 'SKILL.md'),
      );
      await installed.writeAsString('changed by user\n');

      final statuses = await installer.diff(
        target: 'codex',
        roots: roots,
        scope: InstallationScope.user,
      );
      expect(statuses.single.condition, ManagedFileCondition.modified);
      await installer.uninstall(
        target: 'codex',
        roots: roots,
        scope: InstallationScope.user,
      );
      expect(await installed.readAsString(), 'changed by user\n');
    },
  );

  test('keeps a modified managed file when the resolver skips it', () async {
    await installer.install(
      resolution: resolution,
      roots: roots,
      scope: InstallationScope.user,
    );
    final installed = File(
      p.join(roots.userRoot.path, '.codex', 'skills', 'example', 'SKILL.md'),
    );
    await installed.writeAsString('changed by user\n');

    final result = await installer.install(
      resolution: resolution,
      roots: roots,
      scope: InstallationScope.user,
      onModifiedFile: (_) async => ManagedFileConflict.skip,
    );

    expect(result.skippedFiles, ['skills/example/SKILL.md']);
    expect(await installed.readAsString(), 'changed by user\n');

    final statuses = await installer.diff(
      target: 'codex',
      roots: roots,
      scope: InstallationScope.user,
    );
    expect(statuses.single.condition, ManagedFileCondition.modified);
  });

  test(
    'overwrites a modified managed file when the resolver allows it',
    () async {
      await installer.install(
        resolution: resolution,
        roots: roots,
        scope: InstallationScope.user,
      );
      final installed = File(
        p.join(roots.userRoot.path, '.codex', 'skills', 'example', 'SKILL.md'),
      );
      final pristine = await installed.readAsString();
      await installed.writeAsString('changed by user\n');

      final result = await installer.install(
        resolution: resolution,
        roots: roots,
        scope: InstallationScope.user,
        onModifiedFile: (_) async => ManagedFileConflict.overwrite,
      );

      expect(result.skippedFiles, isEmpty);
      expect(await installed.readAsString(), pristine);

      final statuses = await installer.diff(
        target: 'codex',
        roots: roots,
        scope: InstallationScope.user,
      );
      expect(statuses.single.condition, ManagedFileCondition.unchanged);
    },
  );

  test(
    'still fails closed on a modified managed file with no resolver',
    () async {
      await installer.install(
        resolution: resolution,
        roots: roots,
        scope: InstallationScope.user,
      );
      final installed = File(
        p.join(roots.userRoot.path, '.codex', 'skills', 'example', 'SKILL.md'),
      );
      await installed.writeAsString('changed by user\n');

      await expectLater(
        installer.install(
          resolution: resolution,
          roots: roots,
          scope: InstallationScope.user,
        ),
        throwsA(isA<PackageException>()),
      );
      expect(await installed.readAsString(), 'changed by user\n');
    },
  );

  test('reports files removed outside Alfredo as missing', () async {
    await installer.install(
      resolution: resolution,
      roots: roots,
      scope: InstallationScope.user,
    );
    final installed = File(
      p.join(roots.userRoot.path, '.codex', 'skills', 'example', 'SKILL.md'),
    );
    await installed.delete();

    final statuses = await installer.status(
      target: 'codex',
      roots: roots,
      scope: InstallationScope.user,
    );
    expect(statuses.single.condition, ManagedFileCondition.missing);
  });

  test('uninstalls only unchanged managed files', () async {
    await installer.install(
      resolution: resolution,
      roots: roots,
      scope: InstallationScope.user,
    );
    final unmanaged = File(p.join(roots.userRoot.path, '.codex', 'notes.txt'));
    await unmanaged.writeAsString('keep\n');

    await installer.uninstall(
      target: 'codex',
      roots: roots,
      scope: InstallationScope.user,
    );
    expect(
      File(
        p.join(roots.userRoot.path, '.codex', 'skills', 'example', 'SKILL.md'),
      ).existsSync(),
      isFalse,
    );
    expect(await unmanaged.readAsString(), 'keep\n');
  });

  test('seeds personas once and preserves them across reinstalls', () async {
    final source = await createPackageSourceFixture(
      temporary,
      sourceId: 'personas-source',
      packages: const [
        PackageFixture(
          id: 'personas-core',
          contents: {
            'personas': ['personas/alfredo.md', 'personas/user.md'],
          },
        ),
      ],
    );
    final targetResolution = await _resolutionFor(
      source,
      packageId: 'personas-core',
      target: 'generic',
    );

    await installer.install(
      resolution: targetResolution,
      roots: roots,
      scope: InstallationScope.project,
    );
    final userPersona = File(
      p.join(roots.projectRoot.path, '.alfredo', 'personas', 'user.md'),
    );
    await userPersona.writeAsString('local voice preference\n');

    final updatedSource = File(p.join(source.path, 'personas', 'user.md'));
    await updatedSource.writeAsString('upstream default changed\n');
    final updatedResolution = await _resolutionFor(
      source,
      packageId: 'personas-core',
      target: 'generic',
    );
    final result = await installer.install(
      resolution: updatedResolution,
      roots: roots,
      scope: InstallationScope.project,
    );

    expect(result.skippedFiles, isEmpty);
    expect(result.preservedFiles, ['personas/alfredo.md', 'personas/user.md']);
    expect(await userPersona.readAsString(), 'local voice preference\n');
  });

  test('does not uninstall persona seed files', () async {
    final source = await createPackageSourceFixture(
      temporary,
      sourceId: 'persona-uninstall-source',
      packages: const [
        PackageFixture(
          id: 'personas-core',
          contents: {
            'personas': ['personas/user.md'],
          },
        ),
      ],
    );
    final targetResolution = await _resolutionFor(
      source,
      packageId: 'personas-core',
      target: 'generic',
    );

    await installer.install(
      resolution: targetResolution,
      roots: roots,
      scope: InstallationScope.project,
    );
    final userPersona = File(
      p.join(roots.projectRoot.path, '.alfredo', 'personas', 'user.md'),
    );

    await installer.uninstall(
      target: 'generic',
      roots: roots,
      scope: InstallationScope.project,
      packageIds: const ['personas-core'],
    );

    expect(userPersona.existsSync(), isTrue);
  });
}

Future<PackageResolution> _resolutionFor(
  Directory source, {
  required String packageId,
  required String target,
}) async {
  const loader = PackageManifestLoader();
  final packageRoot = p.join(source.path, 'packages', packageId);
  final manifest = await loader.load(packageRoot);
  return PackageResolution(
    target: target,
    packages: [
      PackageCandidate(
        sourceName: 'local',
        sourceRoot: source.path,
        packageRoot: packageRoot,
        manifest: manifest,
        digest: await loader.digest(
          packageDirectory: packageRoot,
          contentRoot: source.path,
          manifest: manifest,
        ),
      ),
    ],
  );
}
