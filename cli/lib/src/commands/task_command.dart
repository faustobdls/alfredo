import 'dart:async';
import 'dart:convert';

import 'package:alfredo_cli/src/task_runtime/task_runtime.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// Manages durable Alfredo tasks.
class TaskCommand extends Command<int> {
  /// Creates the task command group.
  TaskCommand({required TaskRuntimeStore store, required Logger logger}) {
    addSubcommand(_CreateTask(store: store, logger: logger));
    addSubcommand(_ListTasks(store: store, logger: logger));
    addSubcommand(_ReadyTasks(store: store, logger: logger));
    addSubcommand(_ShowTask(store: store, logger: logger));
    addSubcommand(_DependTask(store: store, logger: logger));
    addSubcommand(_ClaimTask(store: store, logger: logger));
    addSubcommand(_SimpleTaskTransition('start', store, logger));
    addSubcommand(_CheckpointTask(store: store, logger: logger));
    addSubcommand(_BlockTask(store: store, logger: logger));
    addSubcommand(_SimpleTaskTransition('unblock', store, logger));
    addSubcommand(_SimpleTaskTransition('verify', store, logger));
    addSubcommand(_SimpleTaskTransition('done', store, logger));
    addSubcommand(_SimpleTaskTransition('release', store, logger));
    addSubcommand(_SimpleTaskTransition('cancel', store, logger));
    addSubcommand(_ResumeTask(store: store, logger: logger));
    addSubcommand(_ReportTasks(store: store, logger: logger));
    addSubcommand(_TaskBoardCommand(store: store, logger: logger));
  }

  @override
  String get description => 'Manage durable task runtime state.';

  @override
  String get name => 'task';
}

abstract class _TaskSubcommand extends Command<int> {
  _TaskSubcommand({required this.store, required this.logger});

  final TaskRuntimeStore store;
  final Logger logger;

  String requireTaskId() {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one task ID.', usage);
    }
    return argResults!.rest.single;
  }

  void output(Object? value, {required bool asJson}) {
    if (asJson) {
      logger.info(prettyJson.convert(value));
    } else {
      logger.info('$value');
    }
  }
}

