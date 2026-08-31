import 'package:alfredo_cli/src/source/source.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('uses the explicit Alfredo configuration override', () {
    final file = defaultSourceRegistryFile(
      environment: const {'ALFREDO_CONFIG_HOME': '/work/config'},
      operatingSystem: 'linux',
    );

    expect(file.path, p.join('/work/config', 'sources.json'));
  });

  test('uses Application Support on macOS', () {
    final file = defaultSourceRegistryFile(
      environment: const {'HOME': '/Users/alfredo'},
      operatingSystem: 'macos',
    );

    expect(
      file.path,
      p.join(
        '/Users/alfredo',
        'Library',
        'Application Support',
        'Alfredo',
        'sources.json',
      ),
    );
  });

  test('uses XDG_CONFIG_HOME on Linux', () {
    final file = defaultSourceRegistryFile(
      environment: const {
        'HOME': '/home/alfredo',
        'XDG_CONFIG_HOME': '/work/config',
      },
      operatingSystem: 'linux',
    );

    expect(file.path, p.join('/work/config', 'alfredo', 'sources.json'));
  });

  test('uses APPDATA on Windows', () {
    final file = defaultSourceRegistryFile(
      environment: const {'APPDATA': r'C:\Users\Alfredo\AppData\Roaming'},
      operatingSystem: 'windows',
    );

    expect(file.path, endsWith(r'Alfredo\sources.json'));
  });

  test('uses the explicit Alfredo cache override', () {
    final directory = defaultSourceCacheDirectory(
      environment: const {'ALFREDO_CACHE_HOME': '/work/cache'},
      operatingSystem: 'linux',
    );

    expect(directory.path, p.join('/work/cache', 'snapshots'));
  });

  test('uses Cache and XDG cache locations', () {
    final macos = defaultSourceCacheDirectory(
      environment: const {'HOME': '/Users/alfredo'},
      operatingSystem: 'macos',
    );
    final linux = defaultSourceCacheDirectory(
      environment: const {
        'HOME': '/home/alfredo',
        'XDG_CACHE_HOME': '/work/cache',
      },
      operatingSystem: 'linux',
    );

    expect(
      macos.path,
      p.join('/Users/alfredo', 'Library', 'Caches', 'Alfredo', 'snapshots'),
    );
    expect(linux.path, p.join('/work/cache', 'alfredo', 'snapshots'));
  });
}
