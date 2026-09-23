import 'dart:io';

import 'package:alfredo_cli/src/package/package.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-adapters-test-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test('falls back to built-ins when directory does not exist', () async {
    final loader = DeclarativeAdapterLoader(
      adaptersDirectory: Directory(p.join(temporary.path, 'non-existent')),
    );
    final adapters = await loader.loadAll();
    expect(adapters, TargetAdapters.all);
  });

  test('loads valid custom adapters from adapter.yaml', () async {
    final customDir = Directory(p.join(temporary.path, 'custom-agent'))
      ..createSync();
    final yamlFile = File(p.join(customDir.path, 'adapter.yaml'));
    await yamlFile.writeAsString('''
schema: alfredo.adapter/v1
id: custom-agent
user_directory: .custom-user
project_directory: .custom-project
configuration_markers:
  - config.json
''');

    final loader = DeclarativeAdapterLoader(adaptersDirectory: temporary);
    final adapters = await loader.loadAll();

    final custom = adapters.firstWhere((a) => a.id == 'custom-agent');
    expect(custom.userDirectoryName, '.custom-user');
    expect(custom.projectDirectoryName, '.custom-project');
    expect(custom.configurationMarkers, ['config.json']);
  });

  test('overrides built-in adapters with the same id', () async {
    final claudeDir = Directory(p.join(temporary.path, 'claude-code'))
      ..createSync();
    final yamlFile = File(p.join(claudeDir.path, 'adapter.yaml'));
    await yamlFile.writeAsString('''
schema: alfredo.adapter/v1
id: claude-code
user_directory: .custom-claude
project_directory: .custom-claude
''');

    final loader = DeclarativeAdapterLoader(adaptersDirectory: temporary);
    final adapters = await loader.loadAll();

    final claude = adapters.firstWhere((a) => a.id == 'claude-code');
    expect(claude.userDirectoryName, '.custom-claude');
    expect(claude.projectDirectoryName, '.custom-claude');
  });
}
