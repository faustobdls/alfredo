import 'dart:io';

import 'package:alfredo_cli/src/package/package_models.dart';
import 'package:path/path.dart' as p;

/// Scope in which package content is installed.
enum InstallationScope {
  /// Install in the user's agent configuration directory.
  user,

  /// Install in the current project's agent configuration directory.
  project,
}

/// Caller-supplied roots, making every target safe to test in a temporary tree.
class AgentTargetRoots {
  /// Creates injectable user and project roots.
  const AgentTargetRoots({required this.userRoot, required this.projectRoot});

  /// Directory that represents the user's home/config root.
  final Directory userRoot;

  /// Directory that represents the current project root.
  final Directory projectRoot;
}

/// Resolves injectable installation roots for normal CLI execution.
AgentTargetRoots defaultAgentTargetRoots({
  Map<String, String>? environment,
  Directory? currentDirectory,
}) {
  final env = environment ?? Platform.environment;
  final userOverride = env['ALFREDO_USER_ROOT'];
  final projectOverride = env['ALFREDO_PROJECT_ROOT'];
  final home = env[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  final userRoot = userOverride ?? home;
  if (userRoot == null || userRoot.trim().isEmpty) {
    throw const PackageException(
      'A user home or ALFREDO_USER_ROOT is required for package installation.',
    );
  }
  return AgentTargetRoots(
    userRoot: Directory(userRoot),
    projectRoot: Directory(
      projectOverride ?? (currentDirectory ?? Directory.current).path,
    ),
  );
}

/// Target-specific mapping from canonical package paths to agent directories.
class TargetAdapter {
  /// Creates a target adapter.
  const TargetAdapter({
    required this.id,
    required this.userDirectoryName,
    required this.projectDirectoryName,
  });

  /// Stable target identifier used in package manifests.
  final String id;

  /// Agent configuration directory below the injected user root.
  final String userDirectoryName;

  /// Agent configuration directory below the injected project root.
  final String projectDirectoryName;

  /// Resolves the target configuration root for [scope].
  Directory targetRoot(AgentTargetRoots roots, InstallationScope scope) {
    final base = switch (scope) {
      InstallationScope.user => roots.userRoot,
      InstallationScope.project => roots.projectRoot,
    };
    final directoryName = switch (scope) {
      InstallationScope.user => userDirectoryName,
      InstallationScope.project => projectDirectoryName,
    };
    return Directory(p.join(base.path, directoryName));
  }

  /// Resolves the metadata file outside the target content root.
  File stateFile(AgentTargetRoots roots, InstallationScope scope) {
    final base = switch (scope) {
      InstallationScope.user => roots.userRoot,
      InstallationScope.project => roots.projectRoot,
    };
    return File(
      p.join(
        base.path,
        '.alfredo-state',
        'targets',
        id,
        scope.name,
        'installed.json',
      ),
    );
  }

  /// Resolves the deterministic lockfile for this target and scope.
  File lockfile(AgentTargetRoots roots, InstallationScope scope) {
    final base = switch (scope) {
      InstallationScope.user => roots.userRoot,
      InstallationScope.project => roots.projectRoot,
    };
    return File(
      p.join(
        base.path,
        '.alfredo',
        'runtime',
        'locks',
        id,
        '${scope.name}.lock.json',
      ),
    );
  }
}

/// Built-in adapters for supported agent configuration layouts.
class TargetAdapters {
  /// Codex uses `.codex` for user content and `.agents` for project skills.
  static const codex = TargetAdapter(
    id: 'codex',
    userDirectoryName: '.codex',
    projectDirectoryName: '.agents',
  );

  /// Claude Code uses `.claude` for user and project configuration.
  static const claudeCode = TargetAdapter(
    id: 'claude-code',
    userDirectoryName: '.claude',
    projectDirectoryName: '.claude',
  );

  /// Cursor loads native skills from `.cursor/skills` in both scopes.
  static const cursor = TargetAdapter(
    id: 'cursor',
    userDirectoryName: '.cursor',
    projectDirectoryName: '.cursor',
  );

  /// Antigravity uses Gemini user configuration and portable project skills.
  static const antigravity = TargetAdapter(
    id: 'antigravity',
    userDirectoryName: '.gemini/config',
    projectDirectoryName: '.agents',
  );

  /// Generic Alfredo content uses `.alfredo`.
  static const generic = TargetAdapter(
    id: 'generic',
    userDirectoryName: '.alfredo',
    projectDirectoryName: '.alfredo',
  );

  /// Every built-in adapter, in stable identifier order.
  static const List<TargetAdapter> all = [
    codex,
    claudeCode,
    cursor,
    antigravity,
    generic,
  ];

  /// Returns an adapter by its package target identifier.
  static TargetAdapter forId(String id) {
    return switch (id) {
      'codex' => codex,
      'claude-code' => claudeCode,
      'cursor' => cursor,
      'antigravity' => antigravity,
      'generic' => generic,
      _ => throw PackageException('Unsupported installation target: $id'),
    };
  }
}
