import 'dart:convert';

/// User-facing task runtime failures.
class TaskRuntimeException implements Exception {
  /// Creates an actionable runtime error.
  const TaskRuntimeException(this.message);

  /// Human-readable error.
  final String message;

  @override
  String toString() => message;
}

/// Durable task lifecycle states.
enum TaskStatus {
  /// Waiting for dependencies or a future claim.
  backlog,

  /// Claimed by a session but not yet actively running.
  claimed,

  /// Being implemented.
  doing,

  /// Awaiting or undergoing verification.
  verifying,

  /// Cannot proceed until a blocker is resolved.
  blocked,

  /// Accepted and complete.
  done,

  /// Intentionally abandoned.
  cancelled;

  /// Parses a persisted or CLI status.
  static TaskStatus parse(String value) {
    return switch (value.toUpperCase()) {
      'BACKLOG' => backlog,
      'READY' => backlog,
      'CLAIMED' => claimed,
      'DOING' => doing,
      'VERIFYING' => verifying,
      'BLOCKED' => blocked,
      'DONE' => done,
      'CANCELLED' => cancelled,
      _ => throw TaskRuntimeException('Unsupported task status: $value'),
    };
  }

  /// Persisted representation.
  String get wireName => name.toUpperCase();
}

/// A task owner claim.
class TaskOwner {
  /// Creates an owner.
  const TaskOwner({
    required this.adapter,
    required this.agent,
    required this.session,
  });

  /// Creates an owner from JSON.
  factory TaskOwner.fromJson(Map<String, Object?> json) {
    final adapter = _string(json, 'adapter');
    final agent = _string(json, 'agent');
    final session = _string(json, 'session');
    return TaskOwner(adapter: adapter, agent: agent, session: session);
  }

  /// Adapter/provider identifier.
  final String adapter;

  /// Agent role.
  final String agent;

  /// Session identifier.
  final String session;

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'adapter': adapter,
    'agent': agent,
    'session': session,
  };
}

/// A compact operational checkpoint.
class TaskCheckpoint {
  /// Creates a checkpoint.
  const TaskCheckpoint({
    this.completed = const [],
    this.current,
    this.remaining = const [],
    this.changedFiles = const [],
    this.validations = const {},
    this.nextAction,
  });

  /// Creates a checkpoint from JSON.
  factory TaskCheckpoint.fromJson(Map<String, Object?> json) {
    return TaskCheckpoint(
      completed: _stringList(json, 'completed'),
      current: _optionalString(json, 'current'),
      remaining: _stringList(json, 'remaining'),
      changedFiles: _stringList(json, 'changed_files'),
      validations: _stringMap(json, 'validations'),
      nextAction: _optionalString(json, 'next_action'),
    );
  }

  /// Completed work.
  final List<String> completed;

  /// Current focus.
  final String? current;

  /// Remaining work.
  final List<String> remaining;

  /// Files changed or considered relevant by the worker.
  final List<String> changedFiles;

  /// Validation names and compact outcomes.
  final Map<String, String> validations;

  /// Next operational action.
  final String? nextAction;

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'completed': completed,
    'current': current,
    'remaining': remaining,
    'changed_files': changedFiles,
    'validations': validations,
    'next_action': nextAction,
  };

  /// Returns a merged checkpoint.
  TaskCheckpoint merge(TaskCheckpoint update) {
    return TaskCheckpoint(
      completed: _mergeList(completed, update.completed),
      current: update.current ?? current,
      remaining: update.remaining.isEmpty ? remaining : update.remaining,
      changedFiles: _mergeList(changedFiles, update.changedFiles),
      validations: {...validations, ...update.validations},
      nextAction: update.nextAction ?? nextAction,
    );
  }
}

/// One append-only task event.
class TaskEvent {
  /// Creates a task event.
  const TaskEvent({
    required this.id,
    required this.task,
    required this.type,
    required this.createdAt,
    this.data = const {},
  });

  /// Creates a task event from JSON.
  factory TaskEvent.fromJson(Map<String, Object?> json) {
    if (json['schema'] != eventSchema) {
      throw const TaskRuntimeException('Unsupported task event schema.');
    }
    return TaskEvent(
      id: _string(json, 'id'),
      task: _string(json, 'task'),
      type: _string(json, 'type'),
      createdAt: DateTime.parse(_string(json, 'created_at')),
      data: Map.unmodifiable(_map(json['data'] ?? const {})),
    );
  }

