import 'package:alfredo_cli/src/package/package_manifest_loader.dart';
import 'package:alfredo_cli/src/package/package_models.dart';
import 'package:alfredo_cli/src/source/source_manifest_loader.dart';
import 'package:alfredo_cli/src/source/source_registry.dart';
import 'package:path/path.dart' as p;

/// Discovers complete package metadata from all registered local sources.
class PackageCatalog {
  /// Creates a deterministic package catalog.
  PackageCatalog({
    required this.registry,
    this.sourceLoader = const SourceManifestLoader(),
    this.packageLoader = const PackageManifestLoader(),
  });

  /// Registered source provider.
  final SourceRegistry registry;

  /// Source catalog loader.
  final SourceManifestLoader sourceLoader;

  /// Package manifest and digest loader.
  final PackageManifestLoader packageLoader;

  /// Discovers every package in source-name and package-path order.
  Future<List<PackageCandidate>> discover() async {
    final candidates = <PackageCandidate>[];
    for (final registered in await registry.list()) {
      final source = await sourceLoader.load(registered.location);
      if (source.id != registered.sourceId) {
        throw PackageException(
          'Source identity changed from ${registered.sourceId} '
          'to ${source.id}.',
        );
      }
      for (final summary in source.packages) {
        final packageRoot = p.dirname(
          p.joinAll([source.root, ...p.posix.split(summary.path)]),
        );
        final manifest = await packageLoader.load(packageRoot);
        if (manifest.id != summary.id || manifest.version != summary.version) {
          throw PackageException(
            'Package summary differs from manifest: ${summary.path}',
          );
        }
        candidates.add(
          PackageCandidate(
            sourceName: registered.name,
            sourceRoot: source.root,
            packageRoot: packageRoot,
            manifest: manifest,
            digest: await packageLoader.digest(
              packageDirectory: packageRoot,
              contentRoot: source.root,
              manifest: manifest,
            ),
          ),
        );
      }
    }
    candidates.sort(_compareCandidates);
    return List.unmodifiable(candidates);
  }

  static int _compareCandidates(PackageCandidate left, PackageCandidate right) {
    final id = left.manifest.id.compareTo(right.manifest.id);
    if (id != 0) return id;
    final version = left.manifest.version.compareTo(right.manifest.version);
    if (version != 0) return version;
    return left.sourceName.compareTo(right.sourceName);
  }
}
