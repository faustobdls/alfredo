import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/command_runner.dart';
import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:alfredo_cli/src/package/package.dart';
import 'package:alfredo_cli/src/source/source.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../helpers/memory_fixture.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  late Directory temporary;
  late Logger logger;
  late FakeEmbeddingsClient embeddings;
  late AlfredoCliCommandRunner runner;
  late Directory userMemory;
  late Directory projectMemory;

  MemoryStore storeFor(Directory directory) =>
      MemoryStore(directory: directory);

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'alfredo-memory-command-',
    );
    logger = _MockLogger();
    embeddings = FakeEmbeddingsClient(reachable: false);
    userMemory = Directory(
      p.join(temporary.path, 'user', '.alfredo', 'memory'),
    );
    projectMemory = Directory(
      p.join(temporary.path, 'project', '.alfredo', 'memory'),
    );
    runner = AlfredoCliCommandRunner(
      logger: logger,
      sourceRegistry: SourceRegistry(
        file: File(p.join(temporary.path, 'config', 'sources.json')),
      ),
      targetRoots: AgentTargetRoots(
        userRoot: Directory(p.join(temporary.path, 'user')),
        projectRoot: Directory(p.join(temporary.path, 'project')),
      ),
      memoryRoots: MemoryRoots(
        userDirectory: userMemory,
        projectDirectory: projectMemory,
      ),
      embeddingsFactory: (_) => embeddings,
    );
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Future<void> registerMemorySource() async {
    final source = await createMemorySourceFixture(temporary);
    expect(
      await runner.run(['source', 'add', 'memory', '--local', source.path]),
      ExitCode.success.code,
    );
  }

  test('records an activity in the dated journal file', () async {
    expect(
      await runner.run(['memory', 'add', 'did the thing', '--scope', 'user']),
      ExitCode.success.code,
    );

    final entries = await storeFor(userMemory).listActivities();
    expect(entries.single.message, 'did the thing');
    expect(entries.single.kind, MemoryEntryKind.activity);
    verify(
      () => logger.success(any(that: contains(p.join('journal')))),
    ).called(1);
  });

  test('records tags and honours the project scope', () async {
    expect(
      await runner.run([
        'memory',
        'add',
        '--scope',
        'project',
        '-t',
        'release',
        'shipped it',
      ]),
      ExitCode.success.code,
    );

    final entries = await storeFor(projectMemory).listActivities();
    expect(entries.single.tags, ['release']);
    expect(await storeFor(userMemory).listActivities(), isEmpty);
  });

  test('writes a durable note with a dated slug', () async {
    expect(
      await runner.run([
        'memory',
        'add',
        '--scope',
        'user',
        '--kind',
        'note',
        '--title',
        'Decision Y',
        'we chose atomic renames',
      ]),
      ExitCode.success.code,
    );

    final notes = storeFor(userMemory).notesDirectory
        .listSync()
        .map((entity) => p.basename(entity.path))
        .toList();
    expect(notes, hasLength(1));
    expect(notes.single, matches(r'^\d{4}-\d{2}-\d{2}-decision-y\.md$'));
  });

  test('requires a title for a note', () async {
    expect(
      await runner.run(['memory', 'add', '--kind', 'note', 'body only']),
      ExitCode.usage.code,
    );
    verify(() => logger.err(any(that: contains('--title')))).called(1);
  });

  test('requires a message', () async {
    expect(await runner.run(['memory', 'add']), ExitCode.usage.code);
    verify(
      () => logger.err(any(that: contains('Expected a memory message'))),
    ).called(1);
  });

  test('rejects an unknown scope', () async {
    expect(
      await runner.run(['memory', 'add', '--scope', 'global', 'x']),
      ExitCode.usage.code,
    );
  });

  test('rejects an unparsable --since window', () async {
    expect(
      await runner.run(['memory', 'list', '--since', 'yesterday']),
      ExitCode.usage.code,
    );
    verify(
      () => logger.err(any(that: contains('Invalid --since value'))),
    ).called(1);
  });

  test('lists and digests recent entries across scopes', () async {
    await runner.run(['memory', 'add', '--scope', 'user', 'user work']);
    await runner.run(['memory', 'add', '--scope', 'project', 'project work']);

    expect(
      await runner.run(['memory', 'list', '--since', '30d']),
      ExitCode.success.code,
    );
    expect(
      await runner.run([
        'memory',
        'digest',
        '--since',
        '30d',
        '--max-chars',
        '200',
      ]),
      ExitCode.success.code,
    );

    verify(
      () => logger.info(any(that: contains('user\tactivity\t[]\tuser work'))),
    ).called(1);
    verify(
      () => logger.info(any(that: contains('# user'))),
    ).called(1);
    verify(
      () => logger.info(any(that: contains('# project'))),
    ).called(1);
  });

  test('reports empty stores without failing', () async {
    expect(
      await runner.run(['memory', 'list', '--since', '7d']),
      ExitCode.success.code,
    );
    expect(await runner.run(['memory', 'digest']), ExitCode.success.code);
    expect(
      await runner.run(['memory', 'search', 'anything']),
      ExitCode.success.code,
    );

    verify(() => logger.info('No entries.')).called(2);
    verify(() => logger.info('No matches.')).called(1);
  });

  test('searches with keyword ranking by default', () async {
    await runner.run([
      'memory',
      'add',
      '--scope',
      'user',
      'alpha alpha rollback',
    ]);

    expect(
      await runner.run(['memory', 'search', 'rollback', '--scope', 'user']),
      ExitCode.success.code,
    );

    verify(
      () => logger.info(any(that: contains('user\tjournal/'))),
    ).called(1);
    expect(embeddings.embedCalls, 0);
  });

  test('indexes and searches with an embedding provider', () async {
    embeddings = FakeEmbeddingsClient();
    await runner.run([
      'memory',
      'add',
      '--scope',
      'user',
      '--kind',
      'note',
      '--title',
      'Alpha One',
      'alpha alpha alpha',
    ]);
    await runner.run([
      'memory',
      'add',
      '--scope',
      'user',
      '--kind',
      'note',
      '--title',
      'Beta One',
      'beta beta beta',
    ]);
    await storeFor(userMemory).writeConfig(
      const MemoryConfig(
        embeddings: EmbeddingsConfig(enabled: true, model: 'fake-embed'),
        capture: CaptureConfig(),
        defaultScope: MemoryScope.user,
      ),
    );

    expect(
      await runner.run(['memory', 'index', '--scope', 'user']),
      ExitCode.success.code,
    );
    expect(
      await runner.run([
        'memory',
        'search',
        'alpha',
        '--scope',
        'user',
        '--limit',
        '1',
      ]),
      ExitCode.success.code,
    );

    verify(
      () => logger.success(any(that: contains('user: embedded 2'))),
    ).called(1);
    verify(
      () => logger.info(any(that: contains('notes/'))),
    ).called(greaterThanOrEqualTo(1));
    expect(embeddings.embedCalls, greaterThan(1));
  });

  test('refuses to index while embeddings are disabled', () async {
    await runner.run(['memory', 'add', '--scope', 'user', 'work']);

    expect(
      await runner.run(['memory', 'index', '--scope', 'user']),
      ExitCode.config.code,
    );
    verify(
      () => logger.err(any(that: contains('Embeddings are disabled'))),
    ).called(1);
  });

  test('refuses to index while the provider is unreachable', () async {
    await runner.run(['memory', 'add', '--scope', 'user', 'work']);
    await storeFor(userMemory).writeConfig(
      const MemoryConfig(
        embeddings: EmbeddingsConfig(enabled: true, model: 'fake-embed'),
        capture: CaptureConfig(),
        defaultScope: MemoryScope.user,
      ),
    );

    expect(
      await runner.run(['memory', 'index', '--scope', 'user']),
      ExitCode.config.code,
    );
    verify(
      () => logger.err(any(that: contains('not reachable'))),
    ).called(1);
  });

  test('sets up a store, installs memory-core, and writes a hook', () async {
    await registerMemorySource();

    expect(
      await runner.run([
        'memory',
        'setup',
        '--all',
        '--source',
        'memory',
        '--scope',
        'user',
      ]),
      ExitCode.success.code,
    );

    final config =
        jsonDecode(
              await File(
                p.join(userMemory.path, 'config.json'),
              ).readAsString(),
            )
            as Map<String, Object?>;
    final settings = File(
      p.join(temporary.path, 'user', '.claude', 'settings.json'),
    );

    expect(config['version'], 1);
    expect(config['defaultScope'], 'user');
    expect((config['capture']! as Map)['sessionEndHook'], isTrue);
    expect((config['capture']! as Map)['targets'], ['claude-code']);
    expect((config['embeddings']! as Map)['enabled'], isFalse);
    expect(
      File(
        p.join(
          temporary.path,
          'user',
          '.claude',
          'skills',
          'alfredo-memory',
          'SKILL.md',
        ),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(temporary.path, 'user', '.claude', 'rules', 'memory-usage.md'),
      ).existsSync(),
      isTrue,
    );
    expect(
      await settings.readAsString(),
      contains('alfredo memory capture --scope user'),
    );
  });

  test('enables embeddings when the model is tagged latest', () async {
    embeddings = FakeEmbeddingsClient(
      model: 'nomic-embed-text',
      installedModels: const ['nomic-embed-text:latest'],
    );
    await registerMemorySource();

    expect(
      await runner.run([
        'memory',
        'setup',
        '--all',
        '--no-hook',
        '--source',
        'memory',
        '--scope',
        'user',
      ]),
      ExitCode.success.code,
    );

    final embeddingsConfig =
        (jsonDecode(
                  await File(
                    p.join(userMemory.path, 'config.json'),
                  ).readAsString(),
                )
                as Map<String, Object?>)['embeddings']!
            as Map<String, Object?>;
    expect(embeddingsConfig['enabled'], isTrue);
    expect(embeddingsConfig['model'], 'nomic-embed-text');
    expect(embeddings.pullCalls, 0);
  });

  test(
    'reuses an already-installed known model instead of downloading',
    () async {
      embeddings = FakeEmbeddingsClient(
        model: 'embeddinggemma',
        installedModels: const ['llama3:latest', 'embeddinggemma:latest'],
      );
      await registerMemorySource();

      expect(
        await runner.run([
          'memory',
          'setup',
          '--all',
          '--no-hook',
          '--source',
          'memory',
          '--scope',
          'user',
        ]),
        ExitCode.success.code,
      );

      final embeddingsConfig =
          (jsonDecode(
                    await File(
                      p.join(userMemory.path, 'config.json'),
                    ).readAsString(),
                  )
                  as Map<String, Object?>)['embeddings']!
              as Map<String, Object?>;
      expect(embeddingsConfig['enabled'], isTrue);
      expect(embeddingsConfig['model'], 'embeddinggemma');
      expect(embeddings.pullCalls, 0);
      verify(
        () => logger.info(
          any(
            that: contains('Using installed embedding model "embeddinggemma"'),
          ),
        ),
      ).called(1);
    },
  );

  test('keeps keyword search when no known model is installed', () async {
    embeddings = FakeEmbeddingsClient(
      installedModels: const ['llama3:latest'],
    );
    await registerMemorySource();

    expect(
      await runner.run([
        'memory',
        'setup',
        '--all',
        '--no-hook',
        '--source',
        'memory',
        '--scope',
        'user',
      ]),
      ExitCode.success.code,
    );

    final embeddingsConfig =
        (jsonDecode(
                  await File(
                    p.join(userMemory.path, 'config.json'),
                  ).readAsString(),
                )
                as Map<String, Object?>)['embeddings']!
            as Map<String, Object?>;
    expect(embeddingsConfig['enabled'], isFalse);
    expect(embeddings.pullCalls, 0);
    expect(embeddings.embedCalls, 0);
  });

  test('skips the hook when it is explicitly declined', () async {
    await registerMemorySource();

    expect(
      await runner.run([
        'memory',
        'setup',
        '--all',
        '--no-hook',
        '--source',
        'memory',
      ]),
      ExitCode.success.code,
    );

    expect(
      File(
        p.join(temporary.path, 'user', '.claude', 'settings.json'),
      ).existsSync(),
      isFalse,
    );
  });

  test('installs into every requested target', () async {
    await registerMemorySource();

    expect(
      await runner.run([
        'memory',
        'setup',
        '--all',
        '--target',
        'codex',
        '--target',
        'generic',
        '--no-hook',
      ]),
      ExitCode.success.code,
    );

    expect(
      File(
        p.join(
          temporary.path,
          'user',
          '.codex',
          'skills',
          'alfredo-memory',
          'SKILL.md',
        ),
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        p.join(temporary.path, 'user', '.alfredo', 'rules', 'memory-usage.md'),
      ).existsSync(),
      isTrue,
    );
  });

  test('reports a configuration error when memory-core is absent', () async {
    expect(
      await runner.run(['memory', 'setup', '--all', '--no-hook']),
      ExitCode.config.code,
    );
    verify(
      () => logger.err(any(that: contains('memory-core'))),
    ).called(1);
  });

  test('reports a configuration error for an unknown source', () async {
    await registerMemorySource();

    expect(
      await runner.run([
        'memory',
        'setup',
        '--all',
        '--no-hook',
        '--source',
        'other',
      ]),
      ExitCode.config.code,
    );
    verify(
      () => logger.err(any(that: contains('does not provide memory-core'))),
    ).called(1);
  });

  test('captures the end of a session without git', () async {
    expect(
      await runner.run(['memory', 'capture', '--scope', 'user']),
      ExitCode.success.code,
    );

    final entries = await storeFor(userMemory).listActivities();
    expect(
      entries.map((entry) => entry.message),
      containsAll(<String>[
        'session ended',
        'TODO: summarize what was done this session',
      ]),
    );
    verify(
      () => logger.success(any(that: contains('Captured session memory'))),
    ).called(1);
  });
}
