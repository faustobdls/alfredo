import 'dart:io';
import 'dart:math' as math;

import 'package:alfredo_cli/src/memory/embeddings_client.dart';
import 'package:alfredo_cli/src/memory/hybrid_search.dart';
import 'package:alfredo_cli/src/memory/keyword_search.dart';
import 'package:alfredo_cli/src/memory/memory_config_store.dart';
import 'package:alfredo_cli/src/memory/memory_models.dart';
import 'package:alfredo_cli/src/memory/memory_paths.dart';
import 'package:alfredo_cli/src/memory/vector_index.dart';
import 'package:path/path.dart' as p;

/// Supplies the current instant, so journal writes stay testable.
typedef Clock = DateTime Function();

final _headingPattern = RegExp(
  r'^## (\d{2}):(\d{2}):(\d{2}) ([a-z]+) \[([^\]]*)\]$',
);
final _slugPattern = RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$');

/// An append-only journal, a durable note collection, and their derived index.
///
/// Only `MEMORY.md` is ever regenerated. Journal files are extended by
/// concatenation and note files are never overwritten.
class MemoryStore {
  /// Creates a store rooted at [directory].
  MemoryStore({required this.directory, Clock? now})
    : _now = now ?? DateTime.now;

  /// Root of this memory scope.
  final Directory directory;

  final Clock _now;

  /// Durable configuration file.
  File get configFile => memoryConfigFile(directory);

  /// Derived, always-regenerated index file.
  File get indexFile => File(p.join(directory.path, 'MEMORY.md'));

  /// Append-only journal root.
  Directory get journalDirectory =>
      Directory(p.join(directory.path, 'journal'));

  /// Durable note root.
  Directory get notesDirectory => Directory(p.join(directory.path, 'notes'));

  /// Hidden archive of journal day-files folded into a compaction summary.
  ///
  /// Files here are moved, never deleted, so the raw history stays on disk
  /// for audit; the leading dot excludes them from [loadAll], search, and
  /// [listActivities]/[digest], the same convention [isExcludedMemoryPath]
  /// already applies to any hidden directory.
  Directory get journalArchiveDirectory =>
      Directory(p.join(journalDirectory.path, '.archive'));

  /// Generated artifact root.
  Directory get generatedDirectory =>
      Directory(p.join(directory.path, 'index'));

  /// Persisted embedding index file.
  File get embeddingIndexFile =>
      File(p.join(generatedDirectory.path, 'embeddings.json'));

  /// Creates every directory and seeds the configuration and derived index.
  Future<void> ensureSkeleton() async {
    await directory.create(recursive: true);
    await journalDirectory.create(recursive: true);
    await notesDirectory.create(recursive: true);
    await generatedDirectory.create(recursive: true);
    if (!configFile.existsSync()) {
      await writeConfig(const MemoryConfig.defaults());
    }
    await regenerateIndexFile();
  }

  /// Reads the configuration, falling back to defaults when it is missing.
  Future<MemoryConfig> readConfig() =>
      MemoryConfigStore(file: configFile).readOrDefault();

  /// Atomically persists [config].
  Future<void> writeConfig(MemoryConfig config) =>
      MemoryConfigStore(file: configFile).write(config);

  /// Appends a time-bound activity entry to today's journal file.
  Future<MemoryEntry> appendActivity({
    required String message,
    List<String> tags = const [],
    DateTime? at,
  }) => _append(MemoryEntryKind.activity, message, tags, at);

  /// Appends a note-shaped entry to today's journal file.
  Future<MemoryEntry> appendNote({
    required String message,
    List<String> tags = const [],
    DateTime? at,
  }) => _append(MemoryEntryKind.note, message, tags, at);

  /// Writes one durable fact, refusing to overwrite an existing note.
  Future<MemoryNote> writeNote({
    required String title,
    required String body,
    List<String> tags = const [],
    DateTime? at,
  }) async {
    final moment = at ?? _now();
    final slug = '${_formatDate(moment)}-${_slugify(title)}';
    final file = File(p.join(notesDirectory.path, '$slug.md'));
    if (file.existsSync()) {
      throw MemoryException('Note already exists: $slug');
    }
    final tagLine = tags.isEmpty ? '' : 'tags: ${tags.join(', ')}\n';
    await _writeAtomically(
      file,
      '# $title\n\n'
      'date: ${_formatDate(moment)}\n'
      '$tagLine'
      '\n'
      '${body.trim()}\n',
    );
    await regenerateIndexFile();
    return MemoryNote(
      slug: slug,
      title: title,
      body: body.trim(),
      at: moment,
      tags: List.unmodifiable(tags),
    );
  }

