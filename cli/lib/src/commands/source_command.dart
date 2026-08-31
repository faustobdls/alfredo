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
    argParser
      ..addOption(
        'local',
        help: 'Path to a local Alfredo source directory.',
        valueHelp: 'path',
      )
      ..addOption(
        'git',
        help: 'URI of an Alfredo Git repository.',
        valueHelp: 'uri',
      )
      ..addOption(
        'archive',
        help: 'URI of an Alfredo ZIP or tar archive.',
        valueHelp: 'uri',
      )
      ..addOption(
        'revision',
        help: 'Immutable Git revision or commit to resolve.',
        valueHelp: 'revision',
      )
      ..addOption(
        'sha256',
        help: 'Expected SHA-256 digest of an archive.',
        valueHelp: 'digest',
      );
  }

  @override
  String get description => 'Validate and register a source snapshot.';

  @override
  String get name => 'add';

  @override
  Future<int> run() async {
    final name = requireName();
    final local = _option('local');
    final git = _option('git');
    final archive = _option('archive');
    final revision = _option('revision');
    final sha256 = _option('sha256');
    final transports = [local, git, archive].whereType<String>().length;
    if (transports != 1) {
      throw UsageException(
        'Use exactly one of --local, --git, or --archive.',
        usage,
      );
    }
    late final RegisteredSource source;
    if (local != null) {
      if (revision != null || sha256 != null) {
        throw UsageException(
          '--revision and --sha256 cannot be used with --local.',
          usage,
        );
      }
      source = await registry.addLocal(name, local);
    } else if (git != null) {
      if (revision == null || sha256 != null) {
        throw UsageException(
          '--git requires --revision and cannot use --sha256.',
          usage,
        );
      }
      source = await registry.addGit(
        name,
        url: Uri.parse(git),
        revision: revision,
      );
    } else {
      if (sha256 == null || revision != null) {
        throw UsageException(
          '--archive requires --sha256 and cannot use --revision.',
          usage,
        );
      }
      source = await registry.addArchive(
        name,
        url: Uri.parse(archive!),
        sha256: sha256,
      );
    }
    logger.success(
      'Added source ${source.name} (${source.sourceId}) '
      'from ${source.location}.',
    );
    return ExitCode.success.code;
  }

  String? _option(String name) {
    final value = argResults![name] as String?;
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
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
