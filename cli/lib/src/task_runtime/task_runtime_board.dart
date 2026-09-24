import 'package:alfredo_cli/src/task_runtime/task_runtime_models.dart';

/// One task placed on the board, with its computed age.
class TaskBoardEntry {
  /// Creates a board entry.
  const TaskBoardEntry({required this.task, required this.age});

  /// The underlying task.
  final AlfredoTask task;

  /// Time elapsed since the task was created.
  final Duration age;

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
    'blocker': task.blocker,
    'age_seconds': age.inSeconds,
  };
}

/// One named column of the board, holding entries in display order.
class TaskBoardColumn {
  /// Creates a board column.
  const TaskBoardColumn({required this.title, required this.entries});

  /// Column heading, e.g. `READY`.
  final String title;

  /// Entries assigned to this column, already sorted for display.
  final List<TaskBoardEntry> entries;

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'title': title,
    'count': entries.length,
    'tasks': [for (final entry in entries) entry.toJson()],
  };
}

/// A point-in-time snapshot of the durable task runtime, grouped into the
/// columns a terminal board renders: `READY`, `IN_PROGRESS`, and
/// `VERIFYING`, plus a `BLOCKED` column so stuck work is never hidden, and
/// trailing counts for tasks that have already left the active board
/// (`DONE`, `CANCELLED`) and backlog tasks still waiting on dependencies.
class TaskBoard {
  /// Creates a board snapshot.
  const TaskBoard({
    required this.generatedAt,
    required this.columns,
    required this.waitingCount,
    required this.doneCount,
    required this.cancelledCount,
  });

  /// Builds a board snapshot from the current set of durable tasks.
  ///
  /// `now` defaults to [DateTime.now] and is only overridable for tests.
  factory TaskBoard.build({required List<AlfredoTask> tasks, DateTime? now}) {
    final effectiveNow = (now ?? DateTime.now()).toUtc();
    final doneIds = {
      for (final task in tasks)
        if (task.status == TaskStatus.done) task.id,
    };

    TaskBoardEntry entryFor(AlfredoTask task) => TaskBoardEntry(
      task: task,
      age: effectiveNow.difference(task.createdAt.toUtc()),
    );

    int byPriorityThenAge(TaskBoardEntry left, TaskBoardEntry right) {
      final priority = _priorityRank(right.task.priority)
          .compareTo(_priorityRank(left.task.priority));
      if (priority != 0) return priority;
      final created = left.task.createdAt.compareTo(right.task.createdAt);
      if (created != 0) return created;
      return left.task.id.compareTo(right.task.id);
    }

    final ready = <TaskBoardEntry>[];
    final inProgress = <TaskBoardEntry>[];
    final verifying = <TaskBoardEntry>[];
    final blocked = <TaskBoardEntry>[];
    var waitingCount = 0;
    var doneCount = 0;
    var cancelledCount = 0;

    for (final task in tasks) {
      switch (task.status) {
        case TaskStatus.backlog:
          if (task.isClaimable(doneIds)) {
            ready.add(entryFor(task));
          } else {
            waitingCount++;
          }
        case TaskStatus.claimed:
        case TaskStatus.doing:
          inProgress.add(entryFor(task));
        case TaskStatus.verifying:
          verifying.add(entryFor(task));
        case TaskStatus.blocked:
          blocked.add(entryFor(task));
        case TaskStatus.done:
          doneCount++;
        case TaskStatus.cancelled:
          cancelledCount++;
      }
    }

    ready.sort(byPriorityThenAge);
    inProgress.sort(byPriorityThenAge);
    verifying.sort(byPriorityThenAge);
    blocked.sort(byPriorityThenAge);

    return TaskBoard(
      generatedAt: effectiveNow,
      columns: [
        TaskBoardColumn(title: 'READY', entries: ready),
        TaskBoardColumn(title: 'IN_PROGRESS', entries: inProgress),
        TaskBoardColumn(title: 'VERIFYING', entries: verifying),
        TaskBoardColumn(title: 'BLOCKED', entries: blocked),
      ],
      waitingCount: waitingCount,
      doneCount: doneCount,
      cancelledCount: cancelledCount,
    );
  }

  /// When this snapshot was generated.
  final DateTime generatedAt;

  /// Board columns in display order.
  final List<TaskBoardColumn> columns;

  /// Backlog tasks that are not yet claimable (unmet dependencies).
  final int waitingCount;

  /// Tasks already completed.
  final int doneCount;

  /// Tasks intentionally abandoned.
  final int cancelledCount;

  /// JSON representation.
  Map<String, Object?> toJson() => {
    'generated_at': generatedAt.toIso8601String(),
    'columns': [for (final column in columns) column.toJson()],
    'waiting_count': waitingCount,
    'done_count': doneCount,
    'cancelled_count': cancelledCount,
  };

  static int _priorityRank(String value) {
    return switch (value.trim().toLowerCase()) {
      'critical' || 'urgent' || 'p0' => 4,
      'high' || 'p1' => 3,
      'low' || 'p3' => 1,
      'lowest' || 'p4' => 0,
      _ => 2,
    };
  }
}
