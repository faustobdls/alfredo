import 'dart:math' as math;

import 'package:alfredo_cli/src/memory/memory_models.dart';

final _termPattern = RegExp(r'[\w]+', unicode: true);
final _whitespacePattern = RegExp(r'\s+');

/// Free BM25 term-frequency saturation constant.
///
/// Higher values let repeated term occurrences keep contributing to the
/// score for longer before saturating; `1.2`-`2.0` is the conventional
/// range and `1.5` is a common default.
const double _bm25K1 = 1.5;

/// Free BM25 document-length normalization constant, in `[0, 1]`.
///
/// `0` disables length normalization entirely; `1` fully normalizes by
/// document length relative to the corpus average. `0.75` is the
/// conventional default.
const double _bm25B = 0.75;

/// Ranks [documents] against [query] using an Okapi BM25 score.
///
/// BM25 improves on a flat term-count in two ways: rarer terms across the
/// corpus (higher inverse document frequency) contribute more, and term
/// frequency saturates instead of growing without bound, so a document that
/// merely repeats one term many times no longer dominates a document that
/// matches more of the query's distinct terms. Document length is also
/// normalized against the corpus average so short, dense matches are not
/// penalized relative to long documents.
///
/// The ranking is deterministic: higher scores first, then path order. It
/// never reads the filesystem and never throws, so it can back every
/// embedding path.
List<MemorySearchHit> keywordSearch(
  Iterable<MemoryDocument> documents,
  String query, {
  int limit = 8,
}) {
  final terms = [
    for (final match in _termPattern.allMatches(query.toLowerCase()))
      if (match[0]!.length > 1) match[0]!,
  ];
  if (terms.isEmpty) return const [];

  final corpus = [
    for (final document in documents)
      if (!isExcludedMemoryPath(document.path)) document,
  ];
  if (corpus.isEmpty) return const [];

  final haystacks = <MemoryDocument, String>{};
  final lengths = <MemoryDocument, int>{};
  var totalLength = 0;
  for (final document in corpus) {
    final source = '${_stem(document.path)}\n${document.text}';
    final haystack = source.toLowerCase();
    haystacks[document] = haystack;
    final length = _tokenCount(haystack);
    lengths[document] = length;
    totalLength += length;
  }
  final averageLength = totalLength / corpus.length;

  // Document frequency: how many documents in the corpus contain each term
  // at least once, used below to weight rarer terms more heavily (IDF).
  final documentFrequency = <String, int>{for (final term in terms) term: 0};
  for (final term in terms) {
    for (final document in corpus) {
      if (haystacks[document]!.contains(term)) {
        documentFrequency[term] = documentFrequency[term]! + 1;
      }
    }
  }
  final n = corpus.length;
  final inverseDocumentFrequency = <String, double>{
    for (final term in terms)
      term: math.log(
        1 +
            ((n - documentFrequency[term]! + 0.5) /
                (documentFrequency[term]! + 0.5)),
      ),
  };

  final hits = <MemorySearchHit>[];
  for (final document in corpus) {
    final haystack = haystacks[document]!;
    final length = lengths[document]!;
    var score = 0.0;
    var matched = false;
    for (final term in terms) {
      final frequency = haystack.split(term).length - 1;
      if (frequency == 0) continue;
      matched = true;
      final normalizedFrequency = frequency * (_bm25K1 + 1);
      final lengthNorm =
          frequency +
          (_bm25K1 * (1 - _bm25B + (_bm25B * length / averageLength)));
      score +=
          inverseDocumentFrequency[term]! * (normalizedFrequency / lengthNorm);
    }
    if (!matched || score <= 0) continue;
    final positions = [
      for (final term in terms)
        if (haystack.contains(term)) haystack.indexOf(term),
    ];
    final position = positions.isEmpty ? 0 : positions.reduce(math.min);
    hits.add(
      MemorySearchHit(
        path: document.path,
        title: document.title,
        excerpt: _excerpt(
          '${_stem(document.path)}\n${document.text}',
          position,
        ),
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

int _tokenCount(String haystack) => _termPattern.allMatches(haystack).length;

/// Whether a memory path is hidden, generated, or otherwise unsearchable.
bool isExcludedMemoryPath(String path) {
  final segments = path.split('/');
  return segments.first == 'index' ||
      segments.any((segment) => segment.startsWith('.'));
}

String _excerpt(String source, int position) => source
    .substring(
      math.max(0, position - 80),
      math.min(source.length, position + 240),
    )
    .split(_whitespacePattern)
    .where((word) => word.isNotEmpty)
    .join(' ');

String _stem(String path) {
  final name = path.split('/').last;
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}
