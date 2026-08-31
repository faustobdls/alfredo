import 'dart:io';

import 'package:alfredo_cli/src/package/package_manifest_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every package shipped in this repository must load, validate, and resolve
/// its declared content against the repository root.
void main() {
  final repoRoot = Directory.current.parent.path;
  final packagesDir = Directory(p.join(repoRoot, 'packages'));
  const loader = PackageManifestLoader();

  final packageDirs =
      packagesDir
          .listSync()
          .whereType<Directory>()
          .where((dir) => File(p.join(dir.path, 'package.yaml')).existsSync())
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('the repository ships the expected core packages', () {
    expect(
      packageDirs.map((dir) => p.basename(dir.path)).toSet(),
      containsAll(<String>[
        'android-core',
        'memory-core',
        'agents-core',
        'rules-core',
        'skills-core',
      ]),
    );
  });

  for (final dir in packageDirs) {
    final id = p.basename(dir.path);
    test('package "$id" validates and its declared content exists', () async {
      final manifest = await loader.load(dir.path);
      expect(manifest.id, id);
      expect(manifest.targets, isNotEmpty);

      final files = await loader.filesForContents(repoRoot, manifest);
      final declaredKinds = manifest.contents.entries
          .where((entry) => entry.value.isNotEmpty)
          .map((entry) => entry.key);
      if (declaredKinds.isNotEmpty) {
        expect(files, isNotEmpty);
        for (final file in files) {
          expect(file.existsSync(), isTrue, reason: file.path);
        }
      }
    });
  }
}
