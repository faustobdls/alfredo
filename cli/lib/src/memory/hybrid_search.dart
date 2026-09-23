import 'dart:math' as math;

import 'package:alfredo_cli/src/memory/memory_models.dart';

/// Blends lexical and vector search rankings using an adjustable weight.
///
/// [vectorWeight] is clamped to the `[0, 1]` range: `0` returns only
/// [keywordHits], `1` returns only [vectorHits], and any value in between
/// linearly blends both rankings after normalizing each list's scores to
/// `[0, 1]` by its own maximum. Normalizing independently keeps the blend
/// meaningful even though keyword scores (term counts) and vector scores
/// (cosine similarity) live on unrelated scales.
///
/// A document that only one ranking found still participates in the blend
/// with a zero contribution from the ranking that missed it, so a strong
/// single-method match is never dropped outright by a moderate weight.
List<MemorySearchHit> combineHybridHits({
  required List<MemorySearchHit> keywordHits,
  required List<MemorySearchHit> vectorHits,
  required double vectorWeight,
  int limit = 8,
}) {
  final weight = vectorWeight.clamp(0.0, 1.0);
  if (weight <= 0) return _limited(keywordHits, limit);
  if (weight >= 1) return _limited(vectorHits, limit);

  final keywordScores = _normalizedScores(keywordHits);
  final vectorScores = _normalizedScores(vectorHits);

  final byPath = <String, MemorySearchHit>{};
  for (final hit in keywordHits) {
    byPath[hit.path] = hit;
  }
  for (final hit in vectorHits) {
    byPath.putIfAbsent(hit.path, () => hit);
  }

  final blended = <MemorySearchHit>[];
  for (final entry in byPath.entries) {
    final keywordScore = keywordScores[entry.key] ?? 0.0;
    final vectorScore = vectorScores[entry.key] ?? 0.0;
    final combined = ((1 - weight) * keywordScore) + (weight * vectorScore);
    if (combined <= 0) continue;
    blended.add(entry.value.withScore(combined));
  }
  blended.sort((left, right) {
    final score = right.score.compareTo(left.score);
    return score == 0 ? left.path.compareTo(right.path) : score;
  });
  return List.unmodifiable(blended.take(limit.clamp(1, 20)));
}

Map<String, double> _normalizedScores(List<MemorySearchHit> hits) {
  if (hits.isEmpty) return const {};
  final maxScore = hits.map((hit) => hit.score).reduce(math.max);
  if (maxScore <= 0) return const {};
  return {for (final hit in hits) hit.path: hit.score / maxScore};
}

List<MemorySearchHit> _limited(List<MemorySearchHit> hits, int limit) =>
    List.unmodifiable(hits.take(limit.clamp(1, 20)));
