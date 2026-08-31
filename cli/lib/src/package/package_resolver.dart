import 'package:alfredo_cli/src/package/package_catalog.dart';
import 'package:alfredo_cli/src/package/package_models.dart';

/// Resolves exact package dependencies in a deterministic, fail-closed order.
class PackageResolver {
  /// Creates a resolver backed by [catalog].
  const PackageResolver(this.catalog);

  /// Package metadata provider.
  final PackageCatalog catalog;

  /// Resolves [packageIds] for [target], with dependencies before dependents.
  Future<PackageResolution> resolve({
    required Iterable<String> packageIds,
    required String target,
    String? sourceName,
  }) async {
    final candidates = (await catalog.discover())
        .where(
          (candidate) =>
              sourceName == null || candidate.sourceName == sourceName,
        )
        .toList();
    final byIdentity = <String, List<PackageCandidate>>{};
    for (final candidate in candidates) {
      final identity = '${candidate.manifest.id}@${candidate.manifest.version}';
      (byIdentity[identity] ??= []).add(candidate);
    }
    for (final values in byIdentity.values) {
      values.sort((left, right) => left.sourceName.compareTo(right.sourceName));
    }

    final selected = <String, PackageCandidate>{};
    final resolving = <String>[];
    final resolved = <PackageCandidate>[];

    Future<void> visit(String id, [String? version]) async {
      final matching = <PackageCandidate>[];
      for (final entry in byIdentity.entries) {
        if (entry.key.startsWith('$id@') &&
            (version == null || entry.key == '$id@$version')) {
          matching.addAll(entry.value);
        }
      }
      matching.sort((left, right) {
        final versionOrder = left.manifest.version.compareTo(
          right.manifest.version,
        );
        return versionOrder == 0
            ? left.sourceName.compareTo(right.sourceName)
            : versionOrder;
      });
      if (matching.isEmpty) {
        final requested = version == null ? id : '$id@$version';
        throw PackageException('Package is not available: $requested');
      }
      final candidate = matching.first;
      if (!candidate.manifest.targets.contains(target)) {
        throw PackageException(
          'Package ${candidate.manifest.id} does not support target $target.',
        );
      }
      final existing = selected[id];
      if (existing != null) {
        if (existing.manifest.version != candidate.manifest.version) {
          throw PackageException(
            'Version conflict for $id: ${existing.manifest.version} and '
            '${candidate.manifest.version}.',
          );
        }
        return;
      }
      if (resolving.contains(id)) {
        final start = resolving.indexOf(id);
        final cycle = [...resolving.sublist(start), id];
        throw PackageException('Dependency cycle: ${cycle.join(' -> ')}');
      }

      resolving.add(id);
      final dependencies = [...candidate.manifest.dependencies]
        ..sort((left, right) {
          final idOrder = left.id.compareTo(right.id);
          return idOrder == 0 ? left.version.compareTo(right.version) : idOrder;
        });
      for (final dependency in dependencies) {
        await visit(dependency.id, dependency.version);
      }
      _assertNoConflict(candidate, selected.values);
      selected[id] = candidate;
      resolving.removeLast();
      resolved.add(candidate);
    }

    final requested = packageIds.toSet().toList()..sort();
    if (requested.isEmpty) {
      throw const PackageException('At least one package must be requested.');
    }
    for (final id in requested) {
      await visit(id);
    }
    return PackageResolution(
      target: target,
      packages: List.unmodifiable(resolved),
    );
  }

  static void _assertNoConflict(
    PackageCandidate candidate,
    Iterable<PackageCandidate> selected,
  ) {
    for (final existing in selected) {
      if (candidate.manifest.conflicts.contains(existing.manifest.id) ||
          existing.manifest.conflicts.contains(candidate.manifest.id)) {
        throw PackageException(
          'Package conflict: ${candidate.manifest.id} and '
          '${existing.manifest.id}.',
        );
      }
    }
  }
}
