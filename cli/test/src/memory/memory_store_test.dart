import 'dart:io';

import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late MemoryStore store;

  final clock = DateTime(2026, 8, 31, 12, 30, 45);

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-memory-store-');
    store = MemoryStore(
      directory: Directory(p.join(temporary.path, 'memory')),
      now: () => clock,
    );
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('creates the skeleton and seeds a default configuration', () async {
    await store.ensureSkeleton();

    expect(store.journalDirectory.existsSync(), isTrue);
    expect(store.notesDirectory.existsSync(), isTrue);
    expect(store.generatedDirectory.existsSync(), isTrue);
    expect(store.indexFile.existsSync(), isTrue);
    expect((await store.readConfig()).defaultScope, MemoryScope.user);
  });

  test('routes an activity to the dated journal file', () async {
    await store.ensureSkeleton();

    final entry = await store.appendActivity(
      message: 'shipped the installer',
      tags: const ['release'],
    );
    final file = File(
      p.join(store.journalDirectory.path, '2026', '2026-08-31.md'),
    );

    expect(entry.at, clock);
    expect(file.existsSync(), isTrue);
    expect(
      await file.readAsString(),
      '# Journal 2026-08-31\n'
      '\n'
      '## 12:30:45 activity [release]\n'
      '\n'
      'shipped the installer\n',
    );
  });

  test('preserves earlier bytes when appending to the same day', () async {
    await store.ensureSkeleton();
    await store.appendActivity(message: 'first entry');
    await store.appendNote(message: 'second entry', tags: const ['a', 'b']);

    final contents = await File(
      p.join(store.journalDirectory.path, '2026', '2026-08-31.md'),
    ).readAsString();

    expect(contents, contains('first entry'));
    expect(contents, contains('second entry'));
    expect(contents, contains('## 12:30:45 note [a,b]'));
    expect(
      contents.indexOf('first entry'),
      lessThan(
        contents.indexOf('second entry'),
      ),
    );
  });

  test('leaves no temporary residue on disk', () async {
    await store.ensureSkeleton();
    await store.appendActivity(message: 'first entry');
    await store.writeNote(title: 'A Title', body: 'body');

    final residue = store.directory
        .listSync(recursive: true)
        .where((entity) => entity.path.endsWith('.tmp'));

    expect(residue, isEmpty);
  });

  test('writes a dated, slugged note exactly once', () async {
    await store.ensureSkeleton();

    final note = await store.writeNote(
      title: 'Atomic Registry Writes!',
      body: 'Stage then rename.',
      tags: const ['storage'],
    );

    expect(note.slug, '2026-08-31-atomic-registry-writes');
    final file = File(p.join(store.notesDirectory.path, '${note.slug}.md'));
    expect(await file.readAsString(), contains('# Atomic Registry Writes!'));
    expect(await file.readAsString(), contains('Stage then rename.'));

    await expectLater(
      store.writeNote(title: 'Atomic Registry Writes!', body: 'other'),
      throwsA(isA<MemoryException>()),
    );
    expect(await file.readAsString(), contains('Stage then rename.'));
  });

  test('lists durable notes without metadata in the body', () async {
    await store.ensureSkeleton();
    await store.writeNote(
      title: 'Runtime Decision',
      body: 'Tasks are canonical.',
      tags: const ['runtime'],
    );

    final notes = await store.listNotes();

    expect(notes.single.slug, '2026-08-31-runtime-decision');
    expect(notes.single.title, 'Runtime Decision');
    expect(notes.single.body, 'Tasks are canonical.');
    expect(notes.single.tags, ['runtime']);
  });

  test('rejects a title that cannot become a slug', () async {
    await store.ensureSkeleton();

    await expectLater(
      store.writeNote(title: '///', body: 'body'),
      throwsA(isA<MemoryException>()),
    );
  });

  test('filters and limits journal entries by date', () async {
    await store.ensureSkeleton();
    await store.appendActivity(
      message: 'old work',
      at: DateTime(2026, 8, 1, 9),
    );
    await store.appendActivity(
      message: 'recent work',
      at: DateTime(2026, 8, 30, 9),
    );
    await store.appendActivity(
      message: 'newest work',
      at: DateTime(2026, 8, 31, 9),
    );

    final all = await store.listActivities();
    final recent = await store.listActivities(
      since: DateTime(2026, 8, 15),
    );
    final limited = await store.listActivities(limit: 1);

    expect(all.map((entry) => entry.message), [
      'newest work',
      'recent work',
      'old work',
    ]);
    expect(recent.map((entry) => entry.message), [
      'newest work',
      'recent work',
    ]);
    expect(limited.map((entry) => entry.message), ['newest work']);
  });

  test('groups the digest by day and marks truncation', () async {
    await store.ensureSkeleton();
    await store.appendActivity(
      message: 'first day work',
      at: DateTime(2026, 8, 30, 9),
    );
    await store.appendActivity(
      message: 'second day work',
      at: DateTime(2026, 8, 31, 9),
    );

    final digest = await store.digest();
    final truncated = await store.digest(maxChars: 20);

    expect(digest, contains('## 2026-08-31'));
    expect(digest, contains('- 09:00 activity: second day work'));
    expect(digest, contains('## 2026-08-30'));
    expect(
      digest.indexOf('2026-08-31'),
      lessThan(
        digest.indexOf('2026-08-30'),
      ),
    );
    expect(truncated, endsWith('\n… (truncated)'));
    expect(truncated.length, 20 + '\n… (truncated)'.length);
  });

  test('returns an empty digest when nothing was recorded', () async {
    await store.ensureSkeleton();

    expect(await store.digest(), isEmpty);
  });

  test('regenerates the index with notes and journal days', () async {
    await store.ensureSkeleton();
    await store.appendActivity(message: 'work');
    await store.writeNote(title: 'Decision Y', body: 'because');

    final index = await store.indexFile.readAsString();

    expect(index, contains('## Notes'));
    expect(index, contains('`notes/2026-08-31-decision-y.md` — Decision Y'));
    expect(index, contains('## Journal'));
    expect(index, contains('`journal/2026/2026-08-31.md`'));
  });

  test('loads notes and journal files as searchable documents', () async {
    await store.ensureSkeleton();
    await store.appendActivity(message: 'work');
    await store.writeNote(title: 'Decision Y', body: 'because');

    final documents = await store.loadAll();

    expect(documents.map((document) => document.path), [
      'journal/2026/2026-08-31.md',
      'notes/2026-08-31-decision-y.md',
    ]);
    expect(documents.first.kind, MemoryEntryKind.activity);
    expect(documents.last.kind, MemoryEntryKind.note);
    expect(documents.last.title, 'Decision Y');
    expect(documents.last.at, DateTime(2026, 8, 31));
  });

  test('rejects an empty entry', () async {
    await store.ensureSkeleton();

    await expectLater(
      store.appendActivity(message: '   '),
      throwsA(isA<MemoryException>()),
    );
  });

  // Cutoff used across compactJournal tests: July 15 has no default values for
  // month or day (avoids the avoid_redundant_argument_values lint).
  final cutoff = DateTime(2026, 7, 15);

  group('compactJournal', () {
    test('reports nothing to archive when the journal is empty', () async {
      await store.ensureSkeleton();

      final report = await store.compactJournal(olderThan: cutoff);

      expect(report.archivedDays, 0);
      expect(report.archivedEntries, 0);
      expect(report.notePath, isNull);
    });

    test('archives only day-files older than the cutoff', () async {
      await store.ensureSkeleton();
      await store.appendActivity(
        message: 'old work',
        at: DateTime(2026, 1, 5, 9),
      );
      await store.appendActivity(
        message: 'still recent',
        at: DateTime(2026, 8, 31, 9),
      );

      final report = await store.compactJournal(olderThan: cutoff);

      expect(report.archivedDays, 1);
      expect(report.archivedEntries, 1);
      expect(report.notePath, isNotNull);

      final activities = await store.listActivities();
      expect(activities.map((entry) => entry.message), ['still recent']);
      expect(
        File(
          p.join(store.journalDirectory.path, '2026', '2026-01-05.md'),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(
          p.join(
            store.journalArchiveDirectory.path,
            '2026',
            '2026-01-05.md',
          ),
        ).existsSync(),
        isTrue,
      );
    });

    test('folds archived entries into one durable summary note', () async {
      await store.ensureSkeleton();
      await store.appendActivity(
        message: 'shipped the installer',
        tags: const ['release'],
        at: DateTime(2026, 1, 5, 9),
      );
      await store.appendNote(
        message: 'decided on atomic renames',
        at: DateTime(2026, 1, 6, 10, 30),
      );

      final report = await store.compactJournal(olderThan: cutoff);

      final notePath = report.notePath;
      if (notePath == null) fail('expected notePath to be non-null');
      final noteFile = File(p.join(store.directory.path, notePath));
      expect(noteFile.existsSync(), isTrue);
      final body = await noteFile.readAsString();
      expect(body, contains('# Journal summary 2026-01-05 to 2026-01-06'));
      expect(body, contains('## 2026-01-05'));
      expect(
        body,
        contains(
          '- 09:00 activity: shipped the installer [release]',
        ),
      );
      expect(body, contains('## 2026-01-06'));
      expect(
        body,
        contains('- 10:30 note: decided on atomic renames'),
      );
    });

    test('changes nothing on disk in dry-run mode', () async {
      await store.ensureSkeleton();
      await store.appendActivity(
        message: 'old work',
        at: DateTime(2026, 1, 5, 9),
      );

      final report = await store.compactJournal(
        olderThan: cutoff,
        dryRun: true,
      );

      expect(report.archivedDays, 1);
      expect(report.archivedEntries, 1);
      expect(report.notePath, isNotNull);
      expect(
        File(
          p.join(store.journalDirectory.path, '2026', '2026-01-05.md'),
        ).existsSync(),
        isTrue,
      );
      expect(store.journalArchiveDirectory.existsSync(), isFalse);
      final notePath = report.notePath;
      if (notePath == null) fail('expected notePath to be non-null');
      expect(
        File(p.join(store.directory.path, notePath)).existsSync(),
        isFalse,
      );
    });

    test(
      'never overwrites an existing summary note with the same name',
      () async {
        await store.ensureSkeleton();
        await store.appendActivity(
          message: 'first batch',
          at: DateTime(2026, 1, 5, 9),
        );
        await store.compactJournal(olderThan: cutoff);

        await store.appendActivity(
          message: 'second batch',
          at: DateTime(2026, 1, 5, 10),
        );
        final second = await store.compactJournal(olderThan: cutoff);

        final notes = store.notesDirectory
            .listSync()
            .map((entity) => p.basename(entity.path))
            .toList();
        expect(notes, hasLength(2));
        expect(second.notePath, isNotNull);
        expect(second.notePath, endsWith('-1.md'));
      },
    );

    test('excludes archived journal files from search and digest', () async {
      await store.ensureSkeleton();
      await store.appendActivity(
        message: 'old work',
        at: DateTime(2026, 1, 5, 9),
      );
      await store.compactJournal(olderThan: cutoff);

      final documents = await store.loadAll();
      expect(
        documents.any((document) => document.path.contains('.archive')),
        isFalse,
      );
      expect(await store.digest(), isNot(contains('old work')));
    });
  });
}
