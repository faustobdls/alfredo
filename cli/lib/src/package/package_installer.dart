import 'dart:io';

import 'package:alfredo_cli/src/package/installation_adapters.dart';
import 'package:alfredo_cli/src/package/installation_state.dart';
import 'package:alfredo_cli/src/package/package_manifest_loader.dart';
import 'package:alfredo_cli/src/package/package_models.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// What to do with a locally modified managed file during an install.
enum ManagedFileConflict {
  /// Replace the modified file with the package version.
  overwrite,

  /// Keep the modified file and leave its ownership record unchanged.
  skip,
}

/// Resolves a locally modified managed file at `path`. Callers that want the
/// historical hard failure pass no resolver at all.
typedef ManagedFileConflictResolver =
    Future<ManagedFileConflict> Function(String path);

/// Installs resolved packages with staging, collision checks, and rollback.
class PackageInstaller {
  /// Creates a package installer.
  const PackageInstaller({this.packageLoader = const PackageManifestLoader()});

  /// Reads source files declared by package manifests.
  final PackageManifestLoader packageLoader;

  /// Stages and installs [resolution] into an adapter root.
  ///
  /// When [onModifiedFile] is supplied it decides, per path, whether a locally
  /// modified managed file is overwritten or kept. With no resolver a modified
  /// managed file aborts the transaction, as before.
  Future<InstallationResult> install({
    required PackageResolution resolution,
    required AgentTargetRoots roots,
    required InstallationScope scope,
    InstalledStateStore? stateStore,
    PackageLockfileStore? lockfileStore,
    ManagedFileConflictResolver? onModifiedFile,
  }) async {
    final adapter = TargetAdapters.forId(resolution.target);
    final safeRoots = await _safeRoots(roots, scope, create: true);
    final scopeRoot = _scopeRoot(safeRoots, scope);
    final targetRoot = adapter.targetRoot(safeRoots, scope);
    final store =
        stateStore ?? InstalledStateStore(adapter.stateFile(safeRoots, scope));
    final locks =
        lockfileStore ??
        PackageLockfileStore(adapter.lockfile(safeRoots, scope));
    _assertContainedPath(scopeRoot, targetRoot.path);
    _assertContainedPath(scopeRoot, store.file.path);
    _assertContainedPath(scopeRoot, locks.file.path);
    await targetRoot.create(recursive: true);
    _assertContainedPath(scopeRoot, targetRoot.path);
    final currentState = await store.read(adapter.id);
    final plan = await _buildPlan(resolution, adapter);
    final replacingPackageIds = resolution.packages
        .map((package) => package.manifest.id)
        .toSet();
    final validation = await _validatePlan(
      plan,
      currentState,
      targetRoot,
      replacingPackageIds,
      onModifiedFile,
    );
    final removals = validation.removals;
    final skipped = validation.skipped;
    final preserved = validation.preserved;
    final untouched = {...skipped, ...preserved};
    final effectivePlan = untouched.isEmpty
        ? plan
        : [
            for (final file in plan)
              if (!untouched.contains(file.path)) file,
          ];

    final stage = await Directory(
      p.join(
        targetRoot.path,
        '.alfredo-stage-$pid-${DateTime.now().microsecondsSinceEpoch}',
      ),
    ).create();
    try {
      await _stage(effectivePlan, stage);
      final nextState = _nextState(
        currentState,
        effectivePlan,
        adapter.id,
        replacingPackageIds,
        skipped,
      );
      final lockfile = PackageLockfile.fromResolution(resolution);
      final previousLock = await _FileSnapshot.capture(locks.file);
      await locks.write(lockfile);
      try {
        await _commit(
          plan: effectivePlan,
          removals: removals,
          stage: stage,
          targetRoot: targetRoot,
          store: store,
          nextState: nextState,
        );
      } on Object {
        await previousLock.restore(locks.file);
        rethrow;
      }
      return InstallationResult(
        lockfile: lockfile,
        installedFiles: [
          for (final file in effectivePlan)
            File(p.join(targetRoot.path, file.path)),
        ],
        skippedFiles: skipped.toList()..sort(),
        preservedFiles: preserved.toList()..sort(),
      );
    } finally {
      if (stage.existsSync()) await stage.delete(recursive: true);
    }
  }

