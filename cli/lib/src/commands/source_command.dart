import 'package:alfredo_cli/src/source/source.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// Manages the configured Alfredo catalog sources.
class SourceCommand extends Command<int> {
  /// Creates the source command group.
  SourceCommand({required SourceRegistry registry, required Logger logger}) {
    addSubcommand(_AddSourceCommand(registry: registry, logger: logger));
    addSubcommand(_ListSourcesCommand(registry: registry, logger: logger));
    addSubcommand(_ShowSourceCommand(registry: registry, logger: logger));
    addSubcommand(_TestSourceCommand(registry: registry, logger: logger));
    addSubcommand(_RemoveSourceCommand(registry: registry, logger: logger));
  }

  @override
  String get description => 'Manage read-only Alfredo package sources.';

  @override
  String get name => 'source';
}

abstract class _SourceSubcommand extends Command<int> {
  _SourceSubcommand({required this.registry, required this.logger});

  final SourceRegistry registry;
  final Logger logger;

  String requireName() {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one source name.', usage);
    }
    return argResults!.rest.single;
  }
}

class _AddSourceCommand extends _SourceSubcommand {
  _AddSourceCommand({required super.registry, required super.logger}) {
    argParser.addOption(
      'local',
      help: 'Path to a local Alfredo source directory.',
      valueHelp: 'path',
    );
  }

  @override
  String get description => 'Validate and register a local source.';

  @override
  String get name => 'add';

  @override
  Future<int> run() async {
    final name = requireName();
    final path = argResults!['local'] as String?;
    if (path == null || path.trim().isEmpty) {
      throw UsageException('The --local option is required.', usage);
    }
    final source = await registry.addLocal(name, path);
    logger.success(
      'Added source ${source.name} (${source.sourceId}) '
      'from ${source.location}.',
    );
    return ExitCode.success.code;
  }
}

class _ListSourcesCommand extends _SourceSubcommand {
  _ListSourcesCommand({required super.registry, required super.logger});

  @override
  String get description => 'List registered sources.';

  @override
  String get name => 'list';

  @override
  Future<int> run() async {
    final sources = await registry.list();
    if (sources.isEmpty) {
      logger.info('No sources registered.');
      return ExitCode.success.code;
    }
    for (final source in sources) {
      logger.info(
        '${source.name}\t${source.kind.name}\t${source.location}',
      );
    }
    return ExitCode.success.code;
  }
}

class _ShowSourceCommand extends _SourceSubcommand {
  _ShowSourceCommand({required super.registry, required super.logger});

  @override
  String get description => 'Show a registered source.';

  @override
  String get name => 'show';

  @override
  Future<int> run() async {
    final source = await registry.get(requireName());
    logger.info(
      'name: ${source.name}\n'
      'kind: ${source.kind.name}\n'
      'source_id: ${source.sourceId}\n'
      'source_name: ${source.sourceName}\n'
      'location: ${source.location}',
    );
    return ExitCode.success.code;
  }
}

class _TestSourceCommand extends _SourceSubcommand {
  _TestSourceCommand({required super.registry, required super.logger});

  @override
  String get description => 'Revalidate a registered source.';

  @override
  String get name => 'test';

  @override
  Future<int> run() async {
    final name = requireName();
    final catalog = await registry.test(name);
    logger.success(
      'Source $name is valid (${catalog.packages.length} packages).',
    );
    return ExitCode.success.code;
  }
}

class _RemoveSourceCommand extends _SourceSubcommand {
  _RemoveSourceCommand({required super.registry, required super.logger});

  @override
  String get description => 'Remove a source registration.';

  @override
  String get name => 'remove';

  @override
  Future<int> run() async {
    final source = await registry.remove(requireName());
    logger.success('Removed source ${source.name}.');
    return ExitCode.success.code;
  }
}
