import 'dart:io';

import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-memory-paths-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('prefers ALFREDO_MEMORY_HOME over every other override', () {
    final directory = defaultUserMemoryDirectory(
      environment: const {
        'ALFREDO_MEMORY_HOME': '/work/memory',
        'ALFREDO_HOME': '/work/alfredo',
        'HOME': '/home/alfredo',
      },
      operatingSystem: 'linux',
    );

    expect(directory.path, '/work/memory');
  });

  test('places memory below ALFREDO_HOME when it is set', () {
    final directory = defaultUserMemoryDirectory(
      environment: const {
        'ALFREDO_HOME': '/work/alfredo',
        'HOME': '/home/alfredo',
      },
      operatingSystem: 'linux',
    );

    expect(directory.path, p.posix.join('/work/alfredo', 'memory'));
  });

  test('falls back to the home directory on macOS and Linux', () {
    final macos = defaultUserMemoryDirectory(
      environment: const {'HOME': '/Users/alfredo'},
      operatingSystem: 'macos',
    );
    final linux = defaultUserMemoryDirectory(
      environment: const {'HOME': '/home/alfredo'},
      operatingSystem: 'linux',
    );

    expect(macos.path, p.posix.join('/Users/alfredo', '.alfredo', 'memory'));
    expect(linux.path, p.posix.join('/home/alfredo', '.alfredo', 'memory'));
  });

  test('uses USERPROFILE and Windows separators on Windows', () {
    final directory = defaultUserMemoryDirectory(
      environment: const {'USERPROFILE': r'C:\Users\Alfredo'},
      operatingSystem: 'windows',
    );

    expect(directory.path, r'C:\Users\Alfredo\.alfredo\memory');
  });

  test('requires a home directory', () {
    expect(
      () => defaultUserMemoryDirectory(
        environment: const {},
        operatingSystem: 'linux',
      ),
      throwsA(isA<MemoryException>()),
    );
    expect(
      () => defaultUserMemoryDirectory(
        environment: const {},
        operatingSystem: 'windows',
      ),
      throwsA(isA<MemoryException>()),
    );
  });

  test('walks up to the directory that contains .git', () async {
    final repository = await Directory(
      p.join(temporary.path, 'repo'),
    ).create();
    await Directory(p.join(repository.path, '.git')).create();
    final nested = await Directory(
      p.join(repository.path, 'cli', 'lib'),
    ).create(recursive: true);

    final directory = projectMemoryDirectory(nested, environment: const {});

    expect(
      directory.path,
      p.join(repository.path, '.alfredo', 'memory'),
    );
  });

  test('prefers ALFREDO_PROJECT_ROOT over the repository walk', () async {
    final repository = await Directory(
      p.join(temporary.path, 'repo'),
    ).create();
    await Directory(p.join(repository.path, '.git')).create();

    final directory = projectMemoryDirectory(
      repository,
      environment: {'ALFREDO_PROJECT_ROOT': p.join(temporary.path, 'other')},
    );

    expect(
      directory.path,
      p.join(temporary.path, 'other', '.alfredo', 'memory'),
    );
  });

  test('falls back to the start directory outside a repository', () async {
    final directory = projectMemoryDirectory(
      await Directory(p.join(temporary.path, 'loose')).create(),
      environment: const {},
    );

    expect(directory.path, endsWith(p.join('.alfredo', 'memory')));
  });

  test('resolves both roots and the configuration file', () {
    final roots = defaultMemoryRoots(
      environment: {
        'ALFREDO_MEMORY_HOME': p.join(temporary.path, 'user-memory'),
        'ALFREDO_PROJECT_ROOT': temporary.path,
      },
      operatingSystem: 'linux',
    );

    expect(roots.userDirectory.path, p.join(temporary.path, 'user-memory'));
    expect(
      roots.projectDirectory.path,
      p.join(temporary.path, '.alfredo', 'memory'),
    );
    expect(
      memoryConfigFile(roots.userDirectory).path,
      p.join(temporary.path, 'user-memory', 'config.json'),
    );
  });
}
