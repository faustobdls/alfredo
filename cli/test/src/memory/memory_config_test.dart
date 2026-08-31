import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late File file;
  late MemoryConfigStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-memory-config-');
    file = File(p.join(temporary.path, 'config.json'));
    store = MemoryConfigStore(file: file);
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Future<void> writeRaw(Map<String, Object?> document) =>
      file.writeAsString(jsonEncode(document));

  test('round-trips a configuration through the versioned envelope', () async {
    await store.write(
      const MemoryConfig(
        embeddings: EmbeddingsConfig(enabled: true, dimensions: 768),
        capture: CaptureConfig(
          sessionEndHook: true,
          gitDiffStat: false,
          targets: ['codex', 'claude-code'],
        ),
        defaultScope: MemoryScope.project,
      ),
    );

    final document =
        jsonDecode(await file.readAsString()) as Map<String, Object?>;
    final config = await store.read();

    expect(document['version'], 1);
    expect(config.embeddings.enabled, isTrue);
    expect(config.embeddings.provider, 'ollama');
    expect(config.embeddings.dimensions, 768);
    expect(config.capture.sessionEndHook, isTrue);
    expect(config.capture.gitDiffStat, isFalse);
    expect(config.capture.targets, ['codex', 'claude-code']);
    expect(config.defaultScope, MemoryScope.project);
  });

  test('returns defaults for a missing configuration file', () async {
    final config = await store.readOrDefault();

    expect(config.embeddings.enabled, isFalse);
    expect(config.embeddings.model, 'nomic-embed-text');
    expect(config.capture.sessionEndHook, isFalse);
    expect(config.defaultScope, MemoryScope.user);
  });

  test('leaves no temporary residue after a write', () async {
    await store.write(const MemoryConfig.defaults());

    expect(
      temporary.listSync().map((entity) => p.basename(entity.path)),
      ['config.json'],
    );
  });

  test('rejects an unsupported schema version', () async {
    await writeRaw({
      'version': 2,
      'embeddings': {'enabled': false},
      'capture': {'sessionEndHook': false},
      'defaultScope': 'user',
    });

    expect(store.read, throwsA(isA<MemoryException>()));
  });

  test('rejects unknown top-level keys', () async {
    await writeRaw({
      'version': 1,
      'embeddings': {'enabled': false},
      'capture': {'sessionEndHook': false},
      'defaultScope': 'user',
      'unknown': true,
    });

    expect(store.read, throwsA(isA<MemoryException>()));
  });

  test('rejects an unknown default scope', () async {
    await writeRaw({
      'version': 1,
      'embeddings': {'enabled': false},
      'capture': {'sessionEndHook': false},
      'defaultScope': 'global',
    });

    expect(store.read, throwsA(isA<MemoryException>()));
  });

  test('rejects an unsupported embedding provider', () async {
    await writeRaw({
      'version': 1,
      'embeddings': {'enabled': true, 'provider': 'openai'},
      'capture': {'sessionEndHook': false},
      'defaultScope': 'user',
    });

    expect(store.read, throwsA(isA<MemoryException>()));
  });

  test('rejects unknown nested keys and invalid capture targets', () async {
    await writeRaw({
      'version': 1,
      'embeddings': {'enabled': false, 'unknown': 1},
      'capture': {'sessionEndHook': false},
      'defaultScope': 'user',
    });
    expect(store.read, throwsA(isA<MemoryException>()));

    await writeRaw({
      'version': 1,
      'embeddings': {'enabled': false},
      'capture': {
        'sessionEndHook': false,
        'targets': ['codex', 'codex'],
      },
      'defaultScope': 'user',
    });
    expect(store.read, throwsA(isA<MemoryException>()));
  });

  test('rejects a malformed configuration document', () async {
    await file.writeAsString('not json');

    expect(store.read, throwsA(isA<MemoryException>()));
  });
}
