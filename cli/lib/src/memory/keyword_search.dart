import 'dart:math' as math;

import 'package:alfredo_cli/src/memory/memory_models.dart';

final _termPattern = RegExp(r'[\w]+', unicode: true);
final _whitespacePattern = RegExp(r'\s+');

/// Ranks [documents] by how often the terms of [query] occur in them.
///
/// The ranking is deterministic: higher scores first, then path order. It never
/// reads the filesystem and never throws, so it can back every embedding path.
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

  final hits = <MemorySearchHit>[];
  for (final document in documents) {
    if (isExcludedMemoryPath(document.path)) continue;
    final source = '${_stem(document.path)}\n${document.text}';
    final haystack = source.toLowerCase();
    var score = 0;
    for (final term in terms) {
      score += haystack.split(term).length - 1;
    }
    if (score == 0) continue;
    final positions = [
      for (final term in terms)
        if (haystack.contains(term)) haystack.indexOf(term),
    ];
    final position = positions.isEmpty ? 0 : positions.reduce(math.min);
    hits.add(
      MemorySearchHit(
        path: document.path,
        title: document.title,
        excerpt: _excerpt(source, position),
        score: score.toDouble(),
      ),
    );
  }
  hits.sort((left, right) {
    final score = right.score.compareTo(left.score);
    return score == 0 ? left.path.compareTo(right.path) : score;
  });
  return List.unmodifiable(hits.take(limit.clamp(1, 20)));
}

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
