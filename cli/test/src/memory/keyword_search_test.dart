import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:test/test.dart';

MemoryDocument _document(String path, String text) => MemoryDocument(
  path: path,
  kind: MemoryEntryKind.note,
  title: path,
  text: text,
);

void main() {
  test('scores documents by total term occurrences', () {
    final hits = keywordSearch([
      _document('notes/a.md', 'rollback rollback rollback'),
      _document('notes/b.md', 'rollback once'),
    ], 'rollback');

    expect(hits.map((hit) => hit.path), ['notes/a.md', 'notes/b.md']);
    expect(hits.first.score, 3);
    expect(hits.last.score, 1);
  });

  test('breaks score ties with path order', () {
    final hits = keywordSearch([
      _document('notes/z.md', 'rollback'),
      _document('notes/a.md', 'rollback'),
    ], 'rollback');

    expect(hits.map((hit) => hit.path), ['notes/a.md', 'notes/z.md']);
  });

  test('sums the counts of every query term', () {
    final hits = keywordSearch([
      _document('notes/a.md', 'rollback and staging'),
    ], 'rollback staging');

    expect(hits.single.score, 2);
  });

  test('drops single-character terms and empty queries', () {
    expect(keywordSearch([_document('notes/a.md', 'a a a')], 'a'), isEmpty);
    expect(keywordSearch([_document('notes/a.md', 'text')], '   '), isEmpty);
  });

  test('matches the document stem as well as its body', () {
    final hits = keywordSearch([
      _document('notes/rollback.md', 'unrelated body'),
    ], 'rollback');

    expect(hits.single.path, 'notes/rollback.md');
  });

  test('clamps the limit between one and twenty', () {
    final documents = [
      for (var index = 0; index < 30; index++)
        _document('notes/$index.md', 'rollback'),
    ];

    expect(keywordSearch(documents, 'rollback', limit: 0), hasLength(1));
    expect(keywordSearch(documents, 'rollback', limit: -5), hasLength(1));
    expect(keywordSearch(documents, 'rollback', limit: 100), hasLength(20));
    expect(keywordSearch(documents, 'rollback', limit: 3), hasLength(3));
  });

  test('builds a collapsed excerpt around the first match', () {
    final hits = keywordSearch([
      _document(
        'notes/a.md',
        '${'padding ' * 40}rollback happened\n\n   here${' tail' * 200}',
      ),
    ], 'rollback');

    final excerpt = hits.single.excerpt;
    expect(excerpt, contains('rollback happened here'));
    expect(excerpt, isNot(contains('\n')));
    expect(excerpt, isNot(contains('  ')));
    expect(excerpt.length, lessThanOrEqualTo(320));
  });

  test('skips generated and hidden paths', () {
    final hits = keywordSearch([
      _document('index/embeddings.json', 'rollback'),
      _document('.hidden/a.md', 'rollback'),
      _document('notes/.draft.md', 'rollback'),
      _document('notes/a.md', 'rollback'),
    ], 'rollback');

    expect(hits.map((hit) => hit.path), ['notes/a.md']);
    expect(isExcludedMemoryPath('index/embeddings.json'), isTrue);
    expect(isExcludedMemoryPath('notes/a.md'), isFalse);
  });
}
