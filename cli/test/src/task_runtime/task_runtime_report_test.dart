import 'package:alfredo_cli/src/task_runtime/task_runtime.dart';
import 'package:test/test.dart';

AlfredoTask _task({
  required String id,
  required TaskStatus status,
  required DateTime createdAt,
  required DateTime updatedAt,
  TaskOwner? owner,
}) {
  return AlfredoTask(
    id: id,
    title: 'Task $id',
    status: status,
    priority: 'normal',
    createdAt: createdAt,
    updatedAt: updatedAt,
    owner: owner,
  );
}

TaskEvent _event({
  required String id,
  required String task,
  required String type,
  required DateTime createdAt,
}) {
  return TaskEvent(id: id, task: task, type: type, createdAt: createdAt);
}

void main() {
  group('TaskRuntimeReport.build', () {
    test('reconstructs time-in-status from a full lifecycle', () {
      final t0 = DateTime.utc(2026, 1, 1, 10);
      final task = _task(
        id: 'ALF-1',
        status: TaskStatus.done,
        createdAt: t0,
        updatedAt: t0.add(const Duration(minutes: 40)),
        owner: const TaskOwner(
          adapter: 'codex',
          agent: 'executor',
          session: 'SES-1',
        ),
      );
      final events = [
        _event(id: 'EVT-1', task: 'ALF-1', type: 'created', createdAt: t0),
        _event(
          id: 'EVT-2',
          task: 'ALF-1',
          type: 'claimed',
          createdAt: t0.add(const Duration(minutes: 5)),
        ),
        _event(
          id: 'EVT-3',
          task: 'ALF-1',
          type: 'started',
          createdAt: t0.add(const Duration(minutes: 10)),
        ),
        _event(
          id: 'EVT-4',
          task: 'ALF-1',
          type: 'verifying',
          createdAt: t0.add(const Duration(minutes: 30)),
        ),
        _event(
          id: 'EVT-5',
          task: 'ALF-1',
          type: 'done',
          createdAt: t0.add(const Duration(minutes: 40)),
        ),
      ];

      final report = TaskRuntimeReport.build(
        tasks: [task],
        eventsByTask: {'ALF-1': events},
        now: t0.add(const Duration(hours: 2)),
      );

      final entry = report.entries.single;
      expect(
        entry.timeInStatus[TaskStatus.backlog],
        const Duration(minutes: 5),
      );
      expect(
        entry.timeInStatus[TaskStatus.claimed],
        const Duration(minutes: 5),
      );
      expect(entry.timeInStatus[TaskStatus.doing], const Duration(minutes: 20));
      expect(
        entry.timeInStatus[TaskStatus.verifying],
        const Duration(minutes: 10),
      );
      expect(entry.verifyDuration, const Duration(minutes: 10));
      expect(entry.age, const Duration(minutes: 40));
      expect(entry.blockedCount, 0);
      expect(report.blockedTasksCount, 0);
      expect(report.countByStatus[TaskStatus.done], 1);
      expect(
        report.doingTimeByAdapter['codex'],
        const Duration(minutes: 20),
      );
      expect(
        report.averageVerifyDuration,
        const Duration(minutes: 10),
      );
    });

    test('counts repeated BLOCKED transitions and uses now for open tasks', () {
      final t0 = DateTime.utc(2026);
      final task = _task(
        id: 'ALF-2',
        status: TaskStatus.doing,
        createdAt: t0,
        updatedAt: t0.add(const Duration(hours: 3)),
      );
      final events = [
        _event(id: 'EVT-1', task: 'ALF-2', type: 'created', createdAt: t0),
        _event(
          id: 'EVT-2',
          task: 'ALF-2',
          type: 'claimed',
          createdAt: t0.add(const Duration(minutes: 1)),
        ),
        _event(
          id: 'EVT-3',
          task: 'ALF-2',
          type: 'started',
          createdAt: t0.add(const Duration(minutes: 2)),
        ),
        _event(
          id: 'EVT-4',
          task: 'ALF-2',
          type: 'blocked',
          createdAt: t0.add(const Duration(hours: 1)),
        ),
        _event(
          id: 'EVT-5',
          task: 'ALF-2',
          type: 'unblocked',
          createdAt: t0.add(const Duration(hours: 1, minutes: 30)),
        ),
        _event(
          id: 'EVT-6',
          task: 'ALF-2',
          type: 'started',
          createdAt: t0.add(const Duration(hours: 2)),
        ),
        _event(
          id: 'EVT-7',
          task: 'ALF-2',
          type: 'blocked',
          createdAt: t0.add(const Duration(hours: 2, minutes: 30)),
        ),
      ];
      final now = t0.add(const Duration(hours: 3));

      final report = TaskRuntimeReport.build(
        tasks: [task],
        eventsByTask: {'ALF-2': events},
        now: now,
      );

      final entry = report.entries.single;
      expect(entry.blockedCount, 2);
      expect(report.blockedTasksCount, 1);
      // Two BLOCKED intervals: 1h->1h30m (unblocked) and 2h30m->3h (now,
      // still open since there is no trailing event).
      expect(
        entry.timeInStatus[TaskStatus.blocked],
        const Duration(hours: 1),
      );
      expect(entry.age, const Duration(hours: 3));
      expect(entry.verifyDuration, isNull);
    });

    test('handles a task with no events gracefully', () {
      final t0 = DateTime.utc(2026);
      final task = _task(
        id: 'ALF-3',
        status: TaskStatus.backlog,
        createdAt: t0,
        updatedAt: t0,
      );
      final report = TaskRuntimeReport.build(
        tasks: [task],
        eventsByTask: const {},
        now: t0.add(const Duration(minutes: 10)),
      );
      final entry = report.entries.single;
      expect(entry.timeInStatus, isEmpty);
      expect(entry.blockedCount, 0);
      expect(entry.verifyDuration, isNull);
      expect(report.averageVerifyDuration, isNull);
    });

    test('serializes to JSON with wire-formatted keys', () {
      final t0 = DateTime.utc(2026);
      final task = _task(
        id: 'ALF-4',
        status: TaskStatus.backlog,
        createdAt: t0,
        updatedAt: t0,
      );
      final report = TaskRuntimeReport.build(
        tasks: [task],
        eventsByTask: const {},
        now: t0,
      );
      final json = report.toJson();
      expect(json['total_tasks'], 1);
      final tasksJson = json['tasks'];
      expect(tasksJson, isA<List<Object?>>());
      final tasksList = tasksJson! as List<Object?>;
      final entryJson = tasksList.single! as Map<String, Object?>;
      expect(entryJson['id'], 'ALF-4');
      expect(entryJson['status'], 'BACKLOG');
    });
  });
}
