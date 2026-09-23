import 'package:alfredo_cli/src/task_runtime/task_runtime_models.dart';

/// Event types that represent a durable task status transition, mapped to
/// the [TaskStatus] the task enters when that event is recorded. Other event
/// types (`checkpointed`, `dependencies-updated`) do not change status and
/// are ignored when reconstructing a task's status timeline.
const Map<String, TaskStatus> _statusTransitionEvents = {
  'created': TaskStatus.backlog,
  'claimed': TaskStatus.claimed,
  'started': TaskStatus.doing,
  'blocked': TaskStatus.blocked,
  'unblocked': TaskStatus.backlog,
  'verifying': TaskStatus.verifying,
  'done': TaskStatus.done,
  'cancelled': TaskStatus.cancelled,
  'released': TaskStatus.backlog,
};

/// One reconstructed status interval for a task.
class TaskStatusInterval {
  /// Creates a status interval.
  const TaskStatusInterval({
    required this.status,
    required this.start,
    required this.end,
  });

  /// Status held during this interval.
  final TaskStatus status;

  /// Interval start.
  final DateTime start;

  /// Interval end (may equal `start` for zero-length intervals).
  final DateTime end;

  /// Interval duration.
  Duration get duration => end.difference(start);
}

/// Per-task metrics derived from its persisted event log.
class TaskReportEntry {
  /// Creates a task report entry.
  const TaskReportEntry({
    required this.task,
    required this.age,
    required this.timeInStatus,
    required this.blockedCount,
    this.verifyDuration,
  });

  /// The underlying task.
  final AlfredoTask task;

  /// Total elapsed time since creation (to now, or to completion).
  final Duration age;

  /// Accumulated time spent in each observed status.
  final Map<TaskStatus, Duration> timeInStatus;

  /// Number of times the task transitioned into `BLOCKED`.
  final int blockedCount;

  /// Time between entering `VERIFYING` and reaching `DONE`, when both are
  /// present in the event log.
  final Duration? verifyDuration;

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'id': task.id,
    'title': task.title,
    'status': task.status.wireName,
    'priority': task.priority,
    'owner': task.owner == null
        ? null
        : {
            'adapter': task.owner!.adapter,
            'agent': task.owner!.agent,
            'session': task.owner!.session,
          },
    'age_seconds': age.inSeconds,
    'time_in_status_seconds': {
      for (final entry in timeInStatus.entries)
        entry.key.wireName: entry.value.inSeconds,
    },
    'blocked_count': blockedCount,
    'verify_duration_seconds': verifyDuration?.inSeconds,
  };
}

/// Aggregated task runtime report across every persisted task.
class TaskRuntimeReport {
  /// Creates a report.
  const TaskRuntimeReport({
    required this.generatedAt,
    required this.entries,
    required this.countByStatus,
    required this.totalTimeByStatus,
    required this.blockedTasksCount,
    required this.averageVerifyDuration,
    required this.doingTimeByAdapter,
  });

