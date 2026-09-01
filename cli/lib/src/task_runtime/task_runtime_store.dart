import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:alfredo_cli/src/task_runtime/task_runtime_models.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Durable local-first task runtime store.
class TaskRuntimeStore {
  /// Creates a store under an Alfredo project root.
  const TaskRuntimeStore({
    required this.projectRoot,
    this.staleLockTimeout = const Duration(minutes: 15),
  });

  /// Project root containing `.alfredo`.
  final Directory projectRoot;

  /// Lock age after which recovery may remove the stale lock.
  final Duration staleLockTimeout;

  /// `.alfredo` root.
  Directory get root => Directory(p.join(projectRoot.path, '.alfredo'));

  Directory get _tasks => Directory(p.join(root.path, 'tasks'));
  Directory get _runs => Directory(p.join(root.path, 'runs'));
  Directory get _events => Directory(p.join(root.path, 'task-events'));

  /// Local, non-versioned execution state (`.alfredo/runtime/`).
  Directory get _runtime => Directory(p.join(root.path, 'runtime'));
  Directory get _sessions => Directory(p.join(_runtime.path, 'sessions'));
  Directory get _locks => Directory(p.join(_runtime.path, 'locks'));

  /// Creates a task.
  Future<AlfredoTask> createTask({
    required String title,
    String priority = 'normal',
    String? run,
    List<String> dependencies = const [],
    List<String> acceptance = const [],
    TaskContextHints context = const TaskContextHints(),
  }) async {
    return withLock('tasks', () async {
      final now = _now();
      final tasks = await listTasks();
      await _ensureKnownDependencies(tasks, dependencies);
      _ensureSafePaths(context.files);
      _ensureAcyclic(tasks, null, dependencies);
      final parentRun = run == null ? null : await readRun(run);
      final task = AlfredoTask(
        id: _newId('ALF'),
        title: title,
        status: TaskStatus.backlog,
        priority: priority,
        run: run,
        createdAt: now,
        updatedAt: now,
        dependencies: _sortedUnique(dependencies),
        acceptance: acceptance,
        context: context,
      );
      await _writeJson(_taskFile(task.id), task.toJson());
      await _appendEvent(task.id, 'created', {'title': title});
      if (parentRun != null) {
        await _writeRun(
          AlfredoRun(
            id: parentRun.id,
            title: parentRun.title,
            summary: parentRun.summary,
            createdAt: parentRun.createdAt,
            updatedAt: now,
            tasks: _sortedUnique([...parentRun.tasks, task.id]),
          ),
        );
      }
      return task;
    });
  }

  /// Lists tasks in stable order.
  Future<List<AlfredoTask>> listTasks() async {
    if (!_tasks.existsSync()) return const [];
    final files =
        _tasks
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    return [
      for (final file in files)
        AlfredoTask.fromJson(_decode(await file.readAsString())),
    ];
  }

  /// Reads a task.
  Future<AlfredoTask> readTask(String id) async {
    final file = _taskFile(id);
    if (!file.existsSync()) throw TaskRuntimeException('Task not found: $id');
    try {
      return AlfredoTask.fromJson(_decode(await file.readAsString()));
    } on FormatException catch (error) {
      throw TaskRuntimeException('Cannot read task $id: ${error.message}');
    }
  }