  /// Schema identifier.
  static const eventSchema = 'alfredo.task-event/v1';

  /// Event ID.
  final String id;

  /// Task ID.
  final String task;

  /// Compact event type.
  final String type;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Small event payload.
  final Map<String, Object?> data;

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'schema': eventSchema,
    'id': id,
    'task': task,
    'type': type,
    'created_at': createdAt.toUtc().toIso8601String(),
    'data': data,
  };
}

/// Task context hints.
class TaskContextHints {
  /// Creates context hints.
  const TaskContextHints({this.topics = const [], this.files = const []});

  /// Creates hints from JSON.
  factory TaskContextHints.fromJson(Map<String, Object?> json) {
    return TaskContextHints(
      topics: _stringList(json, 'topics'),
      files: _stringList(json, 'files'),
    );
  }

  /// Context topic identifiers.
  final List<String> topics;

  /// Explicit file references.
  final List<String> files;

  /// JSON representation.
  Map<String, Object?> toJson() => {'topics': topics, 'files': files};
}

/// A durable Alfredo task.
class AlfredoTask {
  /// Creates a task.
  const AlfredoTask({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
    this.run,
    this.owner,
    this.previousOwner,
    this.dependencies = const [],
    this.acceptance = const [],
    this.context = const TaskContextHints(),
    this.checkpoint = const TaskCheckpoint(),
    this.blocker,
  });

  /// Creates a task from JSON.
  factory AlfredoTask.fromJson(Map<String, Object?> json) {
    if (json['schema'] != taskSchema) {
      throw const TaskRuntimeException('Unsupported task schema.');
    }
    final owner = json['owner'];
    final previousOwner = json['previous_owner'];
    return AlfredoTask(
      id: _string(json, 'id'),
      title: _string(json, 'title'),
      status: TaskStatus.parse(_string(json, 'status')),
      priority: _string(json, 'priority'),
      run: _optionalString(json, 'run'),
      createdAt: DateTime.parse(_string(json, 'created_at')),
      updatedAt: DateTime.parse(_string(json, 'updated_at')),
      owner: owner == null ? null : TaskOwner.fromJson(_map(owner)),
      previousOwner: previousOwner == null
          ? null
          : TaskOwner.fromJson(_map(previousOwner)),
      dependencies: _stringList(json, 'dependencies'),
      acceptance: _stringList(json, 'acceptance'),
      context: TaskContextHints.fromJson(_map(json['context'] ?? const {})),
      checkpoint: TaskCheckpoint.fromJson(
        _map(json['checkpoint'] ?? const {}),
      ),
      blocker: _optionalString(json, 'blocker'),
    );
  }

  /// Schema identifier.
  static const taskSchema = 'alfredo.task/v1';

  /// Task ID.
  final String id;

  /// Title.
  final String title;

  /// Persisted lifecycle state.
  final TaskStatus status;

  /// Priority label.
  final String priority;

  /// Optional run ID.
  final String? run;

  /// Creation timestamp.
  final DateTime createdAt;

  /// Last update timestamp.
  final DateTime updatedAt;

  /// Current owner.
  final TaskOwner? owner;

  /// Last released owner.
  final TaskOwner? previousOwner;

  /// Required dependencies.
  final List<String> dependencies;

  /// Acceptance criteria.
  final List<String> acceptance;

  /// Context hints.
  final TaskContextHints context;

  /// Current operational checkpoint.
  final TaskCheckpoint checkpoint;

  /// Current blocker.
  final String? blocker;

