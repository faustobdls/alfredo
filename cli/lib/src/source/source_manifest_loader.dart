import 'dart:io';

import 'package:alfredo_cli/src/source/catalog_contract_validator.dart';
import 'package:alfredo_cli/src/source/source_models.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Loads and validates a source without modifying it.
class SourceManifestLoader {
  /// Creates a source manifest loader.
  const SourceManifestLoader({
    this.validator = const CatalogContractValidator(),
  });

  /// Runtime validator mirroring the published v1 JSON schemas.
  final CatalogContractValidator validator;

  /// Loads an Alfredo catalog rooted at [directoryPath].
  Future<SourceCatalog> load(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      throw SourceException('Source directory does not exist: $directoryPath');
    }

    final root = await directory.resolveSymbolicLinks();
    final manifest = File(p.join(root, 'alfredo-source.yaml'));
    if (!manifest.existsSync()) {
      throw const SourceException(
        'Source is missing alfredo-source.yaml.',
      );
    }

    final source = _parseYamlMap(
      await manifest.readAsString(),
      context: 'source manifest',
    );
    validator.validateLocalSource(source);
    final id = source['id']! as String;
    final name = source['name']! as String;
    final packagesPath = validator.requireRelativePath(
      source['packages_path'],
      field: 'packages_path',
      allowDot: true,
    );
    final packagesDirectory = Directory(
      p.joinAll([root, ...p.posix.split(packagesPath)]),
    );
    if (!packagesDirectory.existsSync()) {
      throw SourceException(
        'Packages directory does not exist: $packagesPath',
      );
    }
    final resolvedPackagesDirectory = await packagesDirectory
        .resolveSymbolicLinks();
    if (resolvedPackagesDirectory != root &&
        !p.isWithin(root, resolvedPackagesDirectory)) {
      throw SourceException(
        'Packages directory escapes the source: $packagesPath',
      );
    }

    final packageDirectories = await packagesDirectory
        .list()
        .where((entity) => entity is Directory)
        .cast<Directory>()
        .toList();
    packageDirectories.sort((left, right) => left.path.compareTo(right.path));
    final seen = <String>{};
    final packages = <SourcePackage>[];

    for (final packageDirectory in packageDirectories) {
      final packageFile = File(p.join(packageDirectory.path, 'package.yaml'));
      final relativePath = p.posix.joinAll(
        p.split(p.relative(packageFile.path, from: root)),
      );
      if (!packageFile.existsSync()) {
        throw SourceException(
          'Package directory is missing its manifest: $relativePath',
        );
      }
      final resolvedPackage = await packageFile.resolveSymbolicLinks();
      if (!p.isWithin(root, resolvedPackage)) {
        throw SourceException('Package path escapes the source: $relativePath');
      }
      final package = await _loadPackage(packageFile, relativePath);
      if (!seen.add(package.id)) {
        throw SourceException('Duplicate package id: ${package.id}');
      }
      packages.add(package);
    }

    return SourceCatalog(
      id: id,
      name: name,
      root: root,
      packages: List.unmodifiable(packages),
    );
  }

  Future<SourcePackage> _loadPackage(
    File file,
    String relativePath,
  ) async {
    final package = _parseYamlMap(
      await file.readAsString(),
      context: 'package manifest $relativePath',
    );
    validator.validatePackage(package);
    final id = package['id']! as String;
    final version = package['version']! as String;
    return SourcePackage(
      id: id,
      path: relativePath,
      version: version,
      description: package['description']! as String,
    );
  }

  static Map<String, Object?> _asMap(Object? value, String message) {
    if (value is! Map) throw SourceException(message);
    return value.map((key, item) => MapEntry('$key', _plainValue(item)));
  }

  static Map<String, Object?> _parseYamlMap(
    String contents, {
    required String context,
  }) {
    try {
      return _asMap(loadYaml(contents), '$context must be a YAML object.');
    } on FormatException catch (error) {
      throw SourceException('Cannot parse $context: ${error.message}');
    }
  }

  static Object? _plainValue(Object? value) {
    if (value is YamlMap) {
      return value.map<String, Object?>(
        (key, item) => MapEntry('$key', _plainValue(item)),
      );
    }
    if (value is Map) {
      return value.map<String, Object?>(
        (key, item) => MapEntry('$key', _plainValue(item)),
      );
    }
    if (value is YamlList) {
      return value.map<Object?>(_plainValue).toList(growable: false);
    }
    if (value is List) {
      return value.map<Object?>(_plainValue).toList(growable: false);
    }
    return value;
  }
}
