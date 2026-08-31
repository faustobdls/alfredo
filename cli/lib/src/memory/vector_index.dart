import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:alfredo_cli/src/memory/embeddings_client.dart';
import 'package:alfredo_cli/src/memory/keyword_search.dart';
import 'package:alfredo_cli/src/memory/memory_models.dart';
import 'package:crypto/crypto.dart';

/// One embedded memory document.
class EmbeddingVector {
  /// Creates an embedded document vector.
  const EmbeddingVector({
    required this.id,
    required this.path,
    required this.kind,
    required this.sha256,
    required this.values,
  });

  /// Recreates a persisted vector.
  factory EmbeddingVector.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final path = json['path'];
    final kind = json['kind'];
    final digest = json['sha256'];
    final values = json['values'];
    if (id is! String ||
        path is! String ||
        kind is! String ||
        digest is! String ||
        values is! List) {
      throw const FormatException('Invalid embedding index entry.');
    }
    return EmbeddingVector(
      id: id,
      path: path,
      kind: kind,
      sha256: digest,
      values: List.unmodifiable(<double>[
        for (final value in values)
          if (value is num)
            value.toDouble()
          else
            throw const FormatException('Invalid embedding index vector.'),
      ]),
    );
  }

  /// Stable vector identifier, currently the document path.
  final String id;

  /// Portable document path relative to the memory directory.
  final String path;

  /// Durability class of the embedded document.
  final String kind;

  /// SHA-256 of the embedded text, used to skip unchanged documents.
  final String sha256;

  /// Vector components.
  final List<double> values;

  /// Converts this vector to the durable index format.
  Map<String, Object?> toJson() => {
    'id': id,
    'path': path,
    'kind': kind,
    'sha256': sha256,
    'values': [...values],
  };
}

/// A persisted set of document vectors produced by one model.
class EmbeddingIndex {
  /// Creates an embedding index.
  const EmbeddingIndex({
    required this.model,
    required this.dimensions,
    required this.vectors,
    this.version = schemaVersion,
  });

  /// Recreates a persisted index.
  factory EmbeddingIndex.fromJson(Map<String, Object?> json) {
    final model = json['model'];
    final dimensions = json['dimensions'];
    final vectors = json['vectors'];
    if (json['version'] != schemaVersion ||
        model is! String ||
        dimensions is! int ||
        vectors is! List) {
      throw const FormatException('Unsupported embedding index format.');
    }
    return EmbeddingIndex(
      model: model,
      dimensions: dimensions,
      vectors: List.unmodifiable(<EmbeddingVector>[
        for (final vector in vectors)
          if (vector is Map)
            EmbeddingVector.fromJson(
              vector.map((key, value) => MapEntry('$key', value)),
            )
          else
            throw const FormatException('Invalid embedding index entry.'),
      ]),
    );
  }

  /// Schema version for persisted embedding indexes.
  static const schemaVersion = 1;

  /// Persisted schema version.
  final int version;

  /// Model that produced every vector.
  final String model;

  /// Vector length shared by every entry.
  final int dimensions;

  /// Embedded documents, sorted by path.
  final List<EmbeddingVector> vectors;

  /// Converts this index to the durable format.
  Map<String, Object?> toJson() => {
    'version': version,
    'model': model,
    'dimensions': dimensions,
    'vectors': [for (final vector in vectors) vector.toJson()],
  };
}

/// Reads and atomically writes the embedding index file.
class EmbeddingIndexStore {
  /// Creates an index store backed by [file].
  const EmbeddingIndexStore({required this.file});

  /// Persisted JSON index.
  final File file;

  /// Reads the index, returning `null` when it has not been built yet.
  Future<EmbeddingIndex?> read() async {
    if (!file.existsSync()) return null;
    try {
      final document = jsonDecode(await file.readAsString());
      if (document is! Map) {
        throw const MemoryException('Unsupported embedding index format.');
      }
      return EmbeddingIndex.fromJson(
        document.map((key, value) => MapEntry('$key', value)),
      );
    } on FileSystemException catch (error) {
      throw MemoryException('Cannot read embedding index: ${error.message}');
    } on FormatException catch (error) {
      throw MemoryException('Cannot read embedding index: ${error.message}');
    }
  }

  /// Atomically persists [index].
  Future<void> write(EmbeddingIndex index) async {
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final temporary = File('${file.path}.$pid.$nonce.tmp');
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(index.toJson())}\n',
        flush: true,
      );
      await temporary.rename(file.path);
    } on FileSystemException catch (error) {
      throw MemoryException('Cannot update embedding index: ${error.message}');
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
  }
}

/// The outcome of one index build.
class MemoryIndexReport {
  /// Creates an index build report.
  const MemoryIndexReport({
    required this.embedded,
    required this.reused,
    required this.pruned,
  });

