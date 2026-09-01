import 'dart:io';

import 'package:path/path.dart' as p;

/// The project and user roots templates are discovered under.
class TemplateRoots {
  /// Creates injectable template roots.
  const TemplateRoots({required this.projectRoot, required this.userRoot});

  /// Repository root of the current project.
  final Directory projectRoot;

  /// The user's home root, where global agent directories live.
  final Directory userRoot;
}

/// Resolves both template roots for normal CLI execution.
TemplateRoots defaultTemplateRoots({
  Map<String, String>? environment,
  Directory? currentDirectory,
}) {
  final env = environment ?? Platform.environment;
  final projectOverride = env['ALFREDO_PROJECT_ROOT'];
  final projectRoot =
      projectOverride != null && projectOverride.trim().isNotEmpty
      ? Directory(projectOverride)
      : _repositoryRoot(currentDirectory ?? Directory.current);

  final userOverride = env['ALFREDO_USER_ROOT'];
  final home = env[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  final userRoot = userOverride ?? home;
  final resolvedUserRoot = userRoot != null && userRoot.trim().isNotEmpty
      ? userRoot
      : projectRoot.path;

  return TemplateRoots(
    projectRoot: projectRoot,
    userRoot: Directory(resolvedUserRoot),
  );
}

/// Agent directory names that can hold an installed `templates/` tree.
const _agentDirectoryNames = <String>[
  '.claude',
  '.agents',
  '.codex',
  '.cursor',
  '.gemini/config',
  '.alfredo',
];

/// Directories to scan for templates, most authoritative first.
///
/// Canonical `templates/` at the project root wins over installed copies, and
/// project-scoped installs win over user-scoped ones.
List<Directory> templateSearchDirs(TemplateRoots roots) {
  Directory agentDir(String base, String name) => Directory(
    p.joinAll([base, ...p.posix.split(name), 'templates']),
  );

  return <Directory>[
    Directory(p.join(roots.projectRoot.path, 'templates')),
    for (final name in _agentDirectoryNames)
      agentDir(roots.projectRoot.path, name),
    for (final name in _agentDirectoryNames)
      agentDir(roots.userRoot.path, name),
  ];
}

Directory _repositoryRoot(Directory start) {
  final origin = Directory(p.normalize(p.absolute(start.path)));
  var current = origin;
  while (true) {
    final git = p.join(current.path, '.git');
    final alfredo = p.join(current.path, '.alfredo');
    if (FileSystemEntity.typeSync(git) != FileSystemEntityType.notFound ||
        FileSystemEntity.typeSync(alfredo) != FileSystemEntityType.notFound) {
      return current;
    }
    final parent = current.parent;
    if (p.equals(parent.path, current.path)) return origin;
    current = parent;
  }
}
