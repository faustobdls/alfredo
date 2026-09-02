import 'package:alfredo_cli/src/package/package.dart';
import 'package:alfredo_cli/src/source/source.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// Re-resolves installed packages from their sources and reinstalls changes.
class UpdateCommand extends Command<int> {
  /// Creates the update command.
  UpdateCommand({required this.updater, required this.logger}) {
    argParser
      ..addMultiOption(
        'target',
        allowed: TargetAdapters.supportedIds,
        help: 'Limit the update to specific agent targets.',
      )
      ..addMultiOption(
        'scope',
        allowed: const ['user', 'project'],
        help: 'Limit the update to the user or project scope.',
      )
      ..addMultiOption(
        'package',
        help: 'Limit the update to specific package IDs.',
      )
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Report what would change without writing anything.',
      )
      ..addFlag(
        'refresh-sources',
        defaultsTo: true,
        help: 'Advance Git sources to newer upstream revisions first.',
      );
  }

  /// Re-resolves and reinstalls changed packages.
  final PackageUpdater updater;

  /// Structured output sink.
  final Logger logger;

  @override
  String get description =>
      'Update installed Alfredo skills and packages from their sources.';

  @override
  String get name => 'update';

  @override
  Future<int> run() async {
    final dryRun = argResults!['dry-run'] as bool;
    final targets = (argResults!['target'] as List<String>).toSet();
    final scopeNames = (argResults!['scope'] as List<String>).toSet();
    final packages = (argResults!['package'] as List<String>).toSet();

    final report = await updater.run(
      targets: targets.isEmpty ? null : targets,
      scopes: scopeNames.isEmpty ? null : scopeNames.map(_scope).toSet(),
      packageIds: packages.isEmpty ? null : packages,
      dryRun: dryRun,
      refreshSources: argResults!['refresh-sources'] as bool,
    );

    if (report.sources.isEmpty && report.packages.isEmpty) {
      logger.info('No installed Alfredo packages found.');
      return ExitCode.success.code;
    }

    for (final source in report.sources) {
      logger.info(_sourceLine(source));
    }
    for (final package in report.packages) {
      logger.info(_packageLine(package, dryRun: dryRun));
    }

    if (dryRun) {
      logger.info(
        report.changed
            ? 'Dry run: ${report.updatedPackages} package(s) would be '
                  'updated. No changes written.'
            : 'Dry run: everything is already up to date.',
      );
      return ExitCode.success.code;
    }
    if (report.changed) {
      logger.success(
        'Updated ${report.updatedPackages} package(s); '
        '${report.refreshedSources} source(s) refreshed.',
      );
    } else {
      logger.info('Everything is already up to date.');
    }
    return ExitCode.success.code;
  }

  static InstallationScope _scope(String value) =>
      value == 'project' ? InstallationScope.project : InstallationScope.user;

  static String _sourceLine(SourceUpdate source) {
    switch (source.kind) {
      case SourceRefreshKind.updated:
        return 'refreshed ${source.name}: '
            '${_short(source.previousRevision)}..${_short(source.newRevision)}';
      case SourceRefreshKind.live:
        return '${source.name}: local source (live)';
      case SourceRefreshKind.pinned:
        return '${source.name}: pinned (archive checksum)';
      case SourceRefreshKind.unchanged:
        return '${source.name}: ${source.detail ?? 'source unchanged'}';
    }
  }

  static String _packageLine(PackageUpdate package, {required bool dryRun}) {
    final prefix =
        '${package.target}/${package.scope.name} '
        '${package.packageId}: ';
    switch (package.status) {
      case PackageUpdateStatus.upToDate:
        return '${prefix}up to date';
      case PackageUpdateStatus.updated:
        final verb = dryRun ? 'would update' : 'updated';
        if (package.fromVersion == package.toVersion) {
          final refreshed = dryRun ? 'would refresh' : 'refreshed';
          return '$prefix$refreshed content (${package.toVersion})';
        }
        return '$prefix$verb ${package.fromVersion} -> ${package.toVersion}';
      case PackageUpdateStatus.unavailable:
        return '${prefix}unavailable (${package.detail})';
      case PackageUpdateStatus.skippedModified:
        return '${prefix}skipped (${package.detail})';
    }
  }

  static String _short(String? revision) {
    if (revision == null || revision.isEmpty) return '(unknown)';
    return revision.length <= 7 ? revision : revision.substring(0, 7);
  }
}