  /// Returns the current modified/missing state of files owned by Alfredo.
  Future<List<ManagedFileStatus>> status({
    required String target,
    required AgentTargetRoots roots,
    required InstallationScope scope,
    InstalledStateStore? stateStore,
  }) async {
    final adapter = TargetAdapters.forId(target);
    final safeRoots = await _safeRoots(roots, scope);
    final scopeRoot = _scopeRoot(safeRoots, scope);
    final root = adapter.targetRoot(safeRoots, scope);
    final store =
        stateStore ?? InstalledStateStore(adapter.stateFile(safeRoots, scope));
    _assertContainedPath(scopeRoot, root.path);
    _assertContainedPath(scopeRoot, store.file.path);
    final state = await store.read(adapter.id);
    final results = <ManagedFileStatus>[];
    for (final record in state.files) {
      _assertContainedPath(root, p.join(root.path, record.path));
      final destination = File(
        p.joinAll([root.path, ...p.posix.split(record.path)]),
      );
      final condition = !destination.existsSync()
          ? ManagedFileCondition.missing
          : await _digestFile(destination) == record.digest
          ? ManagedFileCondition.unchanged
          : ManagedFileCondition.modified;
      results.add(ManagedFileStatus(file: record, condition: condition));
    }
    return List.unmodifiable(results);
  }

  /// Alias for callers that expose this information as an installation diff.
  Future<List<ManagedFileStatus>> diff({
    required String target,
    required AgentTargetRoots roots,
    required InstallationScope scope,
    InstalledStateStore? stateStore,
  }) => status(
    target: target,
    roots: roots,
    scope: scope,
    stateStore: stateStore,
  );

  /// Removes unchanged files owned by selected packages, never arbitrary files.
  Future<List<ManagedFileStatus>> uninstall({
    required String target,
    required AgentTargetRoots roots,
    required InstallationScope scope,
    Iterable<String>? packageIds,
    InstalledStateStore? stateStore,
  }) async {
    final adapter = TargetAdapters.forId(target);
    final safeRoots = await _safeRoots(roots, scope);
    final scopeRoot = _scopeRoot(safeRoots, scope);
    final root = adapter.targetRoot(safeRoots, scope);
    final store =
        stateStore ?? InstalledStateStore(adapter.stateFile(safeRoots, scope));
    _assertContainedPath(scopeRoot, root.path);
    _assertContainedPath(scopeRoot, store.file.path);
    final requested = packageIds?.toSet();
    final statuses = await status(
      target: target,
      roots: roots,
      scope: scope,
      stateStore: store,
    );
    final remaining = <ManagedFile>[];
    for (final entry in statuses) {
      final selected =
          requested == null || requested.contains(entry.file.packageId);
      if (!selected ||
          entry.file.mode == ManagedFileMode.seed ||
          entry.condition == ManagedFileCondition.modified) {
        remaining.add(entry.file);
        continue;
      }
      if (entry.condition == ManagedFileCondition.unchanged) {
        _assertContainedPath(root, p.join(root.path, entry.file.path));
        final file = File(
          p.joinAll([root.path, ...p.posix.split(entry.file.path)]),
        );
        await file.delete();
      }
    }
    await store.write(InstalledState(target: adapter.id, files: remaining));
    return statuses;
  }

  Future<List<_PlannedFile>> _buildPlan(
    PackageResolution resolution,
    TargetAdapter adapter,
  ) async {
    final plan = <_PlannedFile>[];
    for (final candidate in resolution.packages) {
      final sourceRoot = await Directory(
        candidate.sourceRoot,
      ).resolveSymbolicLinks();
      for (final content in candidate.manifest.contents.entries) {
        final oneKindManifest = PackageManifest(
          id: candidate.manifest.id,
          name: candidate.manifest.name,
          version: candidate.manifest.version,
          description: candidate.manifest.description,
          targets: candidate.manifest.targets,
          contents: {content.key: content.value},
          dependencies: const [],
          conflicts: const {},
        );
        final files = await packageLoader.filesForContents(
          sourceRoot,
          oneKindManifest,
        );
        for (final source in files) {
          final sourcePath = p.posix.joinAll(
            p.split(p.relative(source.path, from: sourceRoot)),
          );
          final destination = sourcePath;
          final bytes = await source.readAsBytes();
          plan.add(
            _PlannedFile(
              path: destination,
              bytes: bytes,
              packageId: candidate.manifest.id,
              mode: content.key == 'personas'
                  ? ManagedFileMode.seed
                  : ManagedFileMode.managed,
            ),
          );
        }
      }
    }
    plan.sort((left, right) => left.path.compareTo(right.path));
    return plan;
  }

