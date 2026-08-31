import 'package:alfredo_cli/src/package/package.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

/// Discovers, resolves, and installs Alfredo packages.
class PackageCommand extends Command<int> {
  /// Creates the package command group.
  PackageCommand({
    required PackageCatalog catalog,
    required PackageResolver resolver,
    required PackageInstaller installer,
    required AgentTargetRoots roots,
    required Logger logger,
  }) {
    addSubcommand(_ListPackages(catalog: catalog, logger: logger));
    addSubcommand(_SearchPackages(catalog: catalog, logger: logger));
    addSubcommand(_ShowPackage(catalog: catalog, logger: logger));
    addSubcommand(
      _InstallPackage(
        resolver: resolver,
        installer: installer,
        roots: roots,
        logger: logger,
      ),
    );
    addSubcommand(
      _PackageStateCommand(
        name: 'status',
        description: 'Show the state of Alfredo-managed files.',
        installer: installer,
        roots: roots,
        logger: logger,
      ),
    );
    addSubcommand(
      _PackageStateCommand(
        name: 'diff',
        description: 'Show missing or locally modified managed files.',
        installer: installer,
        roots: roots,
        logger: logger,
        changedOnly: true,
      ),
    );
    addSubcommand(
      _UninstallPackage(
        installer: installer,
        roots: roots,
        logger: logger,
      ),
    );
  }

  @override
  String get description => 'Discover and install versioned Alfredo packages.';

  @override
  String get name => 'package';
}

abstract class _CatalogCommand extends Command<int> {
  _CatalogCommand({required this.catalog, required this.logger});

  final PackageCatalog catalog;
  final Logger logger;
}

class _ListPackages extends _CatalogCommand {
  _ListPackages({required super.catalog, required super.logger});

  @override
  String get description => 'List packages from registered sources.';

  @override
  String get name => 'list';

  @override
  Future<int> run() async {
    final packages = await catalog.discover();
    if (packages.isEmpty) {
      logger.info('No packages available.');
      return ExitCode.success.code;
    }
    for (final package in packages) {
      logger.info(
        '${package.manifest.id}\t${package.manifest.version}\t'
        '${package.sourceName}',
      );
    }
    return ExitCode.success.code;
  }
}

class _SearchPackages extends _CatalogCommand {
  _SearchPackages({required super.catalog, required super.logger});

  @override
  String get description => 'Search package IDs, names, and descriptions.';

  @override
  String get name => 'search';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected one search query.', usage);
    }
    final query = argResults!.rest.single.toLowerCase();
    final packages = (await catalog.discover()).where((candidate) {
      final manifest = candidate.manifest;
      return manifest.id.toLowerCase().contains(query) ||
          manifest.name.toLowerCase().contains(query) ||
          manifest.description.toLowerCase().contains(query);
    });
    var found = false;
    for (final package in packages) {
      found = true;
      logger.info(
        '${package.manifest.id}\t${package.manifest.version}\t'
        '${package.sourceName}',
      );
    }
    if (!found) logger.info('No packages matched "$query".');
    return ExitCode.success.code;
  }
}

class _ShowPackage extends _CatalogCommand {
  _ShowPackage({required super.catalog, required super.logger});

  @override
  String get description => 'Show package metadata from every matching source.';

  @override
  String get name => 'show';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected one package ID.', usage);
    }
    final id = argResults!.rest.single;
    final packages = (await catalog.discover())
        .where((candidate) => candidate.manifest.id == id)
        .toList();
    if (packages.isEmpty) {
      throw PackageException('Package is not available: $id');
    }
    for (final package in packages) {
      final manifest = package.manifest;
      logger.info(
        'id: ${manifest.id}\n'
        'name: ${manifest.name}\n'
        'version: ${manifest.version}\n'
        'source: ${package.sourceName}\n'
        'digest: ${package.digest}\n'
        'targets: ${manifest.targets.join(', ')}\n'
        'description: ${manifest.description}',
      );
    }
    return ExitCode.success.code;
  }
}

abstract class _TargetCommand extends Command<int> {
  _TargetCommand({
    required this.installer,
    required this.roots,
    required this.logger,
  }) {
    argParser
      ..addOption(
        'target',
        mandatory: true,
        allowed: const [
          'codex',
          'claude-code',
          'cursor',
          'antigravity',
          'generic',
        ],
        help: 'Agent environment to manage.',
      )
      ..addOption(
        'scope',
        defaultsTo: 'user',
        allowed: const ['user', 'project'],
        help: 'Install for the user or current project.',
      );
  }

  final PackageInstaller installer;
  final AgentTargetRoots roots;
  final Logger logger;

  String get target {
    if (!argResults!.wasParsed('target')) {
      throw UsageException('Missing required option --target.', usage);
    }
    return argResults!['target'] as String;
  }

  InstallationScope get scope => switch (argResults!['scope'] as String) {
    'project' => InstallationScope.project,
    _ => InstallationScope.user,
  };
}

class _InstallPackage extends _TargetCommand {
  _InstallPackage({
    required this.resolver,
    required super.installer,
    required super.roots,
    required super.logger,
  });

  final PackageResolver resolver;

  @override
  String get description => 'Resolve and transactionally install packages.';

  @override
  String get name => 'install';

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('Expected at least one package ID.', usage);
    }
    final resolution = await resolver.resolve(
      packageIds: argResults!.rest,
      target: target,
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
    return ExitCode.success.code;
  }
}

class _PackageStateCommand extends _TargetCommand {
  _PackageStateCommand({
    required this.name,
    required this.description,
    required super.installer,
    required super.roots,
    required super.logger,
    this.changedOnly = false,
  });

  @override
  final String name;

  @override
  final String description;

  final bool changedOnly;

  @override
  Future<int> run() async {
    final statuses = await installer.status(
      target: target,
      roots: roots,
      scope: scope,
    );
    final visible = changedOnly
        ? statuses.where(
            (entry) => entry.condition != ManagedFileCondition.unchanged,
          )
        : statuses;
    if (visible.isEmpty) {
      logger.info(
        changedOnly ? 'No managed file changes.' : 'No managed files.',
      );
      return ExitCode.success.code;
    }
    for (final entry in visible) {
      logger.info('${entry.condition.name}\t${entry.file.path}');
    }
    return ExitCode.success.code;
  }
}

class _UninstallPackage extends _TargetCommand {
  _UninstallPackage({
    required super.installer,
    required super.roots,
    required super.logger,
  });

  @override
  String get description => 'Remove unchanged Alfredo-managed package files.';

  @override
  String get name => 'uninstall';

  @override
  Future<int> run() async {
    final ids = argResults!.rest.isEmpty ? null : argResults!.rest;
    final statuses = await installer.uninstall(
      target: target,
      roots: roots,
      scope: scope,
      packageIds: ids,
    );
    final modified = statuses
        .where((entry) => entry.condition == ManagedFileCondition.modified)
        .length;
    logger.success(
      'Uninstall completed for $target; $modified modified file(s) preserved.',
    );
    return ExitCode.success.code;
  }
}
