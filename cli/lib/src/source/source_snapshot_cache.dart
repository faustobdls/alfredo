import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:alfredo_cli/src/source/source_models.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A verified, immutable local materialization of a remote source.
class SourceSnapshot {
  /// Creates an immutable source snapshot.
  const SourceSnapshot({
    required this.cacheKey,
    required this.root,
    required this.transport,
  });

  /// Content-addressed cache key.
  final String cacheKey;

  /// Root directory that contains `alfredo-source.yaml`.
  final String root;

  /// Immutable origin metadata.
  final SourceTransport transport;
}

/// Materializes Git and archive sources into a content-addressed local cache.
///
/// A snapshot is only published after its content and `.complete` marker are
/// written in a staging directory. The final directory rename makes readers
/// observe either a complete snapshot or no snapshot at all.
class SourceSnapshotCache {
  /// Creates a cache rooted at [directory].
  SourceSnapshotCache({required this.directory});

  /// Directory that owns all immutable snapshots.
  final Directory directory;

  /// Resolves [revision] to a commit and materializes that commit once.
  Future<SourceSnapshot> fetchGit({
    required Uri url,
    required String revision,
  }) async {
    _validateGitUri(url);
    _validateRevision(revision);
    final requestedCommit = revision.toLowerCase();
    if (_commitPattern.hasMatch(requestedCommit)) {
      final cachedTransport = SourceTransport(
        kind: SourceKind.git,
        url: url.toString(),
        revision: revision,
        resolvedRevision: requestedCommit,
      );
      final cached = await _openCached(
        SourceKind.git,
        _sha256('$url\n$requestedCommit'),
        cachedTransport,
        repairInvalid: true,
      );
      if (cached != null) return cached;
    }
    final resolvedRevision = await _resolveGitRevision(url, revision);
    final transport = SourceTransport(
      kind: SourceKind.git,
      url: url.toString(),
      revision: revision,
      resolvedRevision: resolvedRevision,
    );
    final cacheKey = _sha256('$url\n$resolvedRevision');
    return _publish(
      kind: SourceKind.git,
      cacheKey: cacheKey,
      transport: transport,
      build: (stage) async {
        final content = Directory(p.join(stage.path, 'content'));
        await _runGit([
          'clone',
          '--no-checkout',
          '--',
          url.toString(),
          content.path,
        ]);
        await _runGit([
          '-C',
          content.path,
          'checkout',
          '--detach',
          resolvedRevision,
        ]);
        final metadata = Directory(p.join(content.path, '.git'));
        if (metadata.existsSync()) {
          await metadata.delete(recursive: true);
        }
        return 'content';
      },
    );
  }

  /// Verifies and extracts a checksum-pinned archive exactly once.
  Future<SourceSnapshot> fetchArchive({
    required Uri url,
    required String sha256,
  }) async {
    _validateArchiveUri(url);
    final digest = _normalizeSha256(sha256);
    final transport = SourceTransport(
      kind: SourceKind.archive,
      url: url.toString(),
      sha256: digest,
    );
    return _publish(
      kind: SourceKind.archive,
      cacheKey: digest,
      transport: transport,
      build: (stage) async {
        final archiveBytes = await _readArchive(url);
        final actual = _sha256Bytes(archiveBytes);
        if (actual != digest) {
          throw SourceException(
            'Archive checksum mismatch: expected $digest, got $actual.',
          );
        }
        final extraction = Directory(p.join(stage.path, 'extract'));
        await extraction.create(recursive: true);
        await _extractArchive(archiveBytes, extraction);
        final root = await _findSourceRoot(extraction);
        return p.posix.joinAll(
          p.split(p.relative(root.path, from: stage.path)),
        );
      },
    );
  }

