import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/source/source.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../helpers/source_fixture.dart';

void main() {
  late Directory temporary;
  late SourceSnapshotCache cache;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-snapshot-');
    cache = SourceSnapshotCache(
      directory: Directory(p.join(temporary.path, 'cache')),
    );
  });

  tearDown(() async {
    if (Platform.isWindows) {
      await Process.run('attrib', [
        '-R',
        p.join(temporary.path, '*'),
        '/S',
        '/D',
      ]);
    } else {
      await Process.run('chmod', ['-R', 'u+w', temporary.path]);
    }
    await temporary.delete(recursive: true);
  });

  test('resolves a Git revision to a commit and reuses its snapshot', () async {
    final source = await createSourceFixture(temporary, sourceId: 'git-source');
    await _git(['init', source.path]);
    await _git(['-C', source.path, 'config', 'user.email', 'alfredo@test']);
    await _git(['-C', source.path, 'config', 'user.name', 'Alfredo Test']);
    await _git(['-C', source.path, 'add', '.']);
    await _git(['-C', source.path, 'commit', '-m', 'initial']);
    final commit = (await _git([
      '-C',
      source.path,
      'rev-parse',
      'HEAD',
    ])).trim();

    final first = await cache.fetchGit(url: source.uri, revision: commit);
    await source.delete(recursive: true);
    final second = await cache.fetchGit(url: source.uri, revision: commit);

    expect(first.cacheKey, second.cacheKey);
    expect(first.root, second.root);
    expect(first.transport.kind, SourceKind.git);
    expect(first.transport.revision, commit);
    expect(first.transport.resolvedRevision, commit);
    expect(
      File(p.join(first.root, 'alfredo-source.yaml')).existsSync(),
      isTrue,
    );
    expect(Directory(p.join(first.root, '.git')).existsSync(), isFalse);
    expect(
      File(
        p.join(cache.directory.path, 'git', first.cacheKey, '.complete'),
      ).existsSync(),
      isTrue,
    );
  });

  test(
    'materializes a checksum-pinned archive once and validates its source',
    () async {
      final source = await createSourceFixture(
        temporary,
        sourceId: 'archive-source',
      );
      final archive = await _makeZip(
        source,
        File(p.join(temporary.path, 'source.zip')),
      );
      final digest = sha256.convert(await archive.readAsBytes()).toString();

      final first = await cache.fetchArchive(url: archive.uri, sha256: digest);
      await archive.delete();
      final second = await cache.fetchArchive(url: archive.uri, sha256: digest);

      expect(first.cacheKey, digest);
      expect(second.root, first.root);
      expect(first.transport.kind, SourceKind.archive);
      expect(first.transport.sha256, digest);
      expect(
        (await const SourceManifestLoader().load(first.root)).id,
        'archive-source',
      );
    },
  );

  test('does not publish an archive with a mismatched checksum', () async {
    final source = await createSourceFixture(temporary);
    final archive = await _makeZip(
      source,
      File(p.join(temporary.path, 'source.zip')),
    );
    const incorrect =
        '0000000000000000000000000000000000000000000000000000000000000000';

    expect(
      () => cache.fetchArchive(url: archive.uri, sha256: incorrect),
      throwsA(isA<SourceException>()),
    );
    expect(
      Directory(
        p.join(cache.directory.path, 'archive', incorrect),
      ).existsSync(),
      isFalse,
    );
  });

  test('rejects archive path traversal before writing files', () async {
    final archive = Archive()
      ..add(ArchiveFile.string('../escape.txt', 'not allowed'));
    final file = File(p.join(temporary.path, 'traversal.zip'));
    await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
    final digest = sha256.convert(await file.readAsBytes()).toString();

    expect(
      () => cache.fetchArchive(url: file.uri, sha256: digest),
      throwsA(isA<SourceException>()),
    );
    expect(File(p.join(temporary.path, 'escape.txt')).existsSync(), isFalse);
  });

  test('rejects archive symbolic links, including escaping links', () async {
    final archive = Archive()
      ..add(ArchiveFile.symlink('source/link', '../../escape'));
    final file = File(p.join(temporary.path, 'link.tar'));
    await file.writeAsBytes(TarEncoder().encodeBytes(archive));
    final digest = sha256.convert(await file.readAsBytes()).toString();

    expect(
      () => cache.fetchArchive(url: file.uri, sha256: digest),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          contains('symbolic'),
        ),
      ),
    );
  });

  test('rejects Git transport helper schemes before invoking Git', () async {
    expect(
      () => cache.fetchGit(
        url: Uri.parse('ext::dangerous-helper'),
        revision: 'main',
      ),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          contains('Unsupported Git URL scheme'),
        ),
      ),
    );
  });

  test('replaces an incomplete cache target before publishing', () async {
    final source = await createSourceFixture(temporary);
    final archive = await _makeZip(
      source,
      File(p.join(temporary.path, 'repair.zip')),
    );
    final digest = sha256.convert(await archive.readAsBytes()).toString();
    final incomplete = await Directory(
      p.join(cache.directory.path, 'archive', digest),
    ).create(recursive: true);
    await File(p.join(incomplete.path, 'partial')).writeAsString('partial');

    final snapshot = await cache.fetchArchive(
      url: archive.uri,
      sha256: digest,
    );

    expect(
      File(p.join(snapshot.root, 'alfredo-source.yaml')).existsSync(),
      isTrue,
    );
    expect(File(p.join(incomplete.path, 'partial')).existsSync(), isFalse);
    expect(
      File(p.join(incomplete.path, '.complete')).existsSync(),
      isTrue,
    );
  });

  test(
    'detects altered cached content and rebuilds a protected snapshot',
    () async {
      final source = await createSourceFixture(
        temporary,
        sourceId: 'protected-source',
      );
      await _git(['init', source.path]);
      await _git(['-C', source.path, 'config', 'user.email', 'alfredo@test']);
      await _git(['-C', source.path, 'config', 'user.name', 'Alfredo Test']);
      await _git(['-C', source.path, 'add', '.']);
      await _git(['-C', source.path, 'commit', '-m', 'initial']);
      final commit = (await _git([
        '-C',
        source.path,
        'rev-parse',
        'HEAD',
      ])).trim();
      final first = await cache.fetchGit(url: source.uri, revision: commit);
      final manifest = File(p.join(first.root, 'alfredo-source.yaml'));
      if (Platform.isWindows) {
        await Process.run('attrib', ['-R', manifest.path]);
      } else {
        await Process.run('chmod', ['u+w', manifest.path]);
        expect(FileStat.statSync(manifest.path).mode & 0x92, isNot(0));
      }
      await manifest.writeAsString('tampered\n');

      final repaired = await cache.fetchGit(url: source.uri, revision: commit);

      expect(
        await File(p.join(repaired.root, 'alfredo-source.yaml')).readAsString(),
        contains('id: protected-source'),
      );
      if (!Platform.isWindows) {
        expect(FileStat.statSync(manifest.path).mode & 0x92, 0);
      }
    },
  );

  test('rejects a duplicate registration before fetching again', () async {
    final source = await createSourceFixture(temporary);
    final registry = SourceRegistry(
      file: File(p.join(temporary.path, 'config', 'sources.json')),
      snapshots: cache,
    );
    await registry.addLocal('existing', source.path);

    expect(
      () => registry.addArchive(
        'existing',
        url: File(p.join(temporary.path, 'missing.zip')).uri,
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      ),
      throwsA(
        isA<SourceException>().having(
          (error) => error.message,
          'message',
          contains('already registered'),
        ),
      ),
    );
  });

  test('persists immutable Git and archive transport metadata', () async {
    final source = await createSourceFixture(
      temporary,
      sourceId: 'metadata-source',
    );
    await _git(['init', source.path]);
    await _git(['-C', source.path, 'config', 'user.email', 'alfredo@test']);
    await _git(['-C', source.path, 'config', 'user.name', 'Alfredo Test']);
    await _git(['-C', source.path, 'add', '.']);
    await _git(['-C', source.path, 'commit', '-m', 'initial']);
    final commit = (await _git([
      '-C',
      source.path,
      'rev-parse',
      'HEAD',
    ])).trim();
    final registry = SourceRegistry(
      file: File(p.join(temporary.path, 'config', 'sources.json')),
      snapshots: cache,
    );

    final registered = await registry.addGit(
      'remote',
      url: source.uri,
      revision: commit,
    );
    final document = jsonDecode(await registry.file.readAsString()) as Map;
    final stored = (document['sources'] as List).single as Map;
    final transport = stored['transport'] as Map;

    expect(registered.kind, SourceKind.git);
    expect(transport['kind'], 'git');
    expect(transport['url'], source.uri.toString());
    expect(transport['revision'], commit);
    expect(transport['resolved_revision'], commit);
    expect((await registry.test('remote')).id, 'metadata-source');

    final archive = await _makeZip(
      source,
      File(p.join(temporary.path, 'metadata.zip')),
    );
    final digest = sha256.convert(await archive.readAsBytes()).toString();
    final archiveRegistration = await registry.addArchive(
      'bundle',
      url: archive.uri,
      sha256: digest,
    );
    final archiveDocument =
        jsonDecode(await registry.file.readAsString()) as Map<String, dynamic>;
    final archiveEntry = (archiveDocument['sources'] as List<dynamic>)
        .map(
          (entry) => Map<String, Object?>.from(entry as Map<String, dynamic>),
        )
        .singleWhere((entry) => entry['name'] == 'bundle');
    final archiveTransport = Map<String, Object?>.from(
      archiveEntry['transport']! as Map<String, dynamic>,
    );

    expect(archiveRegistration.kind, SourceKind.archive);
    expect(archiveTransport['kind'], 'archive');
    expect(archiveTransport['url'], archive.uri.toString());
    expect(archiveTransport['sha256'], digest);
  });
}

Future<File> _makeZip(Directory source, File destination) async {
  final archive = Archive()
    ..add(
      ArchiveFile.string(
        'bundle/alfredo-source.yaml',
        await File(p.join(source.path, 'alfredo-source.yaml')).readAsString(),
      ),
    )
    ..add(
      ArchiveFile.string(
        'bundle/packages/android-core/package.yaml',
        await File(
          p.join(source.path, 'packages', 'android-core', 'package.yaml'),
        ).readAsString(),
      ),
    );
  await destination.writeAsBytes(ZipEncoder().encodeBytes(archive));
  return destination;
}

Future<String> _git(List<String> arguments) async {
  final result = await Process.run('git', arguments);
  if (result.exitCode != 0) {
    fail('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
  return result.stdout as String;
}
