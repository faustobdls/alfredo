import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/source/source_manifest_loader.dart';
import 'package:alfredo_cli/src/source/source_models.dart';

/// Persists registered sources without modifying their contents.
class SourceRegistry {
  /// Creates a source registry backed by [file].
  SourceRegistry({
    required this.file,
    this.loader = const SourceManifestLoader(),
  });

  /// Registry state file.
  final File file;

  /// Validator used before a source is persisted or tested.
  final SourceManifestLoader loader;

  /// Returns registrations sorted by their user-selected name.
  Future<List<RegisteredSource>> list() async {
    if (!file.existsSync()) return const [];
    try {
      final document = jsonDecode(await file.readAsString());
      if (document is! Map<String, dynamic> || document['version'] != 1) {
        throw const SourceException('Unsupported source registry format.');
      }
      final values = document['sources'];
      if (values is! List) {
        throw const SourceException('Invalid source registry format.');
      }
      final sources = values.map((value) {
        if (value is! Map<String, dynamic>) {
          throw const SourceException('Invalid source registry entry.');
        }
        return RegisteredSource.fromJson(value.cast<String, Object?>());
      }).toList()..sort((left, right) => left.name.compareTo(right.name));
      return List.unmodifiable(sources);
    } on FormatException catch (error) {
      throw SourceException('Cannot read source registry: ${error.message}');
    }
  }

  /// Returns a registration by [name].
  Future<RegisteredSource> get(String name) async {
    for (final source in await list()) {
      if (source.name == name) return source;
    }
    throw SourceException('Source is not registered: $name');
  }

  /// Validates and registers a local source.
  Future<RegisteredSource> addLocal(String name, String directoryPath) async {
    _validateRegistrationName(name);
    final catalog = await loader.load(directoryPath);
    final sources = [...await list()];
    if (sources.any((source) => source.name == name)) {
      throw SourceException('Source name is already registered: $name');
    }
    if (sources.any((source) => source.location == catalog.root)) {
      throw SourceException(
        'Source path is already registered: ${catalog.root}',
      );
    }
    final registration = RegisteredSource(
      name: name,
      kind: SourceKind.local,
      location: catalog.root,
      sourceId: catalog.id,
      sourceName: catalog.name,
    );
    sources.add(registration);
    await _write(sources);
    return registration;
  }

  /// Revalidates a registered source and returns its current catalog.
  Future<SourceCatalog> test(String name) async {
    final source = await get(name);
    final catalog = await loader.load(source.location);
    if (catalog.id != source.sourceId) {
      throw SourceException(
        'Source identity changed from ${source.sourceId} to ${catalog.id}.',
      );
    }
    return catalog;
  }

  /// Removes a registration without modifying the source directory.
  Future<RegisteredSource> remove(String name) async {
    final sources = [...await list()];
    final index = sources.indexWhere((source) => source.name == name);
    if (index < 0) throw SourceException('Source is not registered: $name');
    final removed = sources.removeAt(index);
    await _write(sources);
    return removed;
  }

  Future<void> _write(List<RegisteredSource> sources) async {
    await file.parent.create(recursive: true);
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final temporary = File('${file.path}.$pid.$nonce.tmp');
    final document = <String, Object?>{
      'version': 1,
      'sources': [
        for (final source in sources..sort((a, b) => a.name.compareTo(b.name)))
          source.toJson(),
      ],
    };
    try {
      await temporary.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(document)}\n',
        flush: true,
      );
      await temporary.rename(file.path);
    } on FileSystemException catch (error) {
      throw SourceException('Cannot update source registry: ${error.message}');
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
  }

  static void _validateRegistrationName(String name) {
    if (!RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(name)) {
      throw SourceException('Invalid source registration name: $name');
    }
  }
}
