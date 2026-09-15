import 'dart:io';

import 'package:alfredo_cli/src/package/installation_adapters.dart';
import 'package:alfredo_cli/src/package/package_models.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Loads declarative target adapters from an `adapters/` directory.
class DeclarativeAdapterLoader {
  /// Creates an adapter loader.
  const DeclarativeAdapterLoader({required this.adaptersDirectory});

  /// Root directory containing adapter subdirectories with `adapter.yaml`.
  final Directory adaptersDirectory;

  /// Loads all valid declarative adapters found in [adaptersDirectory].
  Future<List<TargetAdapter>> loadAll() async {
    if (!adaptersDirectory.existsSync()) {
      return TargetAdapters.all;
    }

    final entities = adaptersDirectory.listSync(followLinks: false);
    final customAdapters = <TargetAdapter>[];

    for (final entity in entities) {
      if (entity is Directory) {
        final yamlFile = File(p.join(entity.path, 'adapter.yaml'));
        if (yamlFile.existsSync()) {
          try {
            final adapter = _parseAdapterYaml(await yamlFile.readAsString());
            customAdapters.add(adapter);
          } on Exception {
            // Ignore malformed custom adapters
          }
        }
      }
    }

    if (customAdapters.isEmpty) {
      return TargetAdapters.all;
    }

    // Merge custom adapters, overriding built-ins with the same ID
    final customIds = customAdapters.map((a) => a.id).toSet();
    final merged = <TargetAdapter>[
      ...customAdapters,
      for (final builtIn in TargetAdapters.all)
        if (!customIds.contains(builtIn.id)) builtIn,
    ];
    return List.unmodifiable(merged);
  }

  static TargetAdapter _parseAdapterYaml(String input) {
    final value = loadYaml(input);
    if (value is! YamlMap) {
      throw const PackageException('Adapter configuration must be a YAML map.');
    }
    final map = _plainMap(value);
    final id = map['id'] as String?;
    if (id == null || id.isEmpty) {
      throw const PackageException('Adapter definition requires an id.');
    }
    final userDir = map['user_directory'] as String? ?? '.alfredo';
    final projectDir = map['project_directory'] as String? ?? '.alfredo';
    final markersRaw = map['configuration_markers'] ?? const <Object?>[];
    final markers = (markersRaw is List)
        ? markersRaw.map((e) => '$e').toList()
        : const <String>[];

    return TargetAdapter(
      id: id,
      userDirectoryName: userDir,
      projectDirectoryName: projectDir,
      configurationMarkers: markers,
    );
  }

  static Map<String, Object?> _plainMap(Map<Object?, Object?> input) =>
      input.map((key, value) => MapEntry('$key', _plainValue(value)));

  static Object? _plainValue(Object? value) {
    if (value is Map<Object?, Object?>) return _plainMap(value);
    if (value is List) return value.map<Object?>(_plainValue).toList();
    return value;
  }
}