  /// Returns true when the task can be claimed now.
  bool isClaimable(Set<String> doneDependencies) {
    return status == TaskStatus.backlog &&
        owner == null &&
        dependencies.every(doneDependencies.contains);
  }

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'schema': taskSchema,
    'id': id,
    'title': title,
    'status': status.wireName,
    'priority': priority,
    'run': run,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'owner': owner?.toJson(),
    'previous_owner': previousOwner?.toJson(),
    'dependencies': dependencies,
    'acceptance': acceptance,
    'context': context.toJson(),
    'checkpoint': checkpoint.toJson(),
    'blocker': blocker,
  };

  /// Returns a modified task.
  AlfredoTask copyWith({
    String? title,
    TaskStatus? status,
    String? priority,
    Object? run = _sentinel,
    DateTime? updatedAt,
    Object? owner = _sentinel,
    Object? previousOwner = _sentinel,
    List<String>? dependencies,
    List<String>? acceptance,
    TaskContextHints? context,
    TaskCheckpoint? checkpoint,
    Object? blocker = _sentinel,
  }) {
    return AlfredoTask(
      id: id,
      title: title ?? this.title,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      run: identical(run, _sentinel) ? this.run : run as String?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      owner: identical(owner, _sentinel) ? this.owner : owner as TaskOwner?,
      previousOwner: identical(previousOwner, _sentinel)
          ? this.previousOwner
          : previousOwner as TaskOwner?,
      dependencies: dependencies ?? this.dependencies,
      acceptance: acceptance ?? this.acceptance,
      context: context ?? this.context,
      checkpoint: checkpoint ?? this.checkpoint,
      blocker: identical(blocker, _sentinel)
          ? this.blocker
          : blocker as String?,
    );
  }
}

/// Session lifecycle states.
enum SessionStatus {
  /// Session is active.
  active,

  /// Session is closed.
  closed;

  /// Wire name.
  String get wireName => name.toUpperCase();
}

/// A durable worker session.
class AlfredoSession {
  /// Creates a session.
  const AlfredoSession({
    required this.id,
    required this.adapter,
    required this.agent,
    required this.startedAt,
    required this.updatedAt,
    required this.status,
    this.endedAt,
    this.closeReason,
    this.tasksClaimed = const [],
    this.tasksWorked = const [],
    this.lastCheckpoint,
  });

  /// Creates a session from JSON.
  factory AlfredoSession.fromJson(Map<String, Object?> json) {
    if (json['schema'] != sessionSchema) {
      throw const TaskRuntimeException('Unsupported session schema.');
    }
    return AlfredoSession(
      id: _string(json, 'id'),
      adapter: _string(json, 'adapter'),
      agent: _string(json, 'agent'),
      startedAt: DateTime.parse(_string(json, 'started_at')),
      updatedAt: DateTime.parse(_string(json, 'updated_at')),
      status: switch (_string(json, 'status')) {
        'ACTIVE' => SessionStatus.active,
        'CLOSED' => SessionStatus.closed,
        final value => throw TaskRuntimeException(
          'Unsupported session status: $value',
        ),
      },
      endedAt: _optionalString(json, 'ended_at') == null
          ? null
          : DateTime.parse(_optionalString(json, 'ended_at')!),
      closeReason: _optionalString(json, 'close_reason'),
      tasksClaimed: _stringList(json, 'tasks_claimed'),
      tasksWorked: _stringList(json, 'tasks_worked'),
      lastCheckpoint: _optionalString(json, 'last_checkpoint'),
    );
  }

  /// Schema identifier.
  static const sessionSchema = 'alfredo.session/v1';

  /// Session ID.
  final String id;

  /// Adapter/provider label.
  final String adapter;

  /// Agent role.
  final String agent;

  /// Start time.
  final DateTime startedAt;

  /// Last update.
  final DateTime updatedAt;

  /// Session status.
  final SessionStatus status;

  /// End time.
  final DateTime? endedAt;

  /// Close reason.
  final String? closeReason;

  /// Tasks claimed by this session.
  final List<String> tasksClaimed;

  /// Tasks worked by this session.
  final List<String> tasksWorked;

  /// Last checkpoint summary.
  final String? lastCheckpoint;

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'schema': sessionSchema,
    'id': id,
    'adapter': adapter,
    'agent': agent,
    'started_at': startedAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'status': status.wireName,
    'ended_at': endedAt?.toUtc().toIso8601String(),
    'close_reason': closeReason,
    'tasks_claimed': tasksClaimed,
    'tasks_worked': tasksWorked,
    'last_checkpoint': lastCheckpoint,
  };

  /// Returns a modified session.
  AlfredoSession copyWith({
    DateTime? updatedAt,
    SessionStatus? status,
    Object? endedAt = _sentinel,
    Object? closeReason = _sentinel,
    List<String>? tasksClaimed,
    List<String>? tasksWorked,
    Object? lastCheckpoint = _sentinel,
  }) {
    return AlfredoSession(
      id: id,
      adapter: adapter,
      agent: agent,
      startedAt: startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      endedAt: identical(endedAt, _sentinel)
          ? this.endedAt
          : endedAt as DateTime?,
      closeReason: identical(closeReason, _sentinel)
          ? this.closeReason
          : closeReason as String?,
      tasksClaimed: tasksClaimed ?? this.tasksClaimed,
      tasksWorked: tasksWorked ?? this.tasksWorked,
      lastCheckpoint: identical(lastCheckpoint, _sentinel)
          ? this.lastCheckpoint
          : lastCheckpoint as String?,
    );
  }
}