  static Future<
    ({List<ManagedFile> removals, Set<String> skipped, Set<String> preserved})
  >
  _validatePlan(
    List<_PlannedFile> plan,
    InstalledState state,
    Directory targetRoot,
    Set<String> replacingPackageIds,
    ManagedFileConflictResolver? onModifiedFile,
  ) async {
    final planned = <String>{};
    final skipped = <String>{};
    final preserved = <String>{};
    final managed = {for (final file in state.files) file.path: file};
    for (final file in plan) {
      _assertContainedPath(targetRoot, p.join(targetRoot.path, file.path));
      if (!planned.add(file.path)) {
        throw PackageException('Installation collision at ${file.path}.');
      }
      if (!_safeRelativePath(file.path)) {
        throw PackageException('Unsafe installation destination: ${file.path}');
      }
      final destination = File(
        p.joinAll([targetRoot.path, ...p.posix.split(file.path)]),
      );
      if (destination.existsSync()) {
        if (file.mode == ManagedFileMode.seed) {
          preserved.add(file.path);
          continue;
        }
        final record = managed[file.path];
        if (record == null) {
          throw PackageException(
            'Refusing to overwrite unmanaged file: ${file.path}',
          );
        }
        if (record.packageId != file.packageId) {
          throw PackageException('Installation collision at ${file.path}.');
        }
        if (await _digestFile(destination) != record.digest) {
          if (onModifiedFile == null) {
            throw PackageException(
              'Refusing to overwrite modified managed file: ${file.path}',
            );
          }
          if (await onModifiedFile(file.path) == ManagedFileConflict.skip) {
            skipped.add(file.path);
          }
        }
      } else if (Directory(destination.path).existsSync()) {
        throw PackageException('Installation collision at ${file.path}.');
      }
    }
    final removals = <ManagedFile>[];
    for (final file in state.files) {
      if (file.mode == ManagedFileMode.seed) {
        continue;
      }
      if (!replacingPackageIds.contains(file.packageId) ||
          planned.contains(file.path)) {
        continue;
      }
      final destination = File(
        p.joinAll([targetRoot.path, ...p.posix.split(file.path)]),
      );
      if (destination.existsSync() &&
          await _digestFile(destination) != file.digest) {
        throw PackageException(
          'Refusing to remove modified managed file: ${file.path}',
        );
      }
      removals.add(file);
    }
    return (removals: removals, skipped: skipped, preserved: preserved);
  }

  static InstalledState _nextState(
    InstalledState current,
    List<_PlannedFile> plan,
    String target,
    Set<String> replacingPackageIds,
    Set<String> skipped,
  ) {
    final planned = {for (final file in plan) file.path};
    final files = <ManagedFile>[
      // Keep records from packages we are not replacing, plus the original
      // record of any file we skipped so it stays managed and still reports as
      // modified against its installed digest.
      for (final file in current.files)
        if (!replacingPackageIds.contains(file.packageId) ||
            (file.mode == ManagedFileMode.seed &&
                !planned.contains(file.path)) ||
            skipped.contains(file.path))
          file,
      for (final file in plan)
        ManagedFile(
          path: file.path,
          digest: file.digest,
          packageId: file.packageId,
          mode: file.mode,
        ),
    ]..sort((left, right) => left.path.compareTo(right.path));
    return InstalledState(target: target, files: files);
  }

  static Future<void> _stage(List<_PlannedFile> plan, Directory stage) async {
    for (final item in plan) {
      final file = File(p.joinAll([stage.path, ...p.posix.split(item.path)]));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(item.bytes, flush: true);
      if (await _digestFile(file) != item.digest) {
        throw PackageException('Staging digest mismatch: ${item.path}');
      }
    }
  }

