import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alfredo_cli/src/package/package_models.dart';
import 'package:alfredo_cli/src/source/catalog_contract_validator.dart';
import 'package:alfredo_cli/src/source/source_models.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Loads package manifests and calculates content digests without mutation.
class PackageManifestLoader {
  /// Creates a package manifest loader.
  const PackageManifestLoader({
    this.validator = const CatalogContractValidator(),
  });

  /// Shared source/package contract validator.
  final CatalogContractValidator validator;

  /// Loads a package manifest from [packageDirectory].
  Future<PackageManifest> load(String packageDirectory) async {
    final root = await _canonicalDirectory(packageDirectory);
    final file = File(p.join(root, 'package.yaml'));
    if (!file.existsSync()) {
      throw PackageException(
        'Package is missing package.yaml: $packageDirectory',
      );
    }
    final map = _parseYamlMap(await file.readAsString(), 'package manifest');
    try {
      validator.validatePackage(map);
    } on SourceException catch (error) {
      throw PackageException(error.message);
    }

    final contents = <String, List<String>>{};
    final rawContents = map['contents']! as Map<String, Object?>;
    for (final entry in rawContents.entries) {
      contents[entry.key] = List.unmodifiable(
        (entry.value! as List<Object?>).cast<String>(),
      );
    }
    final dependencies = <PackageDependency>[];
    for (final item
        in (map['dependencies'] ?? const <Object?>[]) as List<Object?>) {
      final dependency = item! as Map<String, Object?>;
      dependencies.add(
        PackageDependency(
          id: dependency['id']! as String,
          version: dependency['version']! as String,
        ),
      );
    }
    final conflicts = <String>{
      for (final item
          in (map['conflicts'] ?? const <Object?>[]) as List<Object?>)
        item! as String,
    };
    return PackageManifest(
      id: map['id']! as String,
      name: map['name']! as String,
      version: map['version']! as String,
      description: map['description']! as String,
      targets: Set.unmodifiable(
        (map['targets']! as List<Object?>).cast<String>(),
      ),
      contents: Map.unmodifiable(contents),
      dependencies: List.unmodifiable(dependencies),
      conflicts: Set.unmodifiable(conflicts),
    );
  }

  /// Calculates a stable digest of a package manifest and source-root content.
  Future<String> digest({
    required String packageDirectory,
    required String contentRoot,
    required PackageManifest manifest,
  }) async {
    final packageRoot = await _canonicalDirectory(packageDirectory);
    final root = await _canonicalDirectory(contentRoot);
    final files = <File>[File(p.join(packageRoot, 'package.yaml'))];
    for (final relativePath in manifest.contents.values.expand(
      (paths) => paths,
    )) {
      files.addAll(await _contentFiles(root, relativePath));
    }
    final unique = <String, File>{};
    for (final file in files) {
      final resolved = await file.resolveSymbolicLinks();
      if (!p.isWithin(root, resolved) && resolved != root) {
        throw PackageException(
          'Package content escapes its root: ${file.path}',
        );
      }
      final relative = resolved == p.join(packageRoot, 'package.yaml')
          ? 'package.yaml'
          : p.posix.joinAll(p.split(p.relative(resolved, from: root)));
      unique[relative] = File(resolved);
    }
    final ordered = unique.keys.toList()..sort();
    final bytes = BytesBuilder(copy: false);
    for (final relative in ordered) {
      bytes
        ..add(utf8.encode(relative))
        ..add(const [0])
        ..add(await unique[relative]!.readAsBytes())
        ..add(const [0]);
    }
    return sha256.convert(bytes.takeBytes()).toString();
  }

  /// Returns source-root-relative declared files in deterministic path order.
  Future<List<File>> filesForContents(
    String contentRoot,
    PackageManifest manifest,
  ) async {
    final root = await _canonicalDirectory(contentRoot);
    final files = <File>[];
    for (final relativePath in manifest.contents.values.expand(
      (paths) => paths,
    )) {
      files.addAll(await _contentFiles(root, relativePath));
    }
    final byRelativePath = <String, File>{};
    for (final file in files) {
      final resolved = await file.resolveSymbolicLinks();
      if (!p.isWithin(root, resolved)) {
        throw PackageException(
          'Package content escapes its root: ${file.path}',
        );
      }
      byRelativePath[p.posix.joinAll(
        p.split(p.relative(resolved, from: root)),
      )] = File(
        resolved,
      );
    }
    final sorted = byRelativePath.keys.toList()..sort();
    return [for (final path in sorted) byRelativePath[path]!];
  }

  Future<List<File>> _contentFiles(String root, String relativePath) async {
    final candidate = File(p.joinAll([root, ...p.posix.split(relativePath)]));
    final directory = Directory(candidate.path);
    if (candidate.existsSync()) {
      final resolved = await candidate.resolveSymbolicLinks();
      if (!p.isWithin(root, resolved)) {
        throw PackageException(
          'Package content escapes its root: $relativePath',
        );
      }
      return [File(resolved)];
    }
    if (!directory.existsSync()) {
      throw PackageException(
        'Declared package content does not exist: $relativePath',
      );
    }
    final resolvedDirectory = await directory.resolveSymbolicLinks();
    if (!p.isWithin(root, resolvedDirectory)) {
      throw PackageException('Package content escapes its root: $relativePath');
    }
    final entities = await directory
        .list(recursive: true, followLinks: false)
        .toList();
    if (entities.any((entity) => entity is Link)) {
      throw PackageException(
        'Package content contains a symbolic link: $relativePath',
      );
    }
    final files = entities.whereType<File>().toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    return files;
  }

  Future<String> _canonicalDirectory(String directoryPath) async {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      throw PackageException(
        'Package directory does not exist: $directoryPath',
      );
    }
    return directory.resolveSymbolicLinks();
  }

  static Map<String, Object?> _parseYamlMap(String input, String context) {
    try {
      final value = loadYaml(input);
      if (value is! YamlMap) {
        throw PackageException('$context must be a YAML object.');
      }
      return _plainMap(value);
    } on FormatException catch (error) {
      throw PackageException('Cannot parse $context: ${error.message}');
    }
  }

  static Map<String, Object?> _plainMap(Map<Object?, Object?> input) =>
      input.map(
        (key, value) => MapEntry('$key', _plainValue(value)),
      );

  static Object? _plainValue(Object? value) {
    if (value is Map<Object?, Object?>) return _plainMap(value);
    if (value is List) return value.map<Object?>(_plainValue).toList();
    return value;
  }
}