class _CreateTask extends _TaskSubcommand {
  _CreateTask({required super.store, required super.logger}) {
    argParser
      ..addOption('title', mandatory: true, help: 'Task title.')
      ..addOption('priority', defaultsTo: 'normal', help: 'Priority label.')
      ..addOption('run', help: 'Run ID.')
      ..addMultiOption('depends-on', help: 'Required dependency task IDs.')
      ..addMultiOption('acceptance', help: 'Acceptance criteria.')
      ..addMultiOption('topic', help: 'Context topic.')
      ..addMultiOption('file', help: 'Relevant file.')
      ..addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'Create a durable task.';

  @override
  String get name => 'create';

  @override
  Future<int> run() async {
    final task = await store.createTask(
      title: argResults!['title'] as String,
      priority: argResults!['priority'] as String,
      run: argResults!['run'] as String?,
      dependencies: argResults!['depends-on'] as List<String>,
      acceptance: argResults!['acceptance'] as List<String>,
      context: TaskContextHints(
        topics: argResults!['topic'] as List<String>,
        files: argResults!['file'] as List<String>,
      ),
    );
    if (argResults!['json'] as bool) {
      output(task.toJson(), asJson: true);
    } else {
      logger.success('Created ${task.id}: ${task.title}');
    }
    return ExitCode.success.code;
  }
}

class _ListTasks extends _TaskSubcommand {
  _ListTasks({required super.store, required super.logger}) {
    argParser
      ..addOption('status', help: 'Filter by status or derived READY.')
      ..addOption('owner', help: 'Filter by owner adapter.')
      ..addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'List durable tasks.';

  @override
  String get name => 'list';

  @override
  Future<int> run() async {
    var tasks = await store.listTasks();
    final status = argResults!['status'] as String?;
    if (status != null) {
      if (status.toUpperCase() == 'READY') {
        tasks = await store.readyTasks();
      } else {
        final parsed = TaskStatus.parse(status);
        tasks = tasks.where((task) => task.status == parsed).toList();
      }
    }
    final owner = argResults!['owner'] as String?;
    if (owner != null) {
      tasks = tasks.where((task) => task.owner?.adapter == owner).toList();
    }
    if (argResults!['json'] as bool) {
      output([for (final task in tasks) task.toJson()], asJson: true);
    } else if (tasks.isEmpty) {
      logger.info('No tasks.');
    } else {
      for (final task in tasks) {
        final ownerText = task.owner == null ? '-' : task.owner!.adapter;
        logger.info(
          '${task.id}\t${task.status.wireName}\t$ownerText\t${task.title}',
        );
      }
    }
    return ExitCode.success.code;
  }
}

class _ReadyTasks extends _TaskSubcommand {
  _ReadyTasks({required super.store, required super.logger}) {
    argParser.addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'List tasks eligible to claim.';

  @override
  String get name => 'ready';

  @override
  Future<int> run() async {
    final tasks = await store.readyTasks();
    if (argResults!['json'] as bool) {
      output([for (final task in tasks) task.toJson()], asJson: true);
    } else if (tasks.isEmpty) {
      logger.info('No ready tasks.');
    } else {
      for (final task in tasks) {
        logger.info('${task.id}\tREADY\t${task.title}');
      }
    }
    return ExitCode.success.code;
  }
}

class _ShowTask extends _TaskSubcommand {
  _ShowTask({required super.store, required super.logger}) {
    argParser.addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'Show a task.';

  @override
  String get name => 'show';

  @override
  Future<int> run() async {
    final task = await store.readTask(requireTaskId());
    if (argResults!['json'] as bool) {
      output(task.toJson(), asJson: true);
    } else {
      logger.info(_resumeText(task));
    }
    return ExitCode.success.code;
  }
}

class _ClaimTask extends _TaskSubcommand {
  _ClaimTask({required super.store, required super.logger}) {
    argParser
      ..addOption('adapter', mandatory: true)
      ..addOption('agent', defaultsTo: 'executor')
      ..addOption('session', mandatory: true)
      ..addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'Atomically claim a task.';

  @override
  String get name => 'claim';

  @override
  Future<int> run() async {
    final task = await store.claimTask(
      requireTaskId(),
      adapter: argResults!['adapter'] as String,
      agent: argResults!['agent'] as String,
      session: argResults!['session'] as String,
    );
    if (argResults!['json'] as bool) {
      output(task.toJson(), asJson: true);
    } else {
      logger.success('Claimed ${task.id}.');
    }
    return ExitCode.success.code;
  }
}

class _DependTask extends _TaskSubcommand {
  _DependTask({required super.store, required super.logger}) {
    argParser
      ..addMultiOption('on', help: 'Dependency task ID.')
      ..addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'Add dependencies to a backlog task.';

  @override
  String get name => 'depend';

  @override
  Future<int> run() async {
    if ((argResults!['on'] as List<String>).isEmpty) {
      throw UsageException('Expected at least one --on dependency.', usage);
    }
    final task = await store.addDependencies(
      requireTaskId(),
      dependencies: argResults!['on'] as List<String>,
    );
    if (argResults!['json'] as bool) {
      output(task.toJson(), asJson: true);
    } else {
      logger.success('Updated dependencies for ${task.id}.');
    }
    return ExitCode.success.code;
  }
}

class _SimpleTaskTransition extends _TaskSubcommand {
  _SimpleTaskTransition(this.commandName, TaskRuntimeStore store, Logger logger)
    : super(store: store, logger: logger) {
    argParser.addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  final String commandName;

  @override
  String get description => switch (commandName) {
    'start' => 'Start active work on a claimed task.',
    'unblock' => 'Return a blocked task to backlog.',
    'verify' => 'Move a task into verification.',
    'done' => 'Mark a verified task done.',
    'release' => 'Release ownership for handoff.',
    'cancel' => 'Cancel a task.',
    _ => '$commandName a task.',
  };

  @override
  String get name => commandName;

  @override
  Future<int> run() async {
    final id = requireTaskId();
    final task = switch (commandName) {
      'start' => await store.startTask(id),
      'unblock' => await store.unblockTask(id),
      'verify' => await store.verifyTask(id),
      'done' => await store.doneTask(id),
      'release' => await store.releaseTask(id),
      'cancel' => await store.cancelTask(id),
      _ => throw StateError(commandName),
    };
    if (argResults!['json'] as bool) {
      output(task.toJson(), asJson: true);
    } else {
      logger.success('${task.id}: ${task.status.wireName}');
    }
    return ExitCode.success.code;
  }
}

class _BlockTask extends _TaskSubcommand {
  _BlockTask({required super.store, required super.logger}) {
    argParser
      ..addOption('reason', mandatory: true)
      ..addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'Block a task.';

  @override
  String get name => 'block';

  @override
  Future<int> run() async {
    final task = await store.blockTask(
      requireTaskId(),
      argResults!['reason'] as String,
    );
    if (argResults!['json'] as bool) {
      output(task.toJson(), asJson: true);
    } else {
      logger.success('Blocked ${task.id}.');
    }
    return ExitCode.success.code;
  }
}

class _CheckpointTask extends _TaskSubcommand {
  _CheckpointTask({required super.store, required super.logger}) {
    argParser
      ..addMultiOption('completed')
      ..addOption('current')
      ..addMultiOption('remaining')
      ..addMultiOption('file')
      ..addMultiOption('validation', help: 'Validation in name=value form.')
      ..addOption('next-action')
      ..addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'Persist a compact task checkpoint.';

  @override
  String get name => 'checkpoint';

  @override
  Future<int> run() async {
    final task = await store.checkpointTask(
      requireTaskId(),
      TaskCheckpoint(
        completed: argResults!['completed'] as List<String>,
        current: argResults!['current'] as String?,
        remaining: argResults!['remaining'] as List<String>,
        changedFiles: argResults!['file'] as List<String>,
        validations: _validations(argResults!['validation'] as List<String>),
        nextAction: argResults!['next-action'] as String?,
      ),
    );
    if (argResults!['json'] as bool) {
      output(task.toJson(), asJson: true);
    } else {
      logger.success('Checkpointed ${task.id}.');
    }
    return ExitCode.success.code;
  }

  Map<String, String> _validations(List<String> values) {
    return {
      for (final value in values)
        if (value.contains('='))
          value.split('=').first: value.substring(value.indexOf('=') + 1),
    };
  }
}

class _ResumeTask extends _TaskSubcommand {
  _ResumeTask({required super.store, required super.logger}) {
    argParser.addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'Build a compact handoff packet for a task.';

  @override
  String get name => 'resume';

  @override
  Future<int> run() async {
    final task = await store.readTask(requireTaskId());
    if (argResults!['json'] as bool) {
      output(_resumeJson(task), asJson: true);
    } else {
      logger.info(_resumeText(task));
    }
    return ExitCode.success.code;
  }
}

class _ReportTasks extends _TaskSubcommand {
  _ReportTasks({required super.store, required super.logger}) {
    argParser.addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description =>
      'Summarize time-in-status, blocking rate, and verification speed '
      'across every durable task.';

  @override
  String get name => 'report';

  @override
  Future<int> run() async {
    final tasks = await store.listTasks();
    final eventsByTask = <String, List<TaskEvent>>{
      for (final task in tasks) task.id: await store.listTaskEvents(task.id),
    };
    final report = TaskRuntimeReport.build(
      tasks: tasks,
      eventsByTask: eventsByTask,
    );
    if (argResults!['json'] as bool) {
      output(report.toJson(), asJson: true);
    } else {
      logger.info(_reportText(report));
    }
    return ExitCode.success.code;
  }
}

String _reportText(TaskRuntimeReport report) {
  final buffer = StringBuffer()
    ..writeln('Task Runtime Report — ${report.generatedAt.toIso8601String()}')
    ..writeln('Total tasks: ${report.entries.length}')
    ..writeln('Blocked at least once: ${report.blockedTasksCount}')
    ..writeln(
      'Average VERIFYING -> DONE: '
      '${_formatDuration(report.averageVerifyDuration)}',
    )
    ..writeln()
    ..writeln('By status:');
  for (final status in TaskStatus.values) {
    final count = report.countByStatus[status] ?? 0;
    if (count == 0) continue;
    final time = report.totalTimeByStatus[status] ?? Duration.zero;
    buffer.writeln(
      '  ${status.wireName}: $count task(s), '
      '${_formatDuration(time)} total time',
    );
  }
  if (report.doingTimeByAdapter.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('DOING time by adapter:');
    for (final entry in report.doingTimeByAdapter.entries) {
      buffer.writeln('  ${entry.key}: ${_formatDuration(entry.value)}');
    }
  }
  if (report.entries.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Tasks:');
    for (final entry in report.entries) {
      buffer.writeln(
        '  ${entry.task.id} [${entry.task.status.wireName}] '
        '${entry.task.title} — age ${_formatDuration(entry.age)}, '
        'blocked ${entry.blockedCount}x',
      );
    }
  }
  return buffer.toString().trimRight();
}

String _formatDuration(Duration? duration) {
  if (duration == null) return '-';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

Map<String, Object?> _resumeJson(AlfredoTask task) => {
  'task': task.id,
  'title': task.title,
  'status': task.status.wireName,
  'run': task.run,
  'acceptance': task.acceptance,
  'owner': task.owner?.toJson(),
  'previous_owner': task.previousOwner?.toJson(),
  'completed': task.checkpoint.completed,
  'current': task.checkpoint.current,
  'remaining': task.checkpoint.remaining,
  'relevant_files': {
    'context': task.context.files,
    'changed': task.checkpoint.changedFiles,
  },
  'validations': task.checkpoint.validations,
  'blocker': task.blocker,
  'next_action': task.checkpoint.nextAction,
};

String _resumeText(AlfredoTask task) {
  final buffer = StringBuffer()
    ..writeln('Task: ${task.id}')
    ..writeln('Title: ${task.title}')
    ..writeln('Status: ${task.status.wireName}')
    ..writeln('Run: ${task.run ?? '-'}')
    ..writeln('Owner: ${_owner(task.owner)}')
    ..writeln('Previous owner: ${_owner(task.previousOwner)}')
    ..writeln('Acceptance: ${_join(task.acceptance)}')
    ..writeln('Completed: ${_join(task.checkpoint.completed)}')
    ..writeln('Current: ${task.checkpoint.current ?? '-'}')
    ..writeln('Remaining: ${_join(task.checkpoint.remaining)}')
    ..writeln('Context files: ${_join(task.context.files)}')
    ..writeln('Changed files: ${_join(task.checkpoint.changedFiles)}')
    ..writeln('Validations: ${jsonEncode(task.checkpoint.validations)}')
    ..writeln('Blocker: ${task.blocker ?? '-'}')
    ..writeln('Next action: ${task.checkpoint.nextAction ?? '-'}');
  return buffer.toString().trimRight();
}

String _owner(TaskOwner? owner) {
  if (owner == null) return '-';
  return '${owner.adapter} / ${owner.agent} / ${owner.session}';
}

String _join(List<String> values) => values.isEmpty ? '-' : values.join(', ');

class _TaskBoardCommand extends _TaskSubcommand {
  _TaskBoardCommand({required super.store, required super.logger}) {
    argParser
      ..addFlag('json', negatable: false, help: 'Emit JSON.')
      ..addFlag(
        'watch',
        negatable: false,
        help: 'Redraw the board on an interval until interrupted.',
      )
      ..addOption(
        'interval',
        defaultsTo: '2',
        help: 'Seconds between redraws in --watch mode.',
      )
      ..addOption(
        'max-iterations',
        hide: true,
        help: 'Stops --watch after N redraws. Intended for tests only.',
      );
  }

  @override
  String get description =>
      'Render READY, IN_PROGRESS, VERIFYING, and BLOCKED tasks as a '
      'terminal board.';

  @override
  String get name => 'board';

  @override
  Future<int> run() async {
    final asJson = argResults!['json'] as bool;
    final watch = argResults!['watch'] as bool;
    if (!watch) {
      final board = TaskBoard.build(tasks: await store.listTasks());
      _render(board, asJson: asJson);
      return ExitCode.success.code;
    }

    final intervalSeconds = int.tryParse(argResults!['interval'] as String);
    if (intervalSeconds == null || intervalSeconds <= 0) {
      throw UsageException('--interval must be a positive integer.', usage);
    }
    final interval = Duration(seconds: intervalSeconds);
    final maxIterationsText = argResults!['max-iterations'] as String?;
    final maxIterations = maxIterationsText == null
        ? null
        : int.tryParse(maxIterationsText);
    if (maxIterationsText != null && maxIterations == null) {
      throw UsageException('--max-iterations must be an integer.', usage);
    }

    var iteration = 0;
    while (maxIterations == null || iteration < maxIterations) {
      final board = TaskBoard.build(tasks: await store.listTasks());
      if (!asJson && iteration > 0) logger.info(_clearScreen);
      _render(board, asJson: asJson);
      iteration++;
      if (maxIterations != null && iteration >= maxIterations) break;
      await Future<void>.delayed(interval);
    }
    return ExitCode.success.code;
  }

  void _render(TaskBoard board, {required bool asJson}) {
    if (asJson) {
      output(board.toJson(), asJson: true);
    } else {
      logger.info(_boardText(board));
    }
  }
}

/// ANSI clear-screen + cursor-home, used between --watch redraws so each
/// snapshot replaces the previous one instead of scrolling the terminal.
const _clearScreen = '\x1B[2J\x1B[H';

String _boardText(TaskBoard board) {
  final buffer = StringBuffer()
    ..writeln('Task Board — ${board.generatedAt.toIso8601String()}');
  for (final column in board.columns) {
    final heading = _columnStyle(column.title)
        .wrap('${column.title} (${column.entries.length})');
    buffer
      ..writeln()
      ..writeln(heading);
    if (column.entries.isEmpty) {
      buffer.writeln('  (empty)');
      continue;
    }
    for (final entry in column.entries) {
      final owner = entry.task.owner == null
          ? ''
          : ' · ${entry.task.owner!.adapter}/${entry.task.owner!.agent}';
      final blocker = entry.task.blocker == null
          ? ''
          : ' · blocked: ${entry.task.blocker}';
      buffer.writeln(
        '  ${entry.task.id} [${entry.task.priority}] ${entry.task.title}'
        '$owner$blocker · age ${_formatBoardDuration(entry.age)}',
      );
    }
  }
  buffer
    ..writeln()
    ..writeln(
      'Waiting on dependencies: ${board.waitingCount} · '
      'Done: ${board.doneCount} · Cancelled: ${board.cancelledCount}',
    );
  return buffer.toString().trimRight();
}

AnsiCode _columnStyle(String title) {
  return switch (title) {
    'READY' => cyan,
    'IN_PROGRESS' => yellow,
    'VERIFYING' => magenta,
    'BLOCKED' => red,
    _ => styleBold,
  };
}

String _formatBoardDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}