/// A durable run grouping tasks under one objective.
class AlfredoRun {
  /// Creates a run.
  const AlfredoRun({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.summary,
    this.tasks = const [],
  });

  /// Creates a run from JSON.
  factory AlfredoRun.fromJson(Map<String, Object?> json) {
    if (json['schema'] != runSchema) {
      throw const TaskRuntimeException('Unsupported run schema.');
    }
    return AlfredoRun(
      id: _string(json, 'id'),
      title: _string(json, 'title'),
      summary: _optionalString(json, 'summary'),
      createdAt: DateTime.parse(_string(json, 'created_at')),
      updatedAt: DateTime.parse(_string(json, 'updated_at')),
      tasks: _stringList(json, 'tasks'),
    );
  }

  /// Schema identifier.
  static const runSchema = 'alfredo.run/v1';

  /// Run ID.
  final String id;

  /// Objective title.
  final String title;

  /// Optional summary.
  final String? summary;

  /// Creation time.
  final DateTime createdAt;

  /// Last update.
  final DateTime updatedAt;

  /// Task IDs in this run.
  final List<String> tasks;

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'schema': runSchema,
    'id': id,
    'title': title,
    'summary': summary,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'tasks': tasks,
  };
}

/// A built context package.
class AlfredoContextPackage {
  /// Creates a context package.
  const AlfredoContextPackage({
    required this.task,
    required this.targetTokens,
    required this.hardLimitTokens,
    required this.estimatedTokens,
    required this.sources,
    required this.missing,
  });

  /// Task ID.
  final String task;

  /// Target estimated token budget.
  final int targetTokens;

  /// Hard estimated token budget.
  final int hardLimitTokens;

  /// Estimated tokens using a deterministic cheap heuristic.
  final int estimatedTokens;

  /// Sources grouped by kind.
  final Map<String, List<String>> sources;

  /// Missing references.
  final List<String> missing;

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'schema': 'alfredo.context/v1',
    'task': task,
    'budget': {
      'target_tokens': targetTokens,
      'hard_limit_tokens': hardLimitTokens,
      'estimated_tokens': estimatedTokens,
      'estimator': 'ceil(chars / 4)',
    },
    'sources': sources,
    'missing': missing,
  };
}

/// Pretty JSON encoder used by CLI output.
const prettyJson = JsonEncoder.withIndent('  ');

const Object _sentinel = Object();

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw TaskRuntimeException('Invalid or missing string field: $key');
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw TaskRuntimeException('Invalid string field: $key');
}

List<String> _stringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List) {
    throw TaskRuntimeException('Invalid list field: $key');
  }
  return List.unmodifiable(
    value.map((item) {
      if (item is! String) {
        throw TaskRuntimeException('Invalid list item in: $key');
      }
      return item;
    }),
  );
}

Map<String, String> _stringMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const {};
  if (value is! Map) {
    throw TaskRuntimeException('Invalid map field: $key');
  }
  return Map.unmodifiable(
    value.map((mapKey, item) {
      if (item is! String) {
        throw TaskRuntimeException('Invalid map item in: $key');
      }
      return MapEntry('$mapKey', item);
    }),
  );
}

Map<String, Object?> _map(Object? value) {
  if (value == null) return const {};
  if (value is! Map) {
    throw const TaskRuntimeException('Invalid object field.');
  }
  return value.map((key, item) => MapEntry('$key', item));
}

List<String> _mergeList(List<String> left, List<String> right) {
  final values = <String>{...left, ...right}.toList()..sort();
  return List.unmodifiable(values);
}
