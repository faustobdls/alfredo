import 'package:alfredo_cli/src/package/package.dart';
import 'package:alfredo_cli/src/source/source.dart';
import 'package:alfredo_cli/src/version.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// Bootstraps the official source and installs Alfredo for selected agents.
class SetupCommand extends Command<int> {
  /// Creates the setup command.
  SetupCommand({
    required this.registry,
    required this.catalog,
    required this.resolver,
    required this.installer,
    required this.roots,
    required this.logger,
    Uri? officialRepository,
    String? officialRevision,
  }) : officialRepository =
           officialRepository ??
           Uri.parse('https://github.com/faustobdls/alfredo.git'),
       officialRevision = officialRevision ?? 'v$packageVersion' {
    argParser
      ..addFlag(
        'all',
        negatable: false,
        help: 'Install for every supported agent.',
      )
      ..addFlag('codex', negatable: false, help: 'Install for Codex.')
      ..addFlag(
        'claude',
        aliases: const ['claude-code'],
        negatable: false,
        help: 'Install for Claude Code.',
      )
      ..addFlag('cursor', negatable: false, help: 'Install for Cursor.')
      ..addFlag(
        'antigravity',
        negatable: false,
        help: 'Install for Antigravity.',
      )
      ..addOption(
        'scope',
        defaultsTo: 'user',
        allowed: const ['user', 'project'],
        help: 'Install for the user or current project.',
      );
  }

  /// Registry used to bootstrap the official source.
  final SourceRegistry registry;

  /// Catalog used to find official packages.
  final PackageCatalog catalog;

  /// Dependency resolver used for each target.
  final PackageResolver resolver;

  /// Transactional package installer.
  final PackageInstaller installer;

  /// User and project target roots.
  final AgentTargetRoots roots;

  /// User-facing command logger.
  final Logger logger;

  /// Official Git repository used when no Alfredo source is registered.
  final Uri officialRepository;

  /// Immutable official revision associated with this CLI release.
  final String officialRevision;

  @override
  String get description =>
      'Install official Alfredo packages for one or more agents.';

  @override
  String get name => 'setup';

  @override
  Future<int> run() async {
    if (argResults!.rest.isNotEmpty) {
      throw UsageException(
        'Setup does not accept positional arguments.',
        usage,
      );
    }
    final targets = _selectedTargets();
    final source = await _ensureOfficialSource();
    final candidates = (await catalog.discover())
        .where((candidate) => candidate.sourceName == source.name)
        .toList();
    if (candidates.isEmpty) {
      throw const PackageException(
        'The official Alfredo source does not contain any packages.',
      );
    }

    final scope = switch (argResults!['scope'] as String) {
      'project' => InstallationScope.project,
      _ => InstallationScope.user,
    };
    for (final target in targets) {
      final packageIds =
          candidates
              .where((candidate) => candidate.manifest.targets.contains(target))
              .map((candidate) => candidate.manifest.id)
              .toSet()
              .toList()
            ..sort();
      if (packageIds.isEmpty) {
        logger.info('No official packages support $target; skipping.');
        continue;
      }
      final resolution = await resolver.resolve(
        packageIds: packageIds,
        target: target,
        sourceName: source.name,
      );
      final result = await installer.install(
        resolution: resolution,
        roots: roots,
        scope: scope,
      );
      logger.success(
        'Installed ${result.lockfile.packages.length} package(s) for '
        '$target (${scope.name}).',
      );
    }
    return ExitCode.success.code;
  }

  List<String> _selectedTargets() {
    const flags = {
      'codex': 'codex',
      'claude': 'claude-code',
      'cursor': 'cursor',
      'antigravity': 'antigravity',
    };
    final all = argResults!['all'] as bool;
    final selected = [
      for (final entry in flags.entries)
        if (argResults![entry.key] as bool) entry.value,
    ];
    if (all && selected.isNotEmpty) {
      throw UsageException(
        '--all cannot be combined with individual agent flags.',
        usage,
      );
    }
    if (!all && selected.isEmpty) {
      throw UsageException(
        'Select --all or at least one agent flag.',
        usage,
      );
    }
    return all ? flags.values.toList() : selected;
  }

  Future<RegisteredSource> _ensureOfficialSource() async {
    final sources = await registry.list();
    final officialSources = sources
        .where((source) => source.sourceId == 'alfredo')
        .toList();
    if (officialSources.isNotEmpty) {
      final source = officialSources.first;
      final transport = source.transport;
      if (source.kind == SourceKind.git &&
          transport?.url == officialRepository.toString() &&
          transport?.revision != officialRevision) {
        logger.info('Refreshing official Alfredo source...');
        return registry.replaceGit(
          source.name,
          url: officialRepository,
          revision: officialRevision,
        );
      }
      return source;
    }
    if (sources.any((source) => source.name == 'alfredo')) {
      throw const SourceException(
        'Source name "alfredo" is already used by a different source.',
      );
    }
    logger.info('Adding official Alfredo source...');
    return registry.addGit(
      'alfredo',
      url: officialRepository,
      revision: officialRevision,
    );
  }
}
