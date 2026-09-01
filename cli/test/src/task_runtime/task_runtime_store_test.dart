import 'dart:io';

import 'package:alfredo_cli/src/task_runtime/task_runtime.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late TaskRuntimeStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-runtime-');
    store = TaskRuntimeStore(projectRoot: temporary);
  });

  tearDown(() async => temporary.delete(recursive: true));

  test('discovers the runtime project root from a nested directory', () async {
    await Directory(p.join(temporary.path, '.git')).create();
    final nested = await Directory(
      p.join(temporary.path, 'cli', 'test'),
    ).create(recursive: true);
    await Directory(p.join(temporary.path, 'cli', '.alfredo')).create();

    final root = defaultTaskRuntimeProjectRoot(start: nested);

    expect(root.path, temporary.path);
  });

  test('creates, loads, lists, and rejects corrupted task state', () async {
    final task = await store.createTask(title: 'Implement reconnect support');

    expect(task.id, startsWith('ALF-'));
    expect((await store.readTask(task.id)).title, task.title);
    expect((await store.listTasks()).single.id, task.id);
    final events = await store.listTaskEvents(task.id);
    expect(events, hasLength(1));
    expect(events.single.type, 'created');
    expect(events.single.task, task.id);

    await File(
      p.join(temporary.path, '.alfredo', 'tasks', '${task.id}.json'),
    ).writeAsString('{');

    await expectLater(
      store.readTask(task.id),
      throwsA(isA<TaskRuntimeException>()),
    );
  });

  test('recovers stale locks and rejects fresh locks', () async {
    final staleStore = TaskRuntimeStore(
      projectRoot: temporary,
      staleLockTimeout: const Duration(hours: 1),
    );
    final locks = Directory(
      p.join(temporary.path, '.alfredo', 'runtime', 'locks'),
    );
    await locks.create(recursive: true);
    final stale = File(p.join(locks.path, 'tasks.lock'));
    await stale.writeAsString('{}');
    await stale.setLastModified(
      DateTime.now().subtract(const Duration(days: 1)),
    );

    final task = await staleStore.createTask(title: 'Recover stale lock');
    expect(task.id, startsWith('ALF-'));
    expect(stale.existsSync(), isFalse);

    final fresh = File(p.join(locks.path, 'tasks.lock'));
    await fresh.writeAsString('{}');
    await expectLater(
      staleStore.createTask(title: 'Fresh lock fails'),
      throwsA(isA<TaskRuntimeException>()),
    );
  });

  test('links tasks to runs and rejects missing runs', () async {
    final run = await store.createRun(title: 'Implement multiplayer MVP');
    final task = await store.createTask(title: 'Protocol', run: run.id);

    expect((await store.readTask(task.id)).run, run.id);
    expect((await store.readRun(run.id)).tasks, [task.id]);
    expect(
      File(
        p.join(temporary.path, '.alfredo', 'runs', run.id, 'manifest.json'),
      ).readAsStringSync(),
      contains(task.id),
    );
    await expectLater(
      store.createTask(title: 'Missing run', run: 'RUN-01K3Z7H8J9ABCDEFGHJK'),
      throwsA(isA<TaskRuntimeException>()),
    );
  });

  test('enforces task transitions and ownership', () async {
    final task = await store.createTask(title: 'Implement protocol');
    final session = await store.startSession(adapter: 'claude');

    await expectLater(
      store.startTask(task.id),
      throwsA(isA<TaskRuntimeException>()),
    );

    await store.claimTask(
      task.id,
      adapter: 'claude',
      agent: 'executor',
      session: session.id,
    );
    await store.startTask(task.id);
    await store.verifyTask(task.id);
    final done = await store.doneTask(task.id);

    expect(done.status, TaskStatus.done);
    await expectLater(
      store.blockTask(task.id, 'late'),
      throwsA(isA<TaskRuntimeException>()),
    );
  });

  test('rejects duplicate claim and releases ownership', () async {
    final task = await store.createTask(title: 'Implement server');
    final first = await store.startSession(adapter: 'claude');
    final second = await store.startSession(adapter: 'codex');

    await store.claimTask(
      task.id,
      adapter: 'claude',
      agent: 'executor',
      session: first.id,
    );

    await expectLater(
      store.claimTask(
        task.id,
        adapter: 'codex',
        agent: 'executor',
        session: second.id,
      ),
      throwsA(isA<TaskRuntimeException>()),
    );

    final released = await store.releaseTask(task.id);
    expect(released.owner, isNull);
    expect(released.previousOwner?.session, first.id);
  });

  test('allows only one concurrent claim winner', () async {
    final task = await store.createTask(title: 'Concurrent task');
    final first = await store.startSession(adapter: 'claude');
    final second = await store.startSession(adapter: 'codex');

    final results = await Future.wait<Object>(
      [
        store.claimTask(
          task.id,
          adapter: 'claude',
          agent: 'executor',
          session: first.id,
        ),
        store.claimTask(
          task.id,
          adapter: 'codex',
          agent: 'executor',
          session: second.id,
        ),
      ].map((future) async {
        try {
          return await future;
        } on Object catch (error) {
          return error;
        }
      }),
    );

    expect(results.whereType<AlfredoTask>(), hasLength(1));
    expect(results.whereType<TaskRuntimeException>(), hasLength(1));
    expect((await store.readTask(task.id)).owner, isNotNull);
  });

  test('blocks, unblocks, cancels, and calculates ready tasks', () async {
    final dependency = await store.createTask(title: 'Protocol');
    final dependent = await store.createTask(
      title: 'Client',
      dependencies: [dependency.id],
    );

    expect((await store.readyTasks()).map((task) => task.id), [dependency.id]);

    await store.blockTask(dependency.id, 'waiting');
    expect(await store.readyTasks(), isEmpty);

    await store.unblockTask(dependency.id);
    final session = await store.startSession(adapter: 'codex');
    await store.claimTask(
      dependency.id,
      adapter: 'codex',
      agent: 'executor',
      session: session.id,
    );
    await store.startTask(dependency.id);
    await store.verifyTask(dependency.id);
    await store.doneTask(dependency.id);

    expect((await store.readyTasks()).map((task) => task.id), [dependent.id]);

    await store.cancelTask(dependent.id);
    expect((await store.readTask(dependent.id)).status, TaskStatus.cancelled);
  });

  test('rejects dependency cycles', () async {
    final first = await store.createTask(title: 'First');
    final second = await store.createTask(title: 'Second');

    await store.addDependencies(second.id, dependencies: [first.id]);

    await expectLater(
      store.addDependencies(first.id, dependencies: [second.id]),
      throwsA(isA<TaskRuntimeException>()),
    );
  });

  test('persists repeated checkpoints and session close handoff', () async {
    final task = await store.createTask(title: 'Checkpoint task');
    final session = await store.startSession(adapter: 'claude');
    await store.claimTask(
      task.id,
      adapter: 'claude',
      agent: 'executor',
      session: session.id,
    );

    await store.checkpointTask(
      task.id,
      const TaskCheckpoint(
        completed: ['protocol'],
        current: 'server',
        changedFiles: ['server/player.ts'],
        validations: {'unit_tests': 'pending'},
      ),
    );
    await store.checkpointTask(
      task.id,
      const TaskCheckpoint(
        completed: ['server'],
        remaining: ['client'],
        validations: {'unit_tests': 'passed'},
        nextAction: 'implement client',
      ),
    );

    final checkpoint = (await store.readTask(task.id)).checkpoint;
    expect(checkpoint.completed, ['protocol', 'server']);
    expect(checkpoint.validations['unit_tests'], 'passed');

    final closed = await store.closeSession(
      session.id,
      reason: 'context-limit',
    );
    final released = await store.readTask(task.id);

    expect(closed.status, SessionStatus.closed);
    expect(released.owner, isNull);
    expect(released.previousOwner?.session, session.id);
  });

  test('builds deterministic context from topics and files', () async {
    await File(p.join(temporary.path, 'docs', 'protocol.md'))
        .create(recursive: true)
        .then((file) => file.writeAsString('Protocol notes'));
    await File(p.join(temporary.path, 'lib', 'client.dart'))
        .create(recursive: true)
        .then((file) => file.writeAsString('class Client {}'));
    await File(p.join(temporary.path, 'shared', 'protocol', 'message.dart'))
        .create(recursive: true)
        .then((file) => file.writeAsString('class Message {}'));
    await File(p.join(temporary.path, '.alfredo', 'personas', 'alfredo.md'))
        .create(recursive: true)
        .then((file) => file.writeAsString('Alfredo voice'));
    await File(
      p.join(temporary.path, '.alfredo', 'personas', 'user.md'),
    ).create(recursive: true).then((file) => file.writeAsString('User voice'));
    await File(p.join(temporary.path, '.alfredo', 'context', 'index.yaml'))
        .create(recursive: true)
        .then(
          (file) => file.writeAsString(
            'contexts:\n'
            '  multiplayer:\n'
            '    description: Multiplayer\n'
            '    files:\n'
            '      - docs/protocol.md\n'
            '      - shared/protocol/**\n',
          ),
        );

    final task = await store.createTask(
      title: 'Context task',
      context: const TaskContextHints(
        topics: ['multiplayer'],
        files: ['lib/client.dart'],
      ),
    );

    final context = await store.buildContext(task.id);

    expect(context.sources['files'], [
      'docs/protocol.md',
      'lib/client.dart',
      'shared/protocol/message.dart',
    ]);
    expect(context.sources['personas'], [
      '.alfredo/personas/alfredo.md',
      '.alfredo/personas/user.md',
    ]);
    expect(context.estimatedTokens, greaterThan(0));
    expect(context.missing, isEmpty);
  });

  test('folds a matched template into the context package', () async {
    await File(
          p.join(temporary.path, 'templates', 'bank-email', 'TEMPLATE.md'),
        )
        .create(recursive: true)
        .then(
          (file) => file.writeAsString(
            '---\n'
            'schema_version: 1\n'
            'name: bank-email\n'
            'kind: email\n'
            'description: Use for client email. Not for Slack.\n'
            '---\n\n'
            'Contract prose.\n',
          ),
        );

    final matched = await store.createTask(
      title: 'Draft the email',
      context: const TaskContextHints(template: 'email'),
    );
    final missing = await store.createTask(
      title: 'Draft the deck',
      context: const TaskContextHints(template: 'no-such-template'),
    );

    final withTemplate = await store.buildContext(matched.id);
    expect(withTemplate.sources['templates'], [
      'templates/bank-email/TEMPLATE.md',
    ]);
    expect(withTemplate.missing, isEmpty);

    final withoutTemplate = await store.buildContext(missing.id);
    expect(withoutTemplate.sources['templates'], isEmpty);
    expect(withoutTemplate.missing, contains('template:no-such-template'));
  });

  test('rejects unsafe context file paths', () async {
    await expectLater(
      store.createTask(
        title: 'Unsafe context',
        context: const TaskContextHints(files: ['../secret']),
      ),
      throwsA(isA<TaskRuntimeException>()),
    );
  });
}
