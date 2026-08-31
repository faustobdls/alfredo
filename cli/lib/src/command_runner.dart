import 'package:alfredo_cli/src/commands/package_command.dart';
import 'package:alfredo_cli/src/commands/setup_command.dart';
import 'package:alfredo_cli/src/commands/source_command.dart';
import 'package:alfredo_cli/src/package/package.dart';
import 'package:alfredo_cli/src/source/source.dart';
import 'package:alfredo_cli/src/version.dart';
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';

const executableName = 'alfredo';
const description =
    'Gerenciador multiplataforma de skills e ferramentas do Alfredo.';

/// {@template alfredo_cli_command_runner}
/// The root command runner for the Alfredo CLI.
///
/// ```bash
/// $ alfredo --version
/// ```
/// {@endtemplate}
class AlfredoCliCommandRunner extends CompletionCommandRunner<int> {
  /// {@macro alfredo_cli_command_runner}
  AlfredoCliCommandRunner({
    Logger? logger,
    SourceRegistry? sourceRegistry,
    PackageCatalog? packageCatalog,
    PackageResolver? packageResolver,
    PackageInstaller? packageInstaller,
    AgentTargetRoots? targetRoots,
  }) : _logger = logger ?? Logger(),
       super(executableName, description) {
    argParser
      ..addFlag(
        'version',
        abbr: 'v',
        negatable: false,
        help: 'Print the current version.',
      )
      ..addFlag(
        'verbose',
        help: 'Show detailed command information.',
      );
    final registry =
        sourceRegistry ?? SourceRegistry(file: defaultSourceRegistryFile());
    final catalog = packageCatalog ?? PackageCatalog(registry: registry);
    final resolver = packageResolver ?? PackageResolver(catalog);
    final installer = packageInstaller ?? const PackageInstaller();
    final roots = targetRoots ?? defaultAgentTargetRoots();
    addCommand(SourceCommand(registry: registry, logger: _logger));
    addCommand(
      SetupCommand(
        registry: registry,
        catalog: catalog,
        resolver: resolver,
        installer: installer,
        roots: roots,
        logger: _logger,
      ),
    );
    addCommand(
      PackageCommand(
        catalog: catalog,
        resolver: resolver,
        installer: installer,
        roots: roots,
        logger: _logger,
      ),
    );
  }

  final Logger _logger;

  @override
  void printUsage() => _logger.info(usage);

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      return await runCommand(parse(args)) ?? ExitCode.success.code;
    } on FormatException catch (error, stackTrace) {
      _logger
        ..err(error.message)
        ..detail('$stackTrace')
        ..info('')
        ..info(usage);
      return ExitCode.usage.code;
    } on UsageException catch (error) {
      _logger
        ..err(error.message)
        ..info('')
        ..info(error.usage);
      return ExitCode.usage.code;
    } on SourceException catch (error) {
      _logger.err(error.message);
      return ExitCode.config.code;
    } on PackageException catch (error) {
      _logger.err(error.message);
      return ExitCode.config.code;
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.command?.name == 'completion') {
      await super.runCommand(topLevelResults);
      return ExitCode.success.code;
    }

    if (topLevelResults['verbose'] == true) {
      _logger.level = Level.verbose;
      _logArguments(topLevelResults);
    }

    if (topLevelResults['version'] == true) {
      _logger.info(packageVersion);
      return ExitCode.success.code;
    }

    if (topLevelResults.command == null) {
      printUsage();
      return ExitCode.success.code;
    }

    return super.runCommand(topLevelResults);
  }

  void _logArguments(ArgResults results) {
    _logger
      ..detail('Argument information:')
      ..detail('  Top level options:');
    for (final option in results.options) {
      if (results.wasParsed(option)) {
        _logger.detail('  - $option: ${results[option]}');
      }
    }
  }
}