  Future<SourceSnapshot> _publish({
    required SourceKind kind,
    required String cacheKey,
    required SourceTransport transport,
    required Future<String> Function(Directory stage) build,
  }) async {
    final cached = await _openCached(
      kind,
      cacheKey,
      transport,
      repairInvalid: true,
    );
    if (cached != null) return cached;

    final kindDirectory = Directory(p.join(directory.path, kind.name));
    final stagingDirectory = Directory(p.join(kindDirectory.path, '.staging'));
    await stagingDirectory.create(recursive: true);
    // Keep this segment short: on Windows the staging tree hosts a full Git
    // checkout, and a cacheKey-prefixed name pushes deep paths past MAX_PATH.
    final stage = Directory(
      p.join(stagingDirectory.path, _nonce()),
    );
    final target = Directory(p.join(kindDirectory.path, cacheKey));
    try {
      await stage.create();
      final root = _validateRelativeRoot(await build(stage));
      final digest = await _treeDigest(stage);
      await File(p.join(stage.path, '.complete')).writeAsString(
        '${jsonEncode({'version': 1, 'root': root, 'digest': digest})}\n',
        flush: true,
      );
      try {
        await stage.rename(target.path);
      } on FileSystemException {
        final winner = await _openCached(kind, cacheKey, transport);
        if (winner != null) return winner;
        rethrow;
      }
      try {
        await _protectSnapshot(target);
      } on SourceException {
        await _discardInvalidSnapshot(target);
        rethrow;
      }
      return SourceSnapshot(
        cacheKey: cacheKey,
        root: p.joinAll([target.path, ...p.posix.split(root)]),
        transport: transport,
      );
    } on SourceException {
      rethrow;
    } on FileSystemException catch (error) {
      throw SourceException('Cannot create source snapshot: ${error.message}');
    } finally {
      if (stage.existsSync()) {
        await _makeWritable(stage);
        await stage.delete(recursive: true);
      }
    }
  }

  Future<SourceSnapshot?> _openCached(
    SourceKind kind,
    String cacheKey,
    SourceTransport transport, {
    bool repairInvalid = false,
  }) async {
    final target = Directory(p.join(directory.path, kind.name, cacheKey));
    if (!target.existsSync()) return null;
    final marker = File(p.join(target.path, '.complete'));
    if (!marker.existsSync()) {
      if (repairInvalid) {
        await _discardInvalidSnapshot(target);
        return null;
      }
      throw SourceException('Source snapshot is incomplete: ${target.path}');
    }
    try {
      final document = jsonDecode(await marker.readAsString());
      if (document is! Map<String, dynamic> || document['version'] != 1) {
        throw const FormatException('invalid marker');
      }
      final root = _validateRelativeRoot(document['root']);
      final digest = document['digest'];
      if (digest is! String || !_sha256Pattern.hasMatch(digest)) {
        throw const FormatException('invalid digest');
      }
      final actualDigest = await _treeDigest(target);
      if (actualDigest != digest) {
        throw SourceException(
          'Source snapshot content changed: ${target.path}',
        );
      }
      final sourceRoot = Directory(
        p.joinAll([target.path, ...p.posix.split(root)]),
      );
      if (!sourceRoot.existsSync() ||
          !File(p.join(sourceRoot.path, 'alfredo-source.yaml')).existsSync()) {
        throw SourceException(
          'Source snapshot is invalid: ${target.path}',
        );
      }
      await _protectSnapshot(target);
      return SourceSnapshot(
        cacheKey: cacheKey,
        root: sourceRoot.path,
        transport: transport,
      );
    } on FormatException catch (_) {
      if (repairInvalid) {
        await _discardInvalidSnapshot(target);
        return null;
      }
      throw SourceException(
        'Source snapshot marker is invalid: ${target.path}',
      );
    } on SourceException {
      if (repairInvalid) {
        await _discardInvalidSnapshot(target);
        return null;
      }
      rethrow;
    }
  }

  Future<void> _discardInvalidSnapshot(Directory target) async {
    final quarantine = Directory('${target.path}.invalid-${_nonce()}');
    try {
      await _makeWritable(target);
      await target.rename(quarantine.path);
      await quarantine.delete(recursive: true);
    } on FileSystemException catch (error) {
      throw SourceException(
        'Cannot replace invalid source snapshot: ${error.message}',
      );
    }
  }

