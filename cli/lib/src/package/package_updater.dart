import 'package:alfredo_cli/src/package/installation_adapters.dart';
import 'package:alfredo_cli/src/package/installation_state.dart';
import 'package:alfredo_cli/src/package/package_catalog.dart';
import 'package:alfredo_cli/src/package/package_installer.dart';
import 'package:alfredo_cli/src/package/package_models.dart';
import 'package:alfredo_cli/src/package/package_resolver.dart';
import 'package:alfredo_cli/src/source/source_models.dart';
import 'package:alfredo_cli/src/source/source_registry.dart';

/// The outcome for a single installed package during an update.
enum PackageUpdateStatus {
  /// The installed content already matches the source.
  upToDate,

  /// The package was reinstalled with newer content.
  updated,

  /// The package is no longer offered by its source.
  unavailable,

  /// A locally modified managed file blocked the reinstall.
  skippedModified,
}

/// What happened to one referenced source during an update.
class SourceUpdate {
  /// Creates a source update row.
  const SourceUpdate({
    required this.name,
    required this.kind,
    this.previousRevision,
    this.newRevision,
    this.detail,
  });

  /// Registered source name.
  final String name;

  /// The change that was applied.
  final SourceRefreshKind kind;

  /// Resolved revision before the refresh, when applicable.
  final String? previousRevision;

  /// Resolved revision after the refresh, when applicable.
  final String? newRevision;

  /// Optional human-readable note.
  final String? detail;
}

/// What happened to one installed package during an update.
class PackageUpdate {
  /// Creates a package update row.
  const PackageUpdate({
    required this.target,
    required this.scope,
    required this.packageId,
    required this.status,
    this.fromVersion,
    this.toVersion,
    this.detail,
  });

  /// Agent target identifier.
  final String target;

  /// Installation scope.
  final InstallationScope scope;

  /// Package identifier.
  final String packageId;

  /// Result for this package.
  final PackageUpdateStatus status;

  /// Installed version before the update.
  final String? fromVersion;

  /// Version after the update.
  final String? toVersion;

  /// Optional human-readable note.
  final String? detail;
}

/// The full result of an [PackageUpdater.run] invocation.
class UpdateReport {
  /// Creates an update report.
  const UpdateReport({required this.sources, required this.packages});

  /// One row per referenced source.
  final List<SourceUpdate> sources;

  /// One row per installed package considered.
  final List<PackageUpdate> packages;

  /// Whether anything changed (a source moved or a package was updated).
  bool get changed =>
      sources.any((s) => s.kind == SourceRefreshKind.updated) ||
      packages.any((p) => p.status == PackageUpdateStatus.updated);

  /// Count of packages that were reinstalled with newer content.
  int get updatedPackages =>
      packages.where((p) => p.status == PackageUpdateStatus.updated).length;

  /// Count of sources advanced to a newer revision.
  int get refreshedSources =>
      sources.where((s) => s.kind == SourceRefreshKind.updated).length;
}

/// Re-resolves installed packages from their sources and reinstalls changes.
class PackageUpdater {
  /// Creates a package updater.
  const PackageUpdater({
    required this.registry,
    required this.catalog,
    required this.resolver,
    required this.installer,
    required this.roots,
  });

  /// Registered source provider.
  final SourceRegistry registry;

  /// Package metadata provider.
  final PackageCatalog catalog;

  /// Deterministic dependency resolver.
  final PackageResolver resolver;

  /// Transactional installer.
  final PackageInstaller installer;

  /// Installation roots for every target and scope.
  final AgentTargetRoots roots;

  /// Updates installed packages, optionally filtered and without writing.
  Future<UpdateReport> run({
    Set<String>? targets,
    Set<InstallationScope>? scopes,
    Set<String>? packageIds,
    bool dryRun = false,
    bool refreshSources = true,
  }) async {
    final scopeSet =
        scopes ??
        {
          InstallationScope.user,
          InstallationScope.project,
        };
    final installations = <_Installation>[];
    for (final adapter in TargetAdapters.all) {
      if (targets != null && !targets.contains(adapter.id)) continue;
      for (final scope in scopeSet) {
        final file = adapter.lockfile(roots, scope);
        if (!file.existsSync()) continue;
        final lockfile = await PackageLockfileStore(file).read();
        if (lockfile.packages.isEmpty) continue;
        installations.add(_Installation(adapter, scope, lockfile));
      }
    }

    final sourceUpdates = <SourceUpdate>[];
    final referenced = <String>{
      for (final installation in installations)
        for (final package in installation.lockfile.packages) package.source,
    };
    for (final name in referenced.toList()..sort()) {
      sourceUpdates.add(await _refreshSource(name, refreshSources, dryRun));
    }

    final packageUpdates = <PackageUpdate>[];
    if (installations.isNotEmpty) {
      final available = <String>{
        for (final candidate in await catalog.discover()) candidate.manifest.id,
      };
      for (final installation in installations) {
        packageUpdates.addAll(
          await _updateInstallation(
            installation,
            available,
            packageIds,
            dryRun: dryRun,
          ),
        );
      }
    }

    return UpdateReport(sources: sourceUpdates, packages: packageUpdates);
  }

