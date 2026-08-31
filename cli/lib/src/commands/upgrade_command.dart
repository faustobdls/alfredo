import 'package:alfredo_cli/src/upgrade/upgrade.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// Updates the Alfredo CLI binary to the latest published release.
class UpgradeCommand extends Command<int> {
  /// Creates the upgrade command.
  UpgradeCommand({required this.updater, required this.logger}) {
    argParser
      ..addFlag(
        'check',
        negatable: false,
        help: 'Report whether a newer release exists without installing it.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Reinstall the latest release even if it is already current.',
      );
  }

  /// Downloads, verifies, and swaps the executable.
  final SelfUpdater updater;

  /// Structured output sink.
  final Logger logger;

  @override
  String get description => 'Update the Alfredo CLI to the latest release.';

  @override
  String get name => 'upgrade';

  @override
  Future<int> run() async {
    final checkOnly = argResults!['check'] as bool;
    final outcome = await updater.run(
      checkOnly: checkOnly,
      force: argResults!['force'] as bool,
    );

    if (outcome.applied) {
      logger.success(
        'Upgraded Alfredo ${outcome.previousVersion} -> '
        '${outcome.latestVersion}.',
      );
      final note = outcome.note;
      if (note != null) logger.warn(note);
      return ExitCode.success.code;
    }

    if (checkOnly && outcome.updateAvailable) {
      logger.info(
        'Update available: ${outcome.previousVersion} -> '
        '${outcome.latestVersion}. Run: alfredo upgrade',
      );
      return ExitCode.success.code;
    }

    logger.info(
      'Alfredo is already up to date (${outcome.previousVersion}).',
    );
    return ExitCode.success.code;
  }
}