  /// Loads every searchable note and journal file.
  Future<List<MemoryDocument>> loadAll() async {
    final documents = <MemoryDocument>[];
    final roots = <MemoryEntryKind, Directory>{
      MemoryEntryKind.note: notesDirectory,
      MemoryEntryKind.activity: journalDirectory,
    };
    for (final entry in roots.entries) {
      final root = entry.value;
      if (!root.existsSync()) continue;
      final files =
          (await root.list(recursive: true, followLinks: false).toList())
              .whereType<File>()
              .where((file) => p.extension(file.path) == '.md')
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      for (final file in files) {
        final relative = p.posix.joinAll(
          p.split(p.relative(file.path, from: directory.path)),
        );
        if (isExcludedMemoryPath(relative)) continue;
        final text = await file.readAsString();
        documents.add(
          MemoryDocument(
            path: relative,
            kind: entry.key,
            title: _title(text, p.basenameWithoutExtension(file.path)),
            text: text,
            at: _dateFromName(p.basenameWithoutExtension(file.path)),
          ),
        );
      }
    }
    documents.sort((left, right) => left.path.compareTo(right.path));
    return List.unmodifiable(documents);
  }

  /// Returns journal entries newest first, optionally filtered and truncated.
  Future<List<MemoryEntry>> listActivities({
    DateTime? since,
    int? limit,
  }) async {
    final entries = await _readJournal();
    final filtered = [
      for (final entry in entries)
        if (since == null || !entry.at.isBefore(since)) entry,
    ]..sort((left, right) => right.at.compareTo(left.at));
    if (limit == null || limit >= filtered.length) {
      return List.unmodifiable(filtered);
    }
    return List.unmodifiable(filtered.take(limit < 0 ? 0 : limit));
  }

  /// Returns durable notes newest first, optionally filtered and truncated.
  Future<List<MemoryNote>> listNotes({DateTime? since, int? limit}) async {
    final documents = await loadAll();
    final notes =
        [
            for (final document in documents)
              if (document.kind == MemoryEntryKind.note)
                MemoryNote(
                  slug: p.basenameWithoutExtension(document.path),
                  title: document.title,
                  body: _noteBody(document.text),
                  at: document.at ?? DateTime.fromMillisecondsSinceEpoch(0),
                  tags: _noteTags(document.text),
                ),
          ].where((note) => since == null || !note.at.isBefore(since)).toList()
          ..sort((left, right) => right.at.compareTo(left.at));
    if (limit == null || limit >= notes.length) {
      return List.unmodifiable(notes);
    }
    return List.unmodifiable(notes.take(limit < 0 ? 0 : limit));
  }

