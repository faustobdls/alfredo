import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:alfredo_cli/src/task_runtime/task_runtime.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// Manages worker sessions.
class SessionCommand extends Command<int> {
  /// Creates the session command group.
  SessionCommand({
    required TaskRuntimeStore store,
    required Logger logger,
    MemoryRoots? memoryRoots,
  }) {
    addSubcommand(_StartSession(store: store, logger: logger));
    addSubcommand(_ListSessions(store: store, logger: logger));
    addSubcommand(_ShowSession(store: store, logger: logger));
    addSubcommand(
      _CloseSession(store: store, logger: logger, memoryRoots: memoryRoots),
    );
  }

  @override
  String get description => 'Manage ephemeral worker sessions.';

  @override
  String get name => 'session';
}

abstract class _SessionSubcommand extends Command<int> {
  _SessionSubcommand({required this.store, required this.logger});

  final TaskRuntimeStore store;
  final Logger logger;

  String requireSessionId() {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one session ID.', usage);
    }
    return argResults!.rest.single;
  }
}

class _StartSession extends _SessionSubcommand {
  _StartSession({required super.store, required super.logger}) {
    argParser
      ..addOption('adapter', mandatory: true)
      ..addOption('agent', defaultsTo: 'executor')
      ..addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'Start a worker session.';

  @override
  String get name => 'start';

  @override
  Future<int> run() async {
    final session = await store.startSession(
      adapter: argResults!['adapter'] as String,
      agent: argResults!['agent'] as String,
    );
    if (argResults!['json'] as bool) {
      logger.info(prettyJson.convert(session.toJson()));
    } else {
      logger.success('Started ${session.id}.');
    }
    return ExitCode.success.code;
  }
}

class _ListSessions extends _SessionSubcommand {
  _ListSessions({required super.store, required super.logger}) {
    argParser.addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'List sessions.';

  @override
  String get name => 'list';

  @override
  Future<int> run() async {
    final sessions = await store.listSessions();
    if (argResults!['json'] as bool) {
      logger.info(
        prettyJson.convert([for (final item in sessions) item.toJson()]),
      );
    } else if (sessions.isEmpty) {
      logger.info('No sessions.');
    } else {
      for (final session in sessions) {
        logger.info(
          '${session.id}\t${session.status.wireName}\t'
          '${session.adapter}\t${session.agent}',
        );
      }
    }
    return ExitCode.success.code;
  }
}

class _ShowSession extends _SessionSubcommand {
  _ShowSession({required super.store, required super.logger}) {
    argParser.addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'Show a session.';

  @override
  String get name => 'show';

  @override
  Future<int> run() async {
    final session = await store.readSession(requireSessionId());
    logger.info(
      (argResults!['json'] as bool)
          ? prettyJson.convert(session.toJson())
          : '${session.id}\n'
                'status: ${session.status.wireName}\n'
                'adapter: ${session.adapter}\n'
                'agent: ${session.agent}\n'
                'tasks_claimed: ${session.tasksClaimed.join(', ')}\n'
                'tasks_worked: ${session.tasksWorked.join(', ')}\n'
                'close_reason: ${session.closeReason ?? '-'}',
    );
    return ExitCode.success.code;
  }
}

class _CloseSession extends _SessionSubcommand {
  _CloseSession({
    required super.store,
    required super.logger,
    this.memoryRoots,
  }) {
    argParser
      ..addOption(
        'reason',
        defaultsTo: 'manual',
        allowed: const [
          'completed',
          'manual',
          'context-limit',
          'provider-limit',
          'crash-recovery',
          'handoff',
          'unknown',
        ],
      )
      ..addFlag(
        'capture-memory',
        negatable: false,
        help: 'Append a compact project memory entry for this session close.',
      )
      ..addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  final MemoryRoots? memoryRoots;

  @override
  String get description => 'Close a worker session.';

  @override
  String get name => 'close';

  @override
  Future<int> run() async {
    final session = await store.closeSession(
      requireSessionId(),
      reason: argResults!['reason'] as String,
    );
    final shouldCaptureMemory = await _shouldCaptureMemory();
    if (shouldCaptureMemory) {
      final roots = memoryRoots ?? defaultMemoryRoots();
      final memory = MemoryStore(directory: roots.projectDirectory);
      await memory.ensureSkeleton();
      await memory.appendActivity(
        message:
            'session ${session.id} ended (${session.closeReason}); '
            'claimed: ${_compactList(session.tasksClaimed)}; '
            'worked: ${_compactList(session.tasksWorked)}; '
            'task checkpoints persisted in .alfredo/tasks/',
        tags: const ['session', 'task-runtime'],
      );
    }
    if (argResults!['json'] as bool) {
      logger.info(prettyJson.convert(session.toJson()));
    } else {
      logger.success('Closed ${session.id}: ${session.closeReason}.');
    }
    return ExitCode.success.code;
  }

  Future<bool> _shouldCaptureMemory() async {
    if (argResults!['capture-memory'] as bool) return true;
    final roots = memoryRoots ?? defaultMemoryRoots();
    final memory = MemoryStore(directory: roots.projectDirectory);
    if (!memory.configFile.existsSync()) return false;
    return (await memory.readConfig()).capture.sessionEndHook;
  }
}

String _compactList(List<String> values) =>
    values.isEmpty ? '-' : values.join(', ');