  static Future<void> _commit({
    required List<_PlannedFile> plan,
    required List<ManagedFile> removals,
    required Directory stage,
    required Directory targetRoot,
    required InstalledStateStore store,
    required InstalledState nextState,
  }) async {
    final backups = <String, File>{};
    final written = <File>[];
    try {
      for (final path in [
        ...plan.map((item) => item.path),
        ...removals.map((item) => item.path),
      ]) {
        _assertContainedPath(targetRoot, p.join(targetRoot.path, path));
        final destination = File(
          p.joinAll([targetRoot.path, ...p.posix.split(path)]),
        );
        if (destination.existsSync()) {
          final backup = File(p.join(stage.path, 'backups', path));
          await backup.parent.create(recursive: true);
          await destination.rename(backup.path);
          backups[path] = backup;
        }
      }
      for (final item in plan) {
        _assertContainedPath(targetRoot, p.join(targetRoot.path, item.path));
        final source = File(
          p.joinAll([stage.path, ...p.posix.split(item.path)]),
        );
        final destination = File(
          p.joinAll([targetRoot.path, ...p.posix.split(item.path)]),
        );
        await destination.parent.create(recursive: true);
        await source.rename(destination.path);
        written.add(destination);
      }
      await store.write(nextState);
    } on Object {
      for (final file in written.reversed) {
        if (file.existsSync()) await file.delete();
      }
      for (final entry in backups.entries) {
        final destination = File(
          p.joinAll([targetRoot.path, ...p.posix.split(entry.key)]),
        );
        if (!destination.existsSync()) {
          await entry.value.rename(destination.path);
        }
      }
      rethrow;
    }
  }

  static Future<String> _digestFile(File file) async =>
      sha256.convert(await file.readAsBytes()).toString();

  static Future<AgentTargetRoots> _safeRoots(
    AgentTargetRoots roots,
    InstallationScope scope, {
    bool create = false,
  }) async {
    final requested = _scopeRoot(roots, scope);
    try {
      if (create) await requested.create(recursive: true);
      final safe = requested.existsSync()
          ? Directory(await requested.resolveSymbolicLinks())
          : Directory(p.normalize(p.absolute(requested.path)));
      return switch (scope) {
        InstallationScope.user => AgentTargetRoots(
          userRoot: safe,
          projectRoot: roots.projectRoot,
        ),
        InstallationScope.project => AgentTargetRoots(
          userRoot: roots.userRoot,
          projectRoot: safe,
        ),
      };
    } on FileSystemException catch (error) {
      throw PackageException(
        'Cannot access installation root: ${error.message}',
      );
    }
  }

  static Directory _scopeRoot(
    AgentTargetRoots roots,
    InstallationScope scope,
  ) => switch (scope) {
    InstallationScope.user => roots.userRoot,
    InstallationScope.project => roots.projectRoot,
  };

  static void _assertContainedPath(Directory root, String candidatePath) {
    final rootPath = p.normalize(p.absolute(root.path));
    final candidate = p.normalize(p.absolute(candidatePath));
    if (candidate != rootPath && !p.isWithin(rootPath, candidate)) {
      throw PackageException('Installation path escapes its root: $candidate');
    }
    var current = rootPath;
    final relative = p.relative(candidate, from: rootPath);
    if (relative == '.') return;
    for (final segment in p.split(relative)) {
      current = p.join(current, segment);
      if (FileSystemEntity.typeSync(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw PackageException(
          'Installation path contains a symbolic link: $current',
        );
      }
    }
  }

  static bool _safeRelativePath(String path) =>
      path.isNotEmpty &&
      !path.startsWith('/') &&
      !path.contains(r'\') &&
      !path.split('/').contains('..');
}

class _FileSnapshot {
  const _FileSnapshot._(this.bytes);

  final List<int>? bytes;

  static Future<_FileSnapshot> capture(File file) async =>
      _FileSnapshot._(file.existsSync() ? await file.readAsBytes() : null);

  Future<void> restore(File file) async {
    final previous = bytes;
    if (previous == null) {
      if (file.existsSync()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    final temporary = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.rollback',
    );
    try {
      await temporary.writeAsBytes(previous, flush: true);
      await temporary.rename(file.path);
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
  }
}

class _PlannedFile {
  const _PlannedFile({
    required this.path,
    required this.bytes,
    required this.packageId,
    this.mode = ManagedFileMode.managed,
  });

  final String path;
  final List<int> bytes;
  final String packageId;
  final ManagedFileMode mode;

  String get digest => sha256.convert(bytes).toString();
}
