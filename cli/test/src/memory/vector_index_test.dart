import 'dart:io';

import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../helpers/memory_fixture.dart';

void main() {
  late Directory temporary;
  late MemoryStore store;
  late FakeEmbeddingsClient client;

  final clock = DateTime(2026, 8, 31, 12);

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-memory-index-');
    store = MemoryStore(
      directory: Directory(p.join(temporary.path, 'memory')),
      now: () => clock,
    );
    client = FakeEmbeddingsClient();
    await store.ensureSkeleton();
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  group('cosineSimilarity', () {
    test('returns one for identical vectors', () {
      expect(cosineSimilarity([1, 2, 3], [1, 2, 3]), closeTo(1, 1e-12));
      expect(cosineSimilarity([1, 2, 3], [2, 4, 6]), closeTo(1, 1e-12));
    });

    test('returns zero for orthogonal vectors', () {
      expect(cosineSimilarity([1, 0], [0, 1]), 0);
    });

    test('returns minus one for opposite vectors', () {
      expect(cosineSimilarity([1, 0], [-1, 0]), closeTo(-1, 1e-12));
    });

    test('returns zero for mismatched or degenerate vectors', () {
      expect(cosineSimilarity([1, 2], [1, 2, 3]), 0);
      expect(cosineSimilarity(const [], const []), 0);
      expect(cosineSimilarity([0, 0], [1, 1]), 0);
    });
  });

  test('embeds only new or changed documents', () async {
    await store.writeNote(title: 'Alpha One', body: 'alpha alpha');
    await store.writeNote(title: 'Beta One', body: 'beta');

    final first = await store.updateIndex(client);
    expect(first.embedded, 2);
    expect(first.reused, 0);
    expect(client.embeddedInputs, 2);

    final second = await store.updateIndex(client);
    expect(second.embedded, 0);
    expect(second.reused, 2);
    expect(client.embeddedInputs, 2);

    await store.appendActivity(message: 'gamma work');
    final third = await store.updateIndex(client);
    expect(third.embedded, 1);
    expect(third.reused, 2);
  });

  test('re-embeds every document when forced', () async {
    await store.writeNote(title: 'Alpha One', body: 'alpha');
    await store.updateIndex(client);

    final report = await store.updateIndex(client, force: true);

    expect(report.embedded, 1);
    expect(report.reused, 0);
  });

  test('prunes vectors whose document no longer exists', () async {
    await store.writeNote(title: 'Alpha One', body: 'alpha');
    await store.writeNote(title: 'Beta One', body: 'beta');
    await store.updateIndex(client);

    await File(
      p.join(store.notesDirectory.path, '2026-08-31-beta-one.md'),
    ).delete();
    final report = await store.updateIndex(client);
    final index = await EmbeddingIndexStore(
      file: store.embeddingIndexFile,
    ).read();

    expect(report.pruned, 1);
    expect(
      index!.vectors.map((vector) => vector.path),
      isNot(contains('notes/2026-08-31-beta-one.md')),
    );
  });

  test('re-embeds everything when the model changes', () async {
    await store.writeNote(title: 'Alpha One', body: 'alpha');
    await store.updateIndex(client);

    final other = FakeEmbeddingsClient(model: 'other-embed');
    final report = await store.updateIndex(other);

    expect(report.embedded, 1);
    expect(report.reused, 0);
    final index = await EmbeddingIndexStore(
      file: store.embeddingIndexFile,
    ).read();
    expect(index!.model, 'other-embed');
  });

  test('round-trips the persisted index', () async {
    await store.writeNote(title: 'Alpha One', body: 'alpha');
    await store.updateIndex(client);

    final index = await EmbeddingIndexStore(
      file: store.embeddingIndexFile,
    ).read();

    expect(index!.version, 1);
    expect(index.model, 'fake-embed');
    expect(index.dimensions, 5);
    expect(index.vectors.first.sha256, hasLength(64));
    expect(index.vectors.first.kind, isNotEmpty);
  });

  test('rejects an unreadable index file', () async {
    await store.embeddingIndexFile.writeAsString('not json');

    expect(
      EmbeddingIndexStore(file: store.embeddingIndexFile).read,
      throwsA(isA<MemoryException>()),
    );
  });

  test('ranks documents by cosine similarity to the query', () async {
    await store.writeNote(title: 'Alpha One', body: 'alpha alpha alpha');
    await store.writeNote(title: 'Beta One', body: 'beta beta beta');
    await store.updateIndex(client);

    final hits = await store.search('alpha', embeddings: client);

    expect(hits, isNotEmpty);
    expect(hits.first.path, 'notes/2026-08-31-alpha-one.md');
    expect(hits.first.score, greaterThan(0.9));
    expect(hits.first.excerpt, isNot(contains('\n')));
  });

  test('falls back to keyword search when no index exists', () async {
    await store.writeNote(title: 'Alpha One', body: 'alpha alpha');

    final hits = await store.search('alpha', embeddings: client);

    expect(hits.single.path, 'notes/2026-08-31-alpha-one.md');
    expect(client.embedCalls, 0);
  });

  test('falls back to keyword search when the provider fails', () async {
    await store.writeNote(title: 'Alpha One', body: 'alpha alpha');
    await store.updateIndex(client);

    final hits = await store.search('alpha', embeddings: _FailingClient());

    expect(hits.single.path, 'notes/2026-08-31-alpha-one.md');
  });

  test('keeps keyword results when embeddings are disabled', () async {
    await store.writeNote(title: 'Alpha One', body: 'alpha');
    await store.updateIndex(client);

    final hits = await store.search(
      'alpha',
      keywordOnly: true,
      embeddings: client,
    );

    expect(hits.single.score, greaterThanOrEqualTo(1));
  });
}

class _FailingClient implements EmbeddingsClient {
  @override
  int? get dimensions => null;

  @override
  String get model => 'fake-embed';

  @override
  Future<List<List<double>>> embed(List<String> inputs) async =>
      throw const MemoryException('provider offline');

  @override
  Future<List<String>> listModels() async => const [];

  @override
  Future<bool> probe() async => false;

  @override
  Future<void> pull(String model, {void Function(String)? onProgress}) async =>
      throw const MemoryException('provider offline');
}