  /// Builds a report from tasks and their event logs.
  ///
  /// `now` defaults to [DateTime.now] and is only overridable for tests.
  factory TaskRuntimeReport.build({
    required List<AlfredoTask> tasks,
    required Map<String, List<TaskEvent>> eventsByTask,
    DateTime? now,
  }) {
    final effectiveNow = (now ?? DateTime.now()).toUtc();
    final entries = <TaskReportEntry>[];
    final countByStatus = <TaskStatus, int>{};
    final totalTimeByStatus = <TaskStatus, Duration>{};
    final doingTimeByAdapter = <String, Duration>{};
    final verifyDurations = <Duration>[];
    var blockedTasksCount = 0;

    for (final task in tasks) {
      final events = List<TaskEvent>.of(eventsByTask[task.id] ?? const [])
        ..sort((left, right) => left.createdAt.compareTo(right.createdAt));

      final transitions = <MapEntry<DateTime, TaskStatus>>[
        for (final event in events)
          if (_statusTransitionEvents.containsKey(event.type))
            MapEntry(
              event.createdAt.toUtc(),
              _statusTransitionEvents[event.type]!,
            ),
      ];

      final timeInStatus = <TaskStatus, Duration>{};
      var blockedCount = 0;
      DateTime? verifyingAt;
      DateTime? doneAt;

      for (var i = 0; i < transitions.length; i++) {
        final status = transitions[i].value;
        final start = transitions[i].key;
        final isTerminal =
            status == TaskStatus.done || status == TaskStatus.cancelled;
        final end = i + 1 < transitions.length
            ? transitions[i + 1].key
            : (isTerminal ? start : effectiveNow);
        final duration = end.difference(start);
        timeInStatus.update(
          status,
          (value) => value + duration,
          ifAbsent: () => duration,
        );
        if (status == TaskStatus.blocked) blockedCount++;
        if (status == TaskStatus.verifying) verifyingAt = start;
        if (status == TaskStatus.done) doneAt = start;
      }

      Duration? verifyDuration;
      if (verifyingAt != null &&
          doneAt != null &&
          !doneAt.isBefore(verifyingAt)) {
        verifyDuration = doneAt.difference(verifyingAt);
        verifyDurations.add(verifyDuration);
      }

      final age =
          (task.status == TaskStatus.done ||
              task.status == TaskStatus.cancelled)
          ? task.updatedAt.toUtc().difference(task.createdAt.toUtc())
          : effectiveNow.difference(task.createdAt.toUtc());

      entries.add(
        TaskReportEntry(
          task: task,
          age: age,
          timeInStatus: timeInStatus,
          blockedCount: blockedCount,
          verifyDuration: verifyDuration,
        ),
      );

      countByStatus.update(
        task.status,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      for (final entry in timeInStatus.entries) {
        totalTimeByStatus.update(
          entry.key,
          (value) => value + entry.value,
          ifAbsent: () => entry.value,
        );
      }
      if (blockedCount > 0) blockedTasksCount++;

      final doingDuration = timeInStatus[TaskStatus.doing];
      if (doingDuration != null && doingDuration > Duration.zero) {
        final adapter = task.owner?.adapter ?? 'unassigned';
        doingTimeByAdapter.update(
          adapter,
          (value) => value + doingDuration,
          ifAbsent: () => doingDuration,
        );
      }
    }

    Duration? averageVerifyDuration;
    if (verifyDurations.isNotEmpty) {
      final totalMicroseconds = verifyDurations.fold<int>(
        0,
        (sum, duration) => sum + duration.inMicroseconds,
      );
      averageVerifyDuration = Duration(
        microseconds: totalMicroseconds ~/ verifyDurations.length,
      );
    }

    entries.sort(
      (left, right) => right.blockedCount != left.blockedCount
          ? right.blockedCount.compareTo(left.blockedCount)
          : left.task.id.compareTo(right.task.id),
    );

    return TaskRuntimeReport(
      generatedAt: effectiveNow,
      entries: entries,
      countByStatus: countByStatus,
      totalTimeByStatus: totalTimeByStatus,
      blockedTasksCount: blockedTasksCount,
      averageVerifyDuration: averageVerifyDuration,
      doingTimeByAdapter: doingTimeByAdapter,
    );
  }

  /// When the report was generated.
  final DateTime generatedAt;

  /// Per-task metrics, sorted by descending blocked-transition count.
  final List<TaskReportEntry> entries;

  /// Number of tasks currently in each status.
  final Map<TaskStatus, int> countByStatus;

  /// Total accumulated time spent by all tasks in each status.
  final Map<TaskStatus, Duration> totalTimeByStatus;

  /// Number of tasks blocked at least once.
  final int blockedTasksCount;

  /// Average `VERIFYING` -> `DONE` duration across tasks with both events.
  final Duration? averageVerifyDuration;

  /// Total time spent `DOING` grouped by the task's current owner adapter.
  final Map<String, Duration> doingTimeByAdapter;

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'generated_at': generatedAt.toIso8601String(),
    'total_tasks': entries.length,
    'count_by_status': {
      for (final entry in countByStatus.entries)
        entry.key.wireName: entry.value,
    },
    'total_time_by_status_seconds': {
      for (final entry in totalTimeByStatus.entries)
        entry.key.wireName: entry.value.inSeconds,
    },
    'blocked_tasks_count': blockedTasksCount,
    'average_verify_duration_seconds': averageVerifyDuration?.inSeconds,
    'doing_time_by_adapter_seconds': {
      for (final entry in doingTimeByAdapter.entries)
        entry.key: entry.value.inSeconds,
    },
    'tasks': [for (final entry in entries) entry.toJson()],
  };
}