  /// Renders a compact, day-grouped summary bounded by [maxChars].
  Future<String> digest({DateTime? since, int maxChars = 2000}) async {
    final entries = await listActivities(since: since);
    if (entries.isEmpty) return '';
    final byDay = <String, List<MemoryEntry>>{};
    for (final entry in entries) {
      (byDay[_formatDate(entry.at)] ??= []).add(entry);
    }
    final days = byDay.keys.toList()
      ..sort((left, right) => right.compareTo(left));
    final buffer = StringBuffer();
    for (final day in days) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('## $day');
      for (final entry in byDay[day]!) {
        final tags = entry.tags.isEmpty ? '' : ' [${entry.tags.join(',')}]';
        buffer.writeln(
          '- ${_formatTime(entry.at, seconds: false)} ${entry.kind.name}: '
          '${_singleLine(entry.message)}$tags',
        );
      }
    }
    final digest = buffer.toString().trimRight();
    if (maxChars <= 0 || digest.length <= maxChars) return digest;
    return '${digest.substring(0, maxChars)}\n… (truncated)';
  }

  /// Ranks memory documents against [query], never failing on a provider error.
  ///
  /// [vectorWeight] tunes the blend between lexical and vector ranking: `0`
  /// is keyword-only, `1` is vector-only (falling back to keyword when no
  /// index or provider is available, as before), and any value in between
  /// linearly blends both rankings via [combineHybridHits]. It is clamped
  /// to `[0, 1]` and ignored when [keywordOnly] is set or no [embeddings]
  /// client is supplied.
  Future<List<MemorySearchHit>> search(
    String query, {
    int limit = 8,
    bool keywordOnly = false,
    EmbeddingsClient? embeddings,
    double vectorWeight = 1,
  }) async {
    final documents = await loadAll();
    if (keywordOnly || embeddings == null) {
      return keywordSearch(documents, query, limit: limit);
    }
    final weight = vectorWeight.clamp(0.0, 1.0);
    if (weight <= 0) {
      return keywordSearch(documents, query, limit: limit);
    }
    // Pull a wider candidate pool than requested so blending has enough
    // documents from each ranking to compare before the final trim.
    final poolLimit = math.max(limit, 20);
    try {
      final index = await EmbeddingIndexStore(file: embeddingIndexFile).read();
      if (index != null) {
        final vectorHits = await embeddingSearch(
          client: embeddings,
          index: index,
          documents: documents,
          query: query,
          limit: poolLimit,
        );
        if (vectorHits.isNotEmpty) {
          if (weight >= 1) {
            return List.unmodifiable(vectorHits.take(limit.clamp(1, 20)));
          }
          final keywordHits = keywordSearch(
            documents,
            query,
            limit: poolLimit,
          );
          return combineHybridHits(
            keywordHits: keywordHits,
            vectorHits: vectorHits,
            vectorWeight: weight,
            limit: limit,
          );
        }
      }
    } on Exception {
      return keywordSearch(documents, query, limit: limit);
    }
    return keywordSearch(documents, query, limit: limit);
  }

  /// Consolidates journal entries older than [olderThan] into one durable
  /// summary note and archives the source day-files.
  ///
  /// The journal stays append-only in spirit: day-files are never deleted,
  /// only moved under [journalArchiveDirectory] (a hidden directory that
  /// [loadAll], search, [listActivities], and [digest] all skip). Their
  /// content is folded, oldest first, into one note under [notesDirectory]
  /// so long-lived history keeps costing near-zero context instead of
  /// growing the searchable journal without bound.
  ///
  /// Pass `dryRun: true` to preview the counts and note path without
  /// touching disk. Returns a report with `archivedDays: 0` when nothing is
  /// older than [olderThan].
  Future<MemoryCompactReport> compactJournal({
    required DateTime olderThan,
    bool dryRun = false,
  }) async {
    if (!journalDirectory.existsSync()) {
      return const MemoryCompactReport(
        archivedDays: 0,
        archivedEntries: 0,
        notePath: null,
      );
    }
    final cutoff = DateTime(olderThan.year, olderThan.month, olderThan.day);
    final files =
        (await journalDirectory
                .list(recursive: true, followLinks: false)
                .toList())
            .whereType<File>()
            .where((file) => p.extension(file.path) == '.md')
            .where(
              (file) => !p
                  .split(p.relative(file.path, from: journalDirectory.path))
                  .any((segment) => segment.startsWith('.')),
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));

    final toArchive = <File>[];
    final entries = <MemoryEntry>[];
    for (final file in files) {
      final day = _dateFromName(p.basenameWithoutExtension(file.path));
      if (day == null || !day.isBefore(cutoff)) continue;
      toArchive.add(file);
      entries.addAll(_parseJournal(day, await file.readAsString()));
    }

    if (toArchive.isEmpty) {
      return const MemoryCompactReport(
        archivedDays: 0,
        archivedEntries: 0,
        notePath: null,
      );
    }
    entries.sort((left, right) => left.at.compareTo(right.at));

    final moment = _now();
    final firstDay = _formatDate(entries.first.at);
    final lastDay = _formatDate(entries.last.at);
    final title = 'Journal summary $firstDay to $lastDay';
    final baseSlug =
        '${_formatDate(moment)}-journal-summary-$firstDay-to-$lastDay';
    var noteFile = File(p.join(notesDirectory.path, '$baseSlug.md'));
    if (dryRun) {
      return MemoryCompactReport(
        archivedDays: toArchive.length,
        archivedEntries: entries.length,
        notePath: p.posix.joinAll(
          p.split(p.relative(noteFile.path, from: directory.path)),
        ),
      );
    }

    var suffix = 0;
    while (noteFile.existsSync()) {
      suffix++;
      noteFile = File(p.join(notesDirectory.path, '$baseSlug-$suffix.md'));
    }
    await _writeAtomically(
      noteFile,
      '# $title\n\n'
      'date: ${_formatDate(moment)}\n'
      'tags: compaction, journal-summary\n'
      '\n'
      '${_renderCompactSummary(entries)}\n',
    );

    for (final file in toArchive) {
      final relative = p.relative(file.path, from: journalDirectory.path);
      final archived = File(p.join(journalArchiveDirectory.path, relative));
      await archived.parent.create(recursive: true);
      await file.rename(archived.path);
    }
    await regenerateIndexFile();

    return MemoryCompactReport(
      archivedDays: toArchive.length,
      archivedEntries: entries.length,
      notePath: p.posix.joinAll(
        p.split(p.relative(noteFile.path, from: directory.path)),
      ),
    );
  }

  /// Embeds new or changed documents and prunes vectors for deleted files.
  Future<MemoryIndexReport> updateIndex(
    EmbeddingsClient client, {
    bool force = false,
  }) async {
    await generatedDirectory.create(recursive: true);
    return buildEmbeddingIndex(
      client: client,
      store: EmbeddingIndexStore(file: embeddingIndexFile),
      documents: await loadAll(),
      force: force,
    );
  }

  /// Rewrites `MEMORY.md`, the only derived file Alfredo ever overwrites.
  Future<void> regenerateIndexFile() async {
    final documents = await loadAll();
    final notes = documents.where(
      (document) => document.kind == MemoryEntryKind.note,
    );
    final journal = documents.where(
      (document) => document.kind == MemoryEntryKind.activity,
    );
    final buffer = StringBuffer()
      ..writeln('# Alfredo memory index')
      ..writeln()
      ..writeln(
        'Generated by `alfredo memory`. Every other file in this directory '
        'is append-only.',
      )
      ..writeln()
      ..writeln('## Notes')
      ..writeln();
    if (notes.isEmpty) {
      buffer.writeln('- (none)');
    } else {
      for (final note in notes) {
        buffer.writeln('- `${note.path}` — ${note.title}');
      }
    }
    buffer
      ..writeln()
      ..writeln('## Journal')
      ..writeln();
    if (journal.isEmpty) {
      buffer.writeln('- (none)');
    } else {
      for (final day in journal) {
        buffer.writeln('- `${day.path}`');
      }
    }
    await _writeAtomically(indexFile, buffer.toString());
  }

  Future<MemoryEntry> _append(
    MemoryEntryKind kind,
    String message,
    List<String> tags,
    DateTime? at,
  ) async {
    final body = message.trim();
    if (body.isEmpty) {
      throw const MemoryException('A memory entry cannot be empty.');
    }
    final moment = at ?? _now();
    final file = journalFileFor(moment);
    await file.parent.create(recursive: true);
    final existing = file.existsSync()
        ? await file.readAsString()
        : '# Journal ${_formatDate(moment)}\n';
    final heading =
        '## ${_formatTime(moment)} ${kind.name} [${tags.join(',')}]';
    await _writeAtomically(file, '$existing\n$heading\n\n$body\n');
    await regenerateIndexFile();
    return MemoryEntry(
      at: moment,
      kind: kind,
      tags: List.unmodifiable(tags),
      message: body,
    );
  }

  /// Resolves the append-only journal file that owns [moment].
  File journalFileFor(DateTime moment) => File(
    p.join(
      journalDirectory.path,
      moment.year.toString().padLeft(4, '0'),
      '${_formatDate(moment)}.md',
    ),
  );

  Future<List<MemoryEntry>> _readJournal() async {
    if (!journalDirectory.existsSync()) return const [];
    final files =
        (await journalDirectory
                .list(recursive: true, followLinks: false)
                .toList())
            .whereType<File>()
            .where((file) => p.extension(file.path) == '.md')
            .where(
              (file) => !p
                  .split(p.relative(file.path, from: journalDirectory.path))
                  .any((segment) => segment.startsWith('.')),
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final entries = <MemoryEntry>[];
    for (final file in files) {
      final day = _dateFromName(p.basenameWithoutExtension(file.path));
      if (day == null) continue;
      entries.addAll(_parseJournal(day, await file.readAsString()));
    }
    return entries;
  }

  static List<MemoryEntry> _parseJournal(DateTime day, String text) {
    final entries = <MemoryEntry>[];
    final lines = text.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final match = _headingPattern.firstMatch(lines[index].trimRight());
      if (match == null) continue;
      final kind = switch (match[4]) {
        'note' => MemoryEntryKind.note,
        'activity' => MemoryEntryKind.activity,
        _ => null,
      };
      if (kind == null) continue;
      final body = <String>[];
      for (var cursor = index + 1; cursor < lines.length; cursor++) {
        if (lines[cursor].startsWith('## ')) break;
        body.add(lines[cursor]);
      }
      final tags = match[5]!
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
      entries.add(
        MemoryEntry(
          at: DateTime(
            day.year,
            day.month,
            day.day,
            int.parse(match[1]!),
            int.parse(match[2]!),
            int.parse(match[3]!),
          ),
          kind: kind,
          tags: List.unmodifiable(tags),
          message: body.join('\n').trim(),
        ),
      );
    }
    return entries;
  }

  static String _noteBody(String text) {
    final lines = text.split('\n');
    if (lines.isEmpty) return '';
    var index = lines.first.startsWith('# ') ? 1 : 0;
    while (index < lines.length && lines[index].trim().isEmpty) {
      index++;
    }
    while (index < lines.length && lines[index].contains(':')) {
      index++;
    }
    while (index < lines.length && lines[index].trim().isEmpty) {
      index++;
    }
    return lines.skip(index).join('\n').trim();
  }

  static List<String> _noteTags(String text) {
    for (final line in text.split('\n')) {
      if (!line.startsWith('tags:')) continue;
      return line
          .substring('tags:'.length)
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList(growable: false);
    }
    return const [];
  }

  static Future<void> _writeAtomically(File file, String contents) async {
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final temporary = File('${file.path}.$pid.$nonce.tmp');
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsString(contents, flush: true);
      await temporary.rename(file.path);
    } on FileSystemException catch (error) {
      throw MemoryException('Cannot update ${file.path}: ${error.message}');
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
  }

  static String _slugify(String title) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (!_slugPattern.hasMatch(slug)) {
      throw MemoryException('Cannot derive a note slug from title: $title');
    }
    return slug;
  }

  static String _title(String text, String fallback) {
    for (final line in text.split('\n')) {
      if (line.startsWith('# ')) return line.substring(2).trim();
    }
    return fallback;
  }

  static DateTime? _dateFromName(String name) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(name);
    if (match == null) return null;
    return DateTime(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  static String _formatDate(DateTime moment) =>
      '${moment.year.toString().padLeft(4, '0')}-'
      '${moment.month.toString().padLeft(2, '0')}-'
      '${moment.day.toString().padLeft(2, '0')}';

  static String _formatTime(DateTime moment, {bool seconds = true}) {
    final base =
        '${moment.hour.toString().padLeft(2, '0')}:'
        '${moment.minute.toString().padLeft(2, '0')}';
    return seconds ? '$base:${moment.second.toString().padLeft(2, '0')}' : base;
  }

  static String _singleLine(String value) =>
      value.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).join(' ');

  /// Renders archived journal entries as one day-grouped Markdown body,
  /// reusing the same layout [digest] shows for a live window so a
  /// compacted note reads like a permanent digest of that period.
  static String _renderCompactSummary(List<MemoryEntry> entries) {
    final byDay = <String, List<MemoryEntry>>{};
    for (final entry in entries) {
      (byDay[_formatDate(entry.at)] ??= []).add(entry);
    }
    final days = byDay.keys.toList()..sort();
    final buffer = StringBuffer();
    for (final day in days) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('## $day');
      for (final entry in byDay[day]!) {
        final tags = entry.tags.isEmpty ? '' : ' [${entry.tags.join(',')}]';
        buffer.writeln(
          '- ${_formatTime(entry.at, seconds: false)} ${entry.kind.name}: '
          '${_singleLine(entry.message)}$tags',
        );
      }
    }
    return buffer.toString().trimRight();
  }
}
