import 'package:alfredo_cli/src/task_runtime/task_runtime.dart';
import 'package:test/test.dart';

AlfredoTask _task({
  required String id,
  required TaskStatus status,
  required DateTime createdAt,
  String priority = 'normal',
  List<String> dependencies = const [],
  TaskOwner? owner,
  String? blocker,
}) {
  return AlfredoTask(
    id: id,
    title: 'Task $id',
    status: status,
    priority: priority,
    createdAt: createdAt,
    updatedAt: createdAt,
    dependencies: dependencies,
    owner: owner,
    blocker: blocker,
  );
}

void main() {
  group('TaskBoard.build', () {
    final now = DateTime.utc(2026, 1, 1, 12);

    test('places claimable backlog tasks in READY', () {
      final board = TaskBoard.build(
        tasks: [_task(id: 'ALF-1', status: TaskStatus.backlog, createdAt: now)],
        now: now,
      );

      final ready = board.columns.singleWhere((c) => c.title == 'READY');
      expect(ready.entries.single.task.id, 'ALF-1');
      expect(board.waitingCount, 0);
    });

    test(
      'counts a backlog task with unmet dependencies as waiting, not ready',
      () {
        final board = TaskBoard.build(
          tasks: [
            _task(
              id: 'ALF-2',
              status: TaskStatus.backlog,
              createdAt: now,
              dependencies: ['ALF-1'],
            ),
          ],
          now: now,
        );

        final ready = board.columns.singleWhere((c) => c.title == 'READY');
        expect(ready.entries, isEmpty);
        expect(board.waitingCount, 1);
      },
    );

    test('groups CLAIMED and DOING together under IN_PROGRESS', () {
      final board = TaskBoard.build(
        tasks: [
          _task(id: 'ALF-1', status: TaskStatus.claimed, createdAt: now),
          _task(id: 'ALF-2', status: TaskStatus.doing, createdAt: now),
        ],
        now: now,
      );

      final inProgress = board.columns.singleWhere(
        (c) => c.title == 'IN_PROGRESS',
      );
      expect(
        inProgress.entries.map((e) => e.task.id),
        containsAll(['ALF-1', 'ALF-2']),
      );
    });

    test('places VERIFYING and BLOCKED tasks in their own columns', () {
      final board = TaskBoard.build(
        tasks: [
          _task(id: 'ALF-1', status: TaskStatus.verifying, createdAt: now),
          _task(
            id: 'ALF-2',
            status: TaskStatus.blocked,
            createdAt: now,
            blocker: 'waiting on API key',
          ),
        ],
        now: now,
      );

      final verifying = board.columns.singleWhere(
        (c) => c.title == 'VERIFYING',
      );
      final blocked = board.columns.singleWhere((c) => c.title == 'BLOCKED');
      expect(verifying.entries.single.task.id, 'ALF-1');
      expect(blocked.entries.single.task.id, 'ALF-2');
      expect(blocked.entries.single.task.blocker, 'waiting on API key');
    });

    test('counts DONE and CANCELLED but keeps them off the active board', () {
      final board = TaskBoard.build(
        tasks: [
          _task(id: 'ALF-1', status: TaskStatus.done, createdAt: now),
          _task(id: 'ALF-2', status: TaskStatus.cancelled, createdAt: now),
        ],
        now: now,
      );

      expect(board.doneCount, 1);
      expect(board.cancelledCount, 1);
      for (final column in board.columns) {
        expect(column.entries, isEmpty);
      }
    });

    test('sorts each column by priority then creation order', () {
      final board = TaskBoard.build(
        tasks: [
          _task(
            id: 'ALF-low',
            status: TaskStatus.backlog,
            createdAt: now,
            priority: 'low',
          ),
          _task(
            id: 'ALF-critical',
            status: TaskStatus.backlog,
            createdAt: now.add(const Duration(minutes: 1)),
            priority: 'critical',
          ),
          _task(id: 'ALF-normal', status: TaskStatus.backlog, createdAt: now),
        ],
        now: now,
      );

      final ready = board.columns.singleWhere((c) => c.title == 'READY');
      expect(ready.entries.map((e) => e.task.id), [
        'ALF-critical',
        'ALF-normal',
        'ALF-low',
      ]);
    });

    test('computes age relative to the provided now', () {
      final board = TaskBoard.build(
        tasks: [
          _task(
            id: 'ALF-1',
            status: TaskStatus.doing,
            createdAt: now.subtract(const Duration(minutes: 90)),
          ),
        ],
        now: now,
      );

      final inProgress = board.columns.singleWhere(
        (c) => c.title == 'IN_PROGRESS',
      );
      expect(inProgress.entries.single.age, const Duration(minutes: 90));
    });

    test('serializes to JSON with every column and summary count', () {
      final board = TaskBoard.build(
        tasks: [
          _task(id: 'ALF-1', status: TaskStatus.backlog, createdAt: now),
          _task(id: 'ALF-2', status: TaskStatus.done, createdAt: now),
        ],
        now: now,
      );

      final json = board.toJson();
      expect(json['waiting_count'], 0);
      expect(json['done_count'], 1);
      expect(json['cancelled_count'], 0);
      final columns = json['columns']! as List<dynamic>;
      expect(columns.map((c) => (c as Map)['title']), [
        'READY',
        'IN_PROGRESS',
        'VERIFYING',
        'BLOCKED',
      ]);
      final ready = columns.first as Map;
      expect(ready['count'], 1);
      expect((ready['tasks']! as List).single, isA<Map<String, Object?>>());
    });
  });
}
