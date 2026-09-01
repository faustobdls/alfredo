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
  _SimpleTaskTransition(
    this.commandName,
    TaskRuntimeStore store,
    Logger logger,
  ) : super(store: store, logger: logger) {
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
      ..addMultiOption(
        'validation',
        help: 'Validation in name=value form.',
      )
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
