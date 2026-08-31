import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/memory/memory_models.dart';

/// Reads and atomically writes the durable memory configuration.
class MemoryConfigStore {
  /// Creates a configuration store backed by [file].
  const MemoryConfigStore({required this.file});

  /// Persisted JSON configuration.
  final File file;

  /// Reads and revalidates the persisted configuration.
  Future<MemoryConfig> read() async {
    try {
      final document = jsonDecode(await file.readAsString());
      if (document is! Map<String, dynamic> ||
          document['version'] != MemoryConfig.schemaVersion) {
        throw const MemoryException('Unsupported memory configuration format.');
      }
      for (final key in document.keys) {
        if (!const {
          'version',
          'embeddings',
          'capture',
          'defaultScope',
        }.contains(key)) {
          throw MemoryException('Unknown memory configuration key: $key');
        }
      }
      return MemoryConfig.fromJson(document.cast<String, Object?>());
    } on FileSystemException catch (error) {
      throw MemoryException(
        'Cannot read memory configuration: ${error.message}',
      );
    } on FormatException catch (error) {
      throw MemoryException(
        'Cannot read memory configuration: ${error.message}',
      );
    }
  }

  /// Reads the configuration, falling back to defaults when it is missing.
  Future<MemoryConfig> readOrDefault() async {
    if (!file.existsSync()) return const MemoryConfig.defaults();
    return read();
  }

  /// Atomically persists [config].
  Future<void> write(MemoryConfig config) async {
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final temporary = File('${file.path}.$pid.$nonce.tmp');
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(config.toJson())}\n',
        flush: true,
      );
      await temporary.rename(file.path);
    } on FileSystemException catch (error) {
      throw MemoryException(
        'Cannot update memory configuration: ${error.message}',
      );
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
  }
}
