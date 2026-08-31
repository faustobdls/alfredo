import 'dart:io';

import 'package:alfredo_cli/src/memory/embeddings_client.dart';
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
    for (final root in [notesDirectory, journalDirectory]) {
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
            kind: root == notesDirectory
                ? MemoryEntryKind.note
                : MemoryEntryKind.activity,
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
  Future<List<MemorySearchHit>> search(
    String query, {
    int limit = 8,
    bool keywordOnly = false,
    EmbeddingsClient? embeddings,
  }) async {
    final documents = await loadAll();
    if (keywordOnly || embeddings == null) {
      return keywordSearch(documents, query, limit: limit);
    }
    try {
      final index = await EmbeddingIndexStore(file: embeddingIndexFile).read();
      if (index != null) {
        final hits = await embeddingSearch(
          client: embeddings,
          index: index,
          documents: documents,
          query: query,
          limit: limit,
        );
        if (hits.isNotEmpty) return hits;
      }
    } on Exception {
      return keywordSearch(documents, query, limit: limit);
    }
    return keywordSearch(documents, query, limit: limit);
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
}
