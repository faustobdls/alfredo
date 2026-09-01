import 'package:alfredo_cli/src/task_runtime/task_runtime.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// Builds deterministic task context packages.
class ContextCommand extends Command<int> {
  /// Creates the context command group.
  ContextCommand({required TaskRuntimeStore store, required Logger logger}) {
    addSubcommand(_BuildContext(store: store, logger: logger));
  }

  @override
  String get description => 'Build minimal task context packages.';

  @override
  String get name => 'context';
}

class _BuildContext extends Command<int> {
  _BuildContext({required this.store, required this.logger}) {
    argParser
      ..addOption('target-tokens', defaultsTo: '6000')
      ..addOption('hard-limit-tokens', defaultsTo: '12000')
      ..addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  final TaskRuntimeStore store;
  final Logger logger;

  @override
  String get description => 'Build context for a task.';

  @override
  String get name => 'build';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one task ID.', usage);
    }
    final context = await store.buildContext(
      argResults!.rest.single,
      targetTokens: int.parse(argResults!['target-tokens'] as String),
      hardLimitTokens: int.parse(argResults!['hard-limit-tokens'] as String),
    );
    final json = context.toJson();
    if (argResults!['json'] as bool) {
      logger.info(prettyJson.convert(json));
    } else {
      final budget = json['budget']! as Map<String, Object?>;
      final sources = json['sources']! as Map<String, Object?>;
      logger.info(
        'task: ${context.task}\n'
        'estimated_tokens: ${budget['estimated_tokens']}\n'
        'target_tokens: ${budget['target_tokens']}\n'
        'hard_limit_tokens: ${budget['hard_limit_tokens']}\n'
        'files: ${(sources['files']! as List<String>).join(', ')}\n'
        'missing: ${context.missing.join(', ')}',
      );
    }
    return ExitCode.success.code;
  }
}