  static Future<String> _treeDigest(Directory root) async {
    final entities = await root
        .list(recursive: true, followLinks: false)
        .toList();
    if (entities.any((entity) => entity is Link)) {
      throw SourceException(
        'Source snapshot contains a symbolic link: ${root.path}',
      );
    }
    final files =
        entities
            .whereType<File>()
            .where(
              (file) =>
                  p.normalize(file.path) != p.join(root.path, '.complete'),
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    final bytes = BytesBuilder(copy: false);
    for (final file in files) {
      final relative = p.posix.joinAll(
        p.split(p.relative(file.path, from: root.path)),
      );
      bytes
        ..add(utf8.encode(relative))
        ..add(const [0])
        ..add(await file.readAsBytes())
        ..add(const [0]);
    }
    return _sha256Bytes(bytes.takeBytes());
  }

  static Future<void> _protectSnapshot(Directory directory) async {
    final result = Platform.isWindows
        ? await Process.run('attrib', [
            '+R',
            p.join(directory.path, '*'),
            '/S',
            '/D',
          ])
        : await Process.run('chmod', ['-R', 'a-w', directory.path]);
    if (result.exitCode != 0) {
      throw SourceException(
        'Cannot protect source snapshot: ${(result.stderr as String).trim()}',
      );
    }
  }

  static Future<void> _makeWritable(Directory directory) async {
    if (!directory.existsSync()) return;
    final result = Platform.isWindows
        ? await Process.run('attrib', [
            '-R',
            p.join(directory.path, '*'),
            '/S',
            '/D',
          ])
        : await Process.run('chmod', ['-R', 'u+w', directory.path]);
    if (result.exitCode != 0) {
      throw SourceException(
        'Cannot repair source snapshot: ${(result.stderr as String).trim()}',
      );
    }
  }

  Future<String> _resolveGitRevision(Uri url, String revision) async {
    final result = await _runGit([
      'ls-remote',
      '--quiet',
      '--',
      url.toString(),
    ]);
    final lines = (result.stdout as String)
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    final candidates = lines
        .map((line) => line.split(RegExp(r'\s+')))
        .where((parts) => parts.length == 2)
        .where(
          (parts) =>
              parts[1] == revision ||
              parts[1] == 'refs/heads/$revision' ||
              parts[1] == 'refs/tags/$revision^{}' ||
              parts[1] == 'refs/tags/$revision' ||
              (_commitPattern.hasMatch(revision.toLowerCase()) &&
                  parts[0] == revision.toLowerCase()),
        )
        .toList();
    if (revision == 'HEAD') {
      candidates.addAll(
        lines
            .map((line) => line.split(RegExp(r'\s+')))
            .where((parts) => parts.length == 2 && parts[1] == 'HEAD'),
      );
    }
    if (candidates.isEmpty) {
      throw SourceException('Git revision was not found: $revision');
    }
    final peeled = candidates.where((parts) => parts[1].endsWith('^{}'));
    final commit = (peeled.isNotEmpty ? peeled.first : candidates.first).first;
    if (!_commitPattern.hasMatch(commit)) {
      throw SourceException(
        'Git revision did not resolve to a commit: $revision',
      );
    }
    return commit;
  }

  Future<ProcessResult> _runGit(List<String> arguments) async {
    // core.longpaths lets Git write paths beyond the Windows MAX_PATH limit,
    // independent of the OS-wide long path opt-in; it is a no-op elsewhere.
    final result = await Process.run('git', [
      '-c',
      'core.longpaths=true',
      ...arguments,
    ]);
    if (result.exitCode != 0) {
      final error = (result.stderr as String).trim();
      throw SourceException(
        'Git command failed: ${error.isEmpty ? arguments.first : error}',
      );
    }
    return result;
  }

  Future<Uint8List> _readArchive(Uri url) async {
    if (url.scheme == 'file') {
      final file = File.fromUri(url);
      if (!file.existsSync()) {
        throw SourceException('Archive file does not exist: ${file.path}');
      }
      return file.readAsBytes();
    }
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw SourceException('Unsupported archive URL scheme: ${url.scheme}');
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(url);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw SourceException(
          'Cannot download archive: HTTP ${response.statusCode}',
        );
      }
      final bytes = await response.fold<List<int>>(<int>[], (value, chunk) {
        value.addAll(chunk);
        return value;
      });
      return Uint8List.fromList(bytes);
    } on SocketException catch (error) {
      throw SourceException('Cannot download archive: ${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _extractArchive(
    List<int> bytes,
    Directory destination,
  ) async {
    Archive archive;
    try {
      if (_isZip(bytes)) {
        archive = ZipDecoder().decodeBytes(bytes, verify: true);
      } else if (_isGzip(bytes)) {
        archive = TarDecoder().decodeBytes(
          const GZipDecoder().decodeBytes(bytes),
        );
      } else {
        archive = TarDecoder().decodeBytes(bytes);
      }
    } on Object catch (error) {
      throw SourceException('Cannot decode archive: $error');
    }
    if (archive.isEmpty) throw const SourceException('Archive is empty.');

    for (final entry in archive) {
      final entryPath = _validateArchiveEntryPath(entry.name);
      if (entryPath == null) continue;
      if (entry.isSymbolicLink) {
        throw SourceException(
          'Archive symbolic links are not supported: $entryPath',
        );
      }
      final output = File(
        p.joinAll([destination.path, ...p.posix.split(entryPath)]),
      );
      if (entry.isDirectory) {
        await Directory(output.path).create(recursive: true);
      } else {
        await output.parent.create(recursive: true);
        await output.writeAsBytes(entry.content, flush: true);
      }
    }
  }

  Future<Directory> _findSourceRoot(Directory extraction) async {
    if (File(p.join(extraction.path, 'alfredo-source.yaml')).existsSync()) {
      return extraction;
    }
    final children = await extraction.list().toList();
    final candidates = children
        .whereType<Directory>()
        .where(
          (directory) =>
              File(p.join(directory.path, 'alfredo-source.yaml')).existsSync(),
        )
        .toList();
    if (candidates.length != 1) {
      throw const SourceException(
        'Archive must contain one top-level alfredo-source.yaml.',
      );
    }
    return candidates.single;
  }

  static String? _validateArchiveEntryPath(String path) {
    if (path.isEmpty || path == '.' || path == './') return null;
    if (path.contains(_backslash) ||
        path.contains(_nullCharacter) ||
        path.startsWith('/') ||
        RegExp('^[A-Za-z]:').hasMatch(path)) {
      throw SourceException('Archive entry has an unsafe path: $path');
    }
    final segments = path.split('/');
    if (segments.any((segment) => segment == '..')) {
      throw SourceException('Archive entry has an unsafe path: $path');
    }
    final normalized = p.posix.normalize(path);
    if (normalized == '.' || normalized.startsWith('../')) {
      throw SourceException('Archive entry has an unsafe path: $path');
    }
    return normalized;
  }

  static String _validateRelativeRoot(Object? value) {
    if (value is! String ||
        value.isEmpty ||
        value.contains(_backslash) ||
        value.startsWith('/') ||
        value.split('/').contains('..')) {
      throw const SourceException('Source snapshot has an invalid root.');
    }
    return value;
  }

  static void _validateGitUri(Uri url) {
    const allowedSchemes = {'file', 'http', 'https', 'ssh', 'git'};
    if (!allowedSchemes.contains(url.scheme.toLowerCase())) {
      final scheme = url.scheme.isEmpty ? '(none)' : url.scheme;
      throw SourceException(
        'Unsupported Git URL scheme: $scheme',
      );
    }
  }

  static void _validateArchiveUri(Uri url) {
    if (url.scheme != 'file' && url.scheme != 'http' && url.scheme != 'https') {
      throw SourceException('Unsupported archive URL scheme: ${url.scheme}');
    }
  }

  static void _validateRevision(String revision) {
    if (revision.isEmpty ||
        revision.length > 256 ||
        revision.startsWith('-') ||
        RegExp(r'\s').hasMatch(revision)) {
      throw SourceException('Invalid Git revision: $revision');
    }
  }

  static String _normalizeSha256(String value) {
    final digest = value.toLowerCase();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const SourceException(
        'Archive SHA-256 must be 64 hexadecimal characters.',
      );
    }
    return digest;
  }

  static String _sha256(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static String _sha256Bytes(List<int> bytes) =>
      sha256.convert(bytes).toString();

  static bool _isZip(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      bytes[2] >= 0x03 &&
      bytes[2] <= 0x07;

  static bool _isGzip(List<int> bytes) =>
      bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;

  static String _nonce() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final random = Random.secure().nextInt(1 << 32);
    return '$pid-$timestamp-$random';
  }

  static final _backslash = String.fromCharCode(0x5c);
  static final _nullCharacter = String.fromCharCode(0);
  static final _commitPattern = RegExp(r'^[a-f0-9]{40}$');
  static final _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
}