  /// Documents embedded during this build.
  final int embedded;

  /// Unchanged documents whose vectors were kept.
  final int reused;

  /// Vectors removed because their document no longer exists.
  final int pruned;
}

/// Returns the cosine similarity of [left] and [right].
///
/// Returns `0` for mismatched lengths and for zero-magnitude vectors, so a
/// malformed index degrades into "no match" instead of an error.
double cosineSimilarity(List<double> left, List<double> right) {
  if (left.length != right.length || left.isEmpty) return 0;
  var dot = 0.0;
  var leftNorm = 0.0;
  var rightNorm = 0.0;
  for (var index = 0; index < left.length; index++) {
    dot += left[index] * right[index];
    leftNorm += left[index] * left[index];
    rightNorm += right[index] * right[index];
  }
  if (leftNorm == 0 || rightNorm == 0) return 0;
  return dot / (math.sqrt(leftNorm) * math.sqrt(rightNorm));
}

/// Embeds new or changed [documents] and prunes vectors for deleted paths.
Future<MemoryIndexReport> buildEmbeddingIndex({
  required EmbeddingsClient client,
  required EmbeddingIndexStore store,
  required Iterable<MemoryDocument> documents,
  bool force = false,
}) async {
  final searchable = [
    for (final document in documents)
      if (!isExcludedMemoryPath(document.path)) document,
  ]..sort((left, right) => left.path.compareTo(right.path));
  final current = await store.read();
  final reusable = <String, EmbeddingVector>{
    if (current != null && current.model == client.model && !force)
      for (final vector in current.vectors) vector.path: vector,
  };

  final vectors = <EmbeddingVector>[];
  final pending = <MemoryDocument>[];
  final digests = <String, String>{};
  var reused = 0;
  for (final document in searchable) {
    final digest = sha256.convert(utf8.encode(document.text)).toString();
    digests[document.path] = digest;
    final existing = reusable[document.path];
    if (existing != null && existing.sha256 == digest) {
      vectors.add(existing);
      reused++;
      continue;
    }
    pending.add(document);
  }

  if (pending.isNotEmpty) {
    final embeddings = await client.embed([
      for (final document in pending) document.text,
    ]);
    if (embeddings.length != pending.length) {
      throw const MemoryException(
        'Embedding provider returned an unexpected number of vectors.',
      );
    }
    for (var index = 0; index < pending.length; index++) {
      final document = pending[index];
      vectors.add(
        EmbeddingVector(
          id: document.path,
          path: document.path,
          kind: document.kind.name,
          sha256: digests[document.path]!,
          values: embeddings[index],
        ),
      );
    }
  }

  vectors.sort((left, right) => left.path.compareTo(right.path));
  final paths = {for (final document in searchable) document.path};
  final pruned = (current?.vectors ?? const <EmbeddingVector>[])
      .where((vector) => !paths.contains(vector.path))
      .length;
  await store.write(
    EmbeddingIndex(
      model: client.model,
      dimensions: vectors.isEmpty ? 0 : vectors.first.values.length,
      vectors: List.unmodifiable(vectors),
    ),
  );
  return MemoryIndexReport(
    embedded: pending.length,
    reused: reused,
    pruned: pruned,
  );
}

/// Ranks [documents] against [query] using the persisted [index].
Future<List<MemorySearchHit>> embeddingSearch({
  required EmbeddingsClient client,
  required EmbeddingIndex index,
  required Iterable<MemoryDocument> documents,
  required String query,
  int limit = 8,
}) async {
  final byPath = {for (final document in documents) document.path: document};
  if (index.vectors.isEmpty || byPath.isEmpty) return const [];
  final embeddings = await client.embed([query]);
  if (embeddings.isEmpty) {
    throw const MemoryException('Embedding provider returned no vectors.');
  }
  final queryVector = embeddings.first;
  final hits = <MemorySearchHit>[];
  for (final vector in index.vectors) {
    final document = byPath[vector.path];
    if (document == null) continue;
    final score = cosineSimilarity(queryVector, vector.values);
    if (score <= 0) continue;
    hits.add(
      MemorySearchHit(
        path: document.path,
        title: document.title,
        excerpt: _excerpt(document.text),
        score: score,
      ),
    );
  }
  hits.sort((left, right) {
    final score = right.score.compareTo(left.score);
    return score == 0 ? left.path.compareTo(right.path) : score;
  });
  return List.unmodifiable(hits.take(limit.clamp(1, 20)));
}

String _excerpt(String text) {
  final collapsed = text
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .join(' ');
  return collapsed.length <= 240 ? collapsed : collapsed.substring(0, 240);
}