  /// Lists append-only events for one task in stable order.
  Future<List<TaskEvent>> listTaskEvents(String taskId) async {
    if (!_events.existsSync()) return const [];
    final files =
        _events
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('-$taskId.json') &&
                  p.basename(file.path).startsWith('EVT-'),
            )
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    return [
      for (final file in files)
        TaskEvent.fromJson(_decode(await file.readAsString())),
    ];
  }

  /// Returns claimable tasks. READY is derived here.
  Future<List<AlfredoTask>> readyTasks() async {
    final tasks = await listTasks();
    final done = {
      for (final task in tasks)
        if (task.status == TaskStatus.done) task.id,
    };
    return [
      for (final task in tasks)
        if (task.isClaimable(done)) task,
    ];
  }

  /// Claims a task atomically.
  Future<AlfredoTask> claimTask(
    String id, {
    required String adapter,
    required String agent,
    required String session,
  }) {
    return withLock('task-$id', () async {
      final task = await readTask(id);
      if (task.owner != null) {
        final owner = task.owner!;
        throw TaskRuntimeException(
          'Task already claimed.\n\nOwner:\n'
          '${owner.adapter} / ${owner.agent}\n\nSession:\n${owner.session}',
        );
      }
      final all = await listTasks();
      final done = {
        for (final item in all)
          if (item.status == TaskStatus.done) item.id,
      };
      if (!task.dependencies.every(done.contains)) {
        throw TaskRuntimeException('Task dependencies are not satisfied: $id');
      }
      final ownerSession = await readSession(session);
      if (ownerSession.status != SessionStatus.active) {
        throw TaskRuntimeException('Session is not active: $session');
      }
      if (ownerSession.adapter != adapter) {
        throw TaskRuntimeException(
          'Session $session belongs to ${ownerSession.adapter}, not $adapter.',
        );
      }
      _ensureTransition(task.status, TaskStatus.claimed);
      final now = _now();
      final next = task.copyWith(
        status: TaskStatus.claimed,
        updatedAt: now,
        owner: TaskOwner(adapter: adapter, agent: agent, session: session),
      );
      await _writeTask(next, 'claimed', {'session': session});
      await _writeSession(
        ownerSession.copyWith(
          updatedAt: now,
          tasksClaimed: _sortedUnique([...ownerSession.tasksClaimed, id]),
        ),
      );
      return next;
    });
  }

  /// Adds dependencies to an existing task.
  Future<AlfredoTask> addDependencies(
    String id, {
    required List<String> dependencies,
  }) {
    return withLock('task-$id', () async {
      final task = await readTask(id);
      if (task.status != TaskStatus.backlog) {
        throw TaskRuntimeException(
          'Dependencies can only be changed while BACKLOG: $id',
        );
      }
      final tasks = await listTasks();
      await _ensureKnownDependencies(tasks, dependencies);
      if (dependencies.contains(id)) {
        throw const TaskRuntimeException('Task cannot depend on itself.');
      }
      final nextDependencies = _sortedUnique([
        ...task.dependencies,
        ...dependencies,
      ]);
      _ensureAcyclic(tasks, id, nextDependencies);
      final next = task.copyWith(
        dependencies: nextDependencies,
        updatedAt: _now(),
      );
      await _writeTask(next, 'dependencies-updated', {
        'dependencies': nextDependencies,
      });
      return next;
    });
  }

  /// Starts active work.
  Future<AlfredoTask> startTask(String id) {
    return _transition(id, TaskStatus.doing, event: 'started');
  }

  /// Marks task as verifying.
  Future<AlfredoTask> verifyTask(String id) {
    return _transition(id, TaskStatus.verifying, event: 'verifying');
  }

  /// Marks task done.
  Future<AlfredoTask> doneTask(String id) {
    return _transition(id, TaskStatus.done, event: 'done');
  }

  /// Cancels a task.
  Future<AlfredoTask> cancelTask(String id) {
    return _transition(id, TaskStatus.cancelled, event: 'cancelled');
  }

  /// Releases ownership.
  Future<AlfredoTask> releaseTask(String id) {
    return withLock('task-$id', () async {
      final task = await readTask(id);
      if (task.owner == null) return task;
      final next = task.copyWith(
        status: TaskStatus.backlog,
        updatedAt: _now(),
        owner: null,
        previousOwner: task.owner,
        blocker: null,
      );
      await _writeTask(next, 'released', {'session': task.owner!.session});
      return next;
    });
  }

  /// Blocks a task.
  Future<AlfredoTask> blockTask(String id, String reason) {
    return withLock('task-$id', () async {
      final task = await readTask(id);
      if (task.status == TaskStatus.done ||
          task.status == TaskStatus.cancelled) {
        throw TaskRuntimeException('Cannot block ${task.status.wireName}.');
      }
      final next = task.copyWith(
        status: TaskStatus.blocked,
        updatedAt: _now(),
        blocker: reason,
      );
      await _writeTask(next, 'blocked', {'reason': reason});
      return next;
    });
  }

  /// Unblocks a task back to backlog.
  Future<AlfredoTask> unblockTask(String id) {
    return withLock('task-$id', () async {
      final task = await readTask(id);
      if (task.status != TaskStatus.blocked) {
        throw TaskRuntimeException('Task is not blocked: $id');
      }
      final next = task.copyWith(
        status: TaskStatus.backlog,
        updatedAt: _now(),
        blocker: null,
      );
      await _writeTask(next, 'unblocked', const {});
      return next;
    });
  }

  /// Adds an operational checkpoint.
  Future<AlfredoTask> checkpointTask(String id, TaskCheckpoint checkpoint) {
    return withLock('task-$id', () async {
      final task = await readTask(id);
      if (task.status == TaskStatus.done ||
          task.status == TaskStatus.cancelled) {
        throw TaskRuntimeException(
          'Cannot checkpoint ${task.status.wireName}.',
        );
      }
      final now = _now();
      final next = task.copyWith(
        updatedAt: now,
        checkpoint: task.checkpoint.merge(checkpoint),
      );
      await _writeTask(next, 'checkpointed', checkpoint.toJson());
      final owner = task.owner;
      if (owner != null && _sessionFile(owner.session).existsSync()) {
        final session = await readSession(owner.session);
        await _writeSession(
          session.copyWith(
            updatedAt: now,
            tasksWorked: _sortedUnique([...session.tasksWorked, id]),
            lastCheckpoint: checkpoint.nextAction ?? checkpoint.current,
          ),
        );
      }
      return next;
    });
  }

  /// Starts a worker session.
  Future<AlfredoSession> startSession({
    required String adapter,
    String agent = 'executor',
  }) async {
    final now = _now();
    final session = AlfredoSession(
      id: _newId('SES'),
      adapter: adapter,
      agent: agent,
      startedAt: now,
      updatedAt: now,
      status: SessionStatus.active,
    );
    await _writeSession(session);
    return session;
  }

  /// Lists sessions.
  Future<List<AlfredoSession>> listSessions() async {
    if (!_sessions.existsSync()) return const [];
    final files =
        _sessions
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    return [
      for (final file in files)
        AlfredoSession.fromJson(_decode(await file.readAsString())),
    ];
  }

  /// Reads a session.
  Future<AlfredoSession> readSession(String id) async {
    final file = _sessionFile(id);
    if (!file.existsSync()) {
      throw TaskRuntimeException('Session not found: $id');
    }
    return AlfredoSession.fromJson(_decode(await file.readAsString()));
  }

  /// Closes a session and releases its open claims for handoff.
  Future<AlfredoSession> closeSession(String id, {required String reason}) {
    return withLock('session-$id', () async {
      final session = await readSession(id);
      if (session.status == SessionStatus.closed) return session;
      final now = _now();
      for (final task in await listTasks()) {
        if (task.owner?.session == id &&
            task.status != TaskStatus.done &&
            task.status != TaskStatus.cancelled) {
          await releaseTask(task.id);
        }
      }
      final next = session.copyWith(
        status: SessionStatus.closed,
        updatedAt: now,
        endedAt: now,
        closeReason: reason,
      );
      await _writeSession(next);
      return next;
    });
  }

  /// Creates a run.
  Future<AlfredoRun> createRun({required String title, String? summary}) async {
    final now = _now();
    final run = AlfredoRun(
      id: _newId('RUN'),
      title: title,
      summary: summary,
      createdAt: now,
      updatedAt: now,
    );
    await _writeRun(run);
    return run;
  }

  Future<void> _writeRun(AlfredoRun run) async {
    await _writeJson(_runFile(run.id), run.toJson());
    final runDir = Directory(p.join(_runs.path, run.id));
    await runDir.create(recursive: true);
    await File(p.join(runDir.path, 'manifest.json')).writeAsString(
      '${prettyJson.convert(run.toJson())}\n',
      flush: true,
    );
  }

  /// Lists runs.
  Future<List<AlfredoRun>> listRuns() async {
    if (!_runs.existsSync()) return const [];
    final files =
        _runs
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));
    return [
      for (final file in files)
        AlfredoRun.fromJson(_decode(await file.readAsString())),
    ];
  }

  /// Reads a run.
  Future<AlfredoRun> readRun(String id) async {
    final file = _runFile(id);
    if (!file.existsSync()) throw TaskRuntimeException('Run not found: $id');
    return AlfredoRun.fromJson(_decode(await file.readAsString()));
  }

  /// Builds a compact context package.
  Future<AlfredoContextPackage> buildContext(
    String taskId, {
    int targetTokens = 6000,
    int hardLimitTokens = 12000,
  }) async {
    final task = await readTask(taskId);
    final explicitFiles = <String>{...task.context.files};
    final topicFiles = <String>{};
    final missing = <String>[];
    final index = File(p.join(root.path, 'context', 'index.yaml'));
    if (index.existsSync()) {
      final document = loadYaml(await index.readAsString());
      final contexts = document is YamlMap ? document['contexts'] : null;
      for (final topic in task.context.topics) {
        final entry = contexts is YamlMap ? contexts[topic] : null;
        if (entry is! YamlMap) {
          missing.add('context:$topic');
          continue;
        }
        final files = entry['files'];
        if (files is YamlList) {
          topicFiles.addAll(files.map((item) => '$item'));
        }
      }
    } else if (task.context.topics.isNotEmpty) {
      missing.add('context:index.yaml');
    }
    _ensureSafePaths([...explicitFiles, ...topicFiles]);
    final requestedFiles = _sortedUnique([...explicitFiles, ...topicFiles]);
    final files = <String>{};
    var estimated = _estimateTokens(prettyJson.convert(task.toJson()));
    for (final filePath in requestedFiles) {
      final resolved = await _resolveContextFiles(filePath);
      if (resolved.isEmpty) {
        missing.add('file:$filePath');
        continue;
      }
      for (final resolvedPath in resolved) {
        files.add(resolvedPath);
        final file = File(p.join(projectRoot.path, resolvedPath));
        if (file.existsSync()) {
          estimated += _estimateTokens(await file.readAsString());
        }
      }
    }
    final sortedFiles = _sortedUnique(files);
    return AlfredoContextPackage(
      task: task.id,
      targetTokens: targetTokens,
      hardLimitTokens: hardLimitTokens,
      estimatedTokens: estimated,
      sources: {
        'rules': const [],
        'skills': const [],
        'memory': const [],
        'files': sortedFiles,
        'decisions': const [],
      },
      missing: _sortedUnique(missing),
    );
  }

  /// Runs an operation under a cross-platform lock directory.
  Future<T> withLock<T>(String name, Future<T> Function() callback) async {
    await _locks.create(recursive: true);
    final lock = File(p.join(_locks.path, '$name.lock'));
    await _acquireLock(lock, name);
    try {
      await lock.writeAsString(
        '${prettyJson.convert({
          'pid': pid,
          'created_at': _now().toUtc().toIso8601String(),
        })}\n',
        flush: true,
      );
      return await callback();
    } finally {
      if (lock.existsSync()) await lock.delete();
    }
  }

  Future<void> _acquireLock(File lock, String name) async {
    try {
      await lock.create(exclusive: true);
      return;
    } on FileSystemException {
      if (!await _tryRecoverStaleLock(lock)) {
        throw TaskRuntimeException('Runtime resource is locked: $name');
      }
    }
    try {
      await lock.create(exclusive: true);
    } on FileSystemException {
      throw TaskRuntimeException('Runtime resource is locked: $name');
    }
  }

  Future<bool> _tryRecoverStaleLock(File lock) async {
    try {
      final modified = lock.lastModifiedSync();
      if (_now().difference(modified) < staleLockTimeout) return false;
      await lock.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<AlfredoTask> _transition(
    String id,
    TaskStatus status, {
    required String event,
  }) {
    return withLock('task-$id', () async {
      final task = await readTask(id);
      _ensureTransition(task.status, status);
      if ((status == TaskStatus.doing || status == TaskStatus.verifying) &&
          task.owner == null) {
        throw TaskRuntimeException('Task must be claimed before $event: $id');
      }
      final next = task.copyWith(status: status, updatedAt: _now());
      await _writeTask(next, event, const {});
      return next;
    });
  }

  Future<void> _writeTask(
    AlfredoTask task,
    String event,
    Map<String, Object?> data,
  ) async {
    await _writeJson(_taskFile(task.id), task.toJson());
    await _appendEvent(task.id, event, data);
  }

  Future<void> _writeSession(AlfredoSession session) {
    return _writeJson(_sessionFile(session.id), session.toJson());
  }

  File _taskFile(String id) => File(p.join(_tasks.path, '$id.json'));
  File _sessionFile(String id) => File(p.join(_sessions.path, '$id.json'));
  File _runFile(String id) => File(p.join(_runs.path, '$id.json'));

  Future<void> _appendEvent(
    String task,
    String type,
    Map<String, Object?> data,
  ) async {
    await _events.create(recursive: true);
    final event = TaskEvent(
      id: _newId('EVT'),
      task: task,
      type: type,
      createdAt: _now(),
      data: data,
    );
    await _writeJson(
      File(p.join(_events.path, '${event.id}-$task.json')),
      event.toJson(),
    );
  }

  static Future<void> _writeJson(File file, Map<String, Object?> json) async {
    final temporary = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsString(
        '${prettyJson.convert(json)}\n',
        flush: true,
      );
      await temporary.rename(file.path);
    } on FileSystemException catch (error) {
      throw TaskRuntimeException(
        'Cannot update ${file.path}: ${error.message}',
      );
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
  }

  static Map<String, Object?> _decode(String source) {
    final document = jsonDecode(source);
    if (document is! Map) {
      throw const TaskRuntimeException('Expected JSON object.');
    }
    return document.map((key, value) => MapEntry('$key', value));
  }

  static void _ensureTransition(TaskStatus from, TaskStatus to) {
    final allowed = switch (from) {
      TaskStatus.backlog => {
        TaskStatus.claimed,
        TaskStatus.blocked,
        TaskStatus.cancelled,
      },
      TaskStatus.claimed => {
        TaskStatus.doing,
        TaskStatus.backlog,
        TaskStatus.blocked,
        TaskStatus.cancelled,
      },
      TaskStatus.doing => {
        TaskStatus.verifying,
        TaskStatus.blocked,
        TaskStatus.backlog,
        TaskStatus.cancelled,
      },
      TaskStatus.verifying => {
        TaskStatus.done,
        TaskStatus.doing,
        TaskStatus.blocked,
        TaskStatus.backlog,
        TaskStatus.cancelled,
      },
      TaskStatus.blocked => {
        TaskStatus.backlog,
        TaskStatus.cancelled,
      },
      TaskStatus.done => <TaskStatus>{},
      TaskStatus.cancelled => <TaskStatus>{},
    };
    if (!allowed.contains(to)) {
      throw TaskRuntimeException(
        'Invalid task transition: ${from.wireName} -> ${to.wireName}',
      );
    }
  }

  Future<void> _ensureKnownDependencies(
    List<AlfredoTask> tasks,
    List<String> dependencies,
  ) async {
    final known = {for (final task in tasks) task.id};
    for (final dependency in dependencies) {
      if (!known.contains(dependency)) {
        throw TaskRuntimeException('Unknown dependency: $dependency');
      }
    }
  }

  static void _ensureAcyclic(
    List<AlfredoTask> tasks,
    String? editedTask,
    List<String> dependencies,
  ) {
    final graph = {
      for (final task in tasks) task.id: task.dependencies,
      ?editedTask: dependencies,
    };
    for (final node in graph.keys) {
      final visiting = <String>{};
      final visited = <String>{};
      bool visit(String current) {
        if (visiting.contains(current)) return true;
        if (visited.contains(current)) return false;
        visiting.add(current);
        for (final next in graph[current] ?? const <String>[]) {
          if (visit(next)) return true;
        }
        visiting.remove(current);
        visited.add(current);
        return false;
      }

      if (visit(node)) {
        throw const TaskRuntimeException('Task dependency cycle rejected.');
      }
    }
  }

  static int _estimateTokens(String value) => (value.length / 4).ceil();

  Future<List<String>> _resolveContextFiles(String pattern) async {
    if (pattern.endsWith('/**')) {
      final prefix = pattern.substring(0, pattern.length - 3);
      final directory = Directory(p.join(projectRoot.path, prefix));
      if (!directory.existsSync()) return const [];
      final files =
          (await directory.list(recursive: true, followLinks: false).toList())
              .whereType<File>()
              .map(
                (file) => p.posix.joinAll(
                  p.split(p.relative(file.path, from: projectRoot.path)),
                ),
              )
              .toList()
            ..sort();
      return List.unmodifiable(files);
    }
    if (pattern.contains('*')) return [pattern];
    final file = File(p.join(projectRoot.path, pattern));
    return file.existsSync() ? [pattern] : const [];
  }

  static void _ensureSafePaths(Iterable<String> paths) {
    for (final path in paths) {
      if (path.isEmpty ||
          path.startsWith('/') ||
          path.contains(r'\') ||
          path.split('/').contains('..')) {
        throw TaskRuntimeException('Unsafe runtime path: $path');
      }
    }
  }

  static DateTime _now() => DateTime.now().toUtc();

  static String _newId(String prefix) {
    const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
    final random = Random.secure();
    final now = DateTime.now().millisecondsSinceEpoch;
    var value = now;
    final time = List.generate(10, (_) {
      final char = alphabet[value & 31];
      value >>= 5;
      return char;
    }).reversed.join();
    final entropy = List.generate(
      10,
      (_) => alphabet[random.nextInt(32)],
    ).join();
    return '$prefix-$time$entropy';
  }

  static List<String> _sortedUnique(Iterable<String> values) {
    return (values.where((value) => value.trim().isNotEmpty).toSet().toList()
      ..sort());
  }
}
