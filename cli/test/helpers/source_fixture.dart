import 'dart:io';

import 'package:path/path.dart' as p;

Future<Directory> createSourceFixture(
  Directory parent, {
  String sourceId = 'test-source',
  String packageId = 'android-core',
  String version = '1.2.3',
}) async {
  final source = await Directory(p.join(parent.path, sourceId)).create();
  await File(p.join(source.path, 'alfredo-source.yaml')).writeAsString('''
schema_version: 1
id: $sourceId
name: Test Source
kind: local
path: .
read_only: true
packages_path: packages
''');
  final package = await Directory(
    p.join(source.path, 'packages', packageId),
  ).create(recursive: true);
  await File(p.join(package.path, 'package.yaml')).writeAsString('''
schema_version: 1
id: $packageId
name: Android Core
version: $version
description: Test package.
license: MIT
targets: [codex]
contents:
  skills: []
  rules: []
dependencies: []
conflicts: []
''');
  return source;
}
