import 'dart:io';

import 'package:alfredo_cli/src/memory/memory_models.dart';
import 'package:path/path.dart' as p;

/// The user and project memory directories resolved for one invocation.
class MemoryRoots {
  /// Creates injectable memory roots.
  const MemoryRoots({
    required this.userDirectory,
    required this.projectDirectory,
  });

  /// Memory directory shared by every project of the current user.
  final Directory userDirectory;

  /// Memory directory owned by the current repository.
  final Directory projectDirectory;
}

/// Resolves both memory directories for normal CLI execution.
MemoryRoots defaultMemoryRoots({
  Map<String, String>? environment,
  String? operatingSystem,
  Directory? currentDirectory,
}) {
  final env = environment ?? Platform.environment;
  return MemoryRoots(
    userDirectory: defaultUserMemoryDirectory(
      environment: env,
      operatingSystem: operatingSystem,
    ),
    projectDirectory: projectMemoryDirectory(
      currentDirectory ?? Directory.current,
      environment: env,
    ),
  );
}

/// Resolves the user memory directory for the current platform.
Directory defaultUserMemoryDirectory({
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final env = environment ?? Platform.environment;
  final os = operatingSystem ?? Platform.operatingSystem;
  final context = os == 'windows'
      ? p.Context(style: p.Style.windows)
      : p.Context(style: p.Style.posix);

  final memoryHome = env['ALFREDO_MEMORY_HOME'];
  if (memoryHome != null && memoryHome.trim().isNotEmpty) {
    return Directory(memoryHome);
  }

  final alfredoHome = env['ALFREDO_HOME'];
  if (alfredoHome != null && alfredoHome.trim().isNotEmpty) {
    return Directory(context.join(alfredoHome, 'memory'));
  }

  if (os == 'windows') {
    final home = env['USERPROFILE'];
    if (home == null || home.isEmpty) {
      throw const MemoryException('USERPROFILE is required on Windows.');
    }
    return Directory(context.join(home, '.alfredo', 'memory'));
  }

  final home = env['HOME'];
  if (home == null || home.isEmpty) {
    throw const MemoryException('HOME is required to store Alfredo memory.');
  }
  return Directory(context.join(home, '.alfredo', 'memory'));
}

/// Resolves the project memory directory for the repository containing [start].
Directory projectMemoryDirectory(
  Directory start, {
  Map<String, String>? environment,
}) {
  final env = environment ?? Platform.environment;
  final override = env['ALFREDO_PROJECT_ROOT'];
  final root = override != null && override.trim().isNotEmpty
      ? Directory(override)
      : _repositoryRoot(start);
  return Directory(p.join(root.path, '.alfredo', 'memory'));
}

/// Resolves the configuration file of a memory directory.
File memoryConfigFile(Directory memoryDirectory) =>
    File(p.join(memoryDirectory.path, 'config.json'));

Directory _repositoryRoot(Directory start) {
  final origin = Directory(p.normalize(p.absolute(start.path)));
  var current = origin;
  while (true) {
    final marker = p.join(current.path, '.git');
    if (FileSystemEntity.typeSync(marker) != FileSystemEntityType.notFound) {
      return current;
    }
    final parent = current.parent;
    if (p.equals(parent.path, current.path)) return origin;
    current = parent;
  }
}
