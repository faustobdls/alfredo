import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:test/test.dart';

MemorySearchHit _hit(String path, double score) => MemorySearchHit(
  path: path,
  title: path,
  excerpt: 'excerpt for $path',
  score: score,
);

void main() {
  group('combineHybridHits', () {
    test('returns only keyword hits when weight is zero', () {
      final keyword = [_hit('a.md', 3), _hit('b.md', 1)];
      final vector = [_hit('c.md', 0.9)];

      final blended = combineHybridHits(
        keywordHits: keyword,
        vectorHits: vector,
        vectorWeight: 0,
      );

      expect(blended, keyword);
    });

    test('returns only vector hits when weight is one', () {
      final keyword = [_hit('a.md', 3)];
      final vector = [_hit('c.md', 0.9), _hit('d.md', 0.4)];

      final blended = combineHybridHits(
        keywordHits: keyword,
        vectorHits: vector,
        vectorWeight: 1,
      );

      expect(blended, vector);
    });

    test('clamps out-of-range weights to the nearest bound', () {
      final keyword = [_hit('a.md', 3)];
      final vector = [_hit('c.md', 0.9)];

      expect(
        combineHybridHits(
          keywordHits: keyword,
          vectorHits: vector,
          vectorWeight: -5,
        ),
        keyword,
      );
      expect(
        combineHybridHits(
          keywordHits: keyword,
          vectorHits: vector,
          vectorWeight: 5,
        ),
        vector,
      );
    });

    test('blends normalized scores at an even weight', () {
      final keyword = [_hit('shared.md', 4), _hit('keyword-only.md', 2)];
      final vector = [_hit('shared.md', 0.5), _hit('vector-only.md', 1)];

      final blended = combineHybridHits(
        keywordHits: keyword,
        vectorHits: vector,
        vectorWeight: 0.5,
      );

      final byPath = {for (final hit in blended) hit.path: hit.score};
      // shared.md: keyword normalized 4/4=1, vector normalized 0.5/1=0.5
      // -> 0.5*1 + 0.5*0.5 = 0.75
      expect(byPath['shared.md'], closeTo(0.75, 1e-9));
      // keyword-only.md: keyword normalized 2/4=0.5, vector 0
      // -> 0.5*0.5 + 0.5*0 = 0.25
      expect(byPath['keyword-only.md'], closeTo(0.25, 1e-9));
      // vector-only.md: keyword 0, vector normalized 1/1=1
      // -> 0.5*0 + 0.5*1 = 0.5
      expect(byPath['vector-only.md'], closeTo(0.5, 1e-9));
      expect(blended.map((hit) => hit.path).first, 'shared.md');
    });

    test('keeps a document found by only one ranking', () {
      final keyword = [_hit('only-keyword.md', 5)];
      final vector = <MemorySearchHit>[];

      final blended = combineHybridHits(
        keywordHits: keyword,
        vectorHits: vector,
        vectorWeight: 0.3,
      );

      expect(blended.single.path, 'only-keyword.md');
      expect(blended.single.score, closeTo(0.7, 1e-9));
    });

    test('returns nothing when both rankings are empty', () {
      final blended = combineHybridHits(
        keywordHits: const [],
        vectorHits: const [],
        vectorWeight: 0.5,
      );

      expect(blended, isEmpty);
    });

    test('clamps the limit between one and twenty', () {
      final keyword = [
        for (var index = 0; index < 30; index++) _hit('k$index.md', 1),
      ];
      final vector = [
        for (var index = 0; index < 30; index++) _hit('k$index.md', 1),
      ];

      expect(
        combineHybridHits(
          keywordHits: keyword,
          vectorHits: vector,
          vectorWeight: 0.5,
          limit: 100,
        ),
        hasLength(20),
      );
      expect(
        combineHybridHits(
          keywordHits: keyword,
          vectorHits: vector,
          vectorWeight: 0.5,
          limit: 0,
        ),
        hasLength(1),
      );
    });
  });
}