  Future<SourceUpdate> _refreshSource(
    String name,
    bool refreshSources,
    bool dryRun,
  ) async {
    if (!refreshSources) {
      return SourceUpdate(
        name: name,
        kind: SourceRefreshKind.unchanged,
        detail: 'source refresh skipped (--no-refresh-sources)',
      );
    }
    if (dryRun) {
      return SourceUpdate(
        name: name,
        kind: SourceRefreshKind.unchanged,
        detail: 'run without --dry-run to pull newer revisions',
      );
    }
    final refresh = await registry.refresh(name);
    return SourceUpdate(
      name: name,
      kind: refresh.kind,
      previousRevision: refresh.previousRevision,
      newRevision: refresh.newRevision,
    );
  }

  Future<List<PackageUpdate>> _updateInstallation(
    _Installation installation,
    Set<String> available,
    Set<String>? packageIds, {
    required bool dryRun,
  }) async {
    final adapter = installation.adapter;
    final scope = installation.scope;
    final locked = {
      for (final package in installation.lockfile.packages) package.id: package,
    };
    final requested = locked.keys
        .where((id) => packageIds == null || packageIds.contains(id))
        .toList();
    if (requested.isEmpty) return const [];

    final rows = <PackageUpdate>[];
    final resolvable = <String>[];
    for (final id in requested) {
      if (available.contains(id)) {
        resolvable.add(id);
      } else {
        rows.add(
          PackageUpdate(
            target: adapter.id,
            scope: scope,
            packageId: id,
            status: PackageUpdateStatus.unavailable,
            fromVersion: locked[id]!.version,
            detail: 'removed from source ${locked[id]!.source}',
          ),
        );
      }
    }
    if (resolvable.isEmpty) return rows;

    PackageResolution resolution;
    try {
      resolution = await resolver.resolve(
        packageIds: resolvable,
        target: adapter.id,
      );
    } on PackageException catch (error) {
      for (final id in resolvable) {
        rows.add(
          PackageUpdate(
            target: adapter.id,
            scope: scope,
            packageId: id,
            status: PackageUpdateStatus.unavailable,
            fromVersion: locked[id]!.version,
            detail: error.message,
          ),
        );
      }
      return rows;
    }

    final resolved = {
      for (final package in PackageLockfile.fromResolution(resolution).packages)
        package.id: package,
    };
    final blocked = await _modifiedPackageIds(adapter.id, scope);
    final changedIds = <String>[];
    for (final id in resolvable) {
      final before = locked[id]!;
      final after = resolved[id];
      if (after == null) continue;
      final isChanged =
          after.version != before.version || after.digest != before.digest;
      if (!isChanged) {
        rows.add(
          _row(adapter.id, scope, id, PackageUpdateStatus.upToDate, before),
        );
      } else if (blocked.contains(id)) {
        rows.add(
          PackageUpdate(
            target: adapter.id,
            scope: scope,
            packageId: id,
            status: PackageUpdateStatus.skippedModified,
            fromVersion: before.version,
            toVersion: after.version,
            detail: 'locally modified managed file',
          ),
        );
      } else {
        changedIds.add(id);
        rows.add(
          PackageUpdate(
            target: adapter.id,
            scope: scope,
            packageId: id,
            status: PackageUpdateStatus.updated,
            fromVersion: before.version,
            toVersion: after.version,
          ),
        );
      }
    }

    if (dryRun || changedIds.isEmpty) return rows;

    try {
      final applied = await resolver.resolve(
        packageIds: changedIds,
        target: adapter.id,
      );
      await installer.install(
        resolution: applied,
        roots: roots,
        scope: scope,
      );
    } on PackageException catch (error) {
      if (!error.message.contains('modified managed file')) rethrow;
      for (var index = 0; index < rows.length; index++) {
        final row = rows[index];
        if (row.status != PackageUpdateStatus.updated) continue;
        rows[index] = PackageUpdate(
          target: row.target,
          scope: row.scope,
          packageId: row.packageId,
          status: PackageUpdateStatus.skippedModified,
          fromVersion: row.fromVersion,
          toVersion: row.toVersion,
          detail: error.message,
        );
      }
    }
    return rows;
  }

  Future<Set<String>> _modifiedPackageIds(
    String target,
    InstallationScope scope,
  ) async {
    final statuses = await installer.status(
      target: target,
      roots: roots,
      scope: scope,
    );
    return {
      for (final status in statuses)
        if (status.condition == ManagedFileCondition.modified)
          status.file.packageId,
    };
  }

  static PackageUpdate _row(
    String target,
    InstallationScope scope,
    String id,
    PackageUpdateStatus status,
    LockedPackage locked,
  ) => PackageUpdate(
    target: target,
    scope: scope,
    packageId: id,
    status: status,
    fromVersion: locked.version,
    toVersion: locked.version,
  );
}

class _Installation {
  const _Installation(this.adapter, this.scope, this.lockfile);

  final TargetAdapter adapter;
  final InstallationScope scope;
  final PackageLockfile lockfile;
}
