import 'package:alfredo_cli/src/task_runtime/task_runtime.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// Manages durable runs.
class RunCommand extends Command<int> {
  /// Creates the run command group.
  RunCommand({required TaskRuntimeStore store, required Logger logger}) {
    addSubcommand(_CreateRun(store: store, logger: logger));
    addSubcommand(_ListRuns(store: store, logger: logger));
    addSubcommand(_ShowRun(store: store, logger: logger));
  }

  @override
  String get description => 'Manage durable task runs.';

  @override
  String get name => 'run';
}

abstract class _RunSubcommand extends Command<int> {
  _RunSubcommand({required this.store, required this.logger});

  final TaskRuntimeStore store;
  final Logger logger;
}

class _CreateRun extends _RunSubcommand {
  _CreateRun({required super.store, required super.logger}) {
    argParser
      ..addOption('title', mandatory: true)
      ..addOption('summary')
      ..addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'Create a run.';

  @override
  String get name => 'create';

  @override
  Future<int> run() async {
    final run = await store.createRun(
      title: argResults!['title'] as String,
      summary: argResults!['summary'] as String?,
    );
    if (argResults!['json'] as bool) {
      logger.info(prettyJson.convert(run.toJson()));
    } else {
      logger.success('Created ${run.id}: ${run.title}');
    }
    return ExitCode.success.code;
  }
}

class _ListRuns extends _RunSubcommand {
  _ListRuns({required super.store, required super.logger}) {
    argParser.addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'List runs.';

  @override
  String get name => 'list';

  @override
  Future<int> run() async {
    final runs = await store.listRuns();
    if (argResults!['json'] as bool) {
      logger.info(prettyJson.convert([for (final run in runs) run.toJson()]));
    } else if (runs.isEmpty) {
      logger.info('No runs.');
    } else {
      for (final run in runs) {
        logger.info('${run.id}\t${run.title}\t${run.tasks.length} task(s)');
      }
    }
    return ExitCode.success.code;
  }
}

class _ShowRun extends _RunSubcommand {
  _ShowRun({required super.store, required super.logger}) {
    argParser.addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'Show a run.';

  @override
  String get name => 'show';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one run ID.', usage);
    }
    final run = await store.readRun(argResults!.rest.single);
    if (argResults!['json'] as bool) {
      logger.info(prettyJson.convert(run.toJson()));
    } else {
      logger.info(
        '${run.id}\n'
        'title: ${run.title}\n'
        'summary: ${run.summary ?? '-'}\n'
        'tasks: ${run.tasks.join(', ')}',
      );
    }
    return ExitCode.success.code;
  }
}
