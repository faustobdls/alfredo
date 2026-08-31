import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  const command = 'alfredo memory capture --scope user';
  const writer = HookWriter();

  late Directory temporary;
  late File settings;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-memory-hook-');
    settings = File(p.join(temporary.path, '.claude', 'settings.json'));
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  Future<Map<String, Object?>> read() async =>
      jsonDecode(await settings.readAsString()) as Map<String, Object?>;

  test('creates a settings file that did not exist', () async {
    expect(await writer.ensureStopHook(settings, command), isTrue);

    final document = await read();
    final hooks = document['hooks']! as Map<String, Object?>;

    expect(hooks.keys, ['Stop', 'SessionEnd']);
    expect(hooks['Stop'], [
      {
        'hooks': [
          {'type': 'command', 'command': command},
        ],
      },
    ]);
    expect(File('${settings.path}.alfredo-bak').existsSync(), isFalse);
  });

  test('merges into an empty settings object', () async {
    await settings.parent.create(recursive: true);
    await settings.writeAsString('{}');

    expect(await writer.ensureStopHook(settings, command), isTrue);
    expect((await read())['hooks'], isA<Map<String, Object?>>());
  });

  test('preserves unrelated keys and existing hooks', () async {
    await settings.parent.create(recursive: true);
    await settings.writeAsString(
      jsonEncode({
        'model': 'opus',
        'permissions': {
          'allow': ['Bash'],
        },
        'hooks': {
          'Stop': [
            {
              'hooks': [
                {'type': 'command', 'command': 'other-tool'},
              ],
            },
          ],
          'PreToolUse': <Object?>[],
        },
      }),
    );

    expect(await writer.ensureStopHook(settings, command), isTrue);

    final document = await read();
    final hooks = document['hooks']! as Map<String, Object?>;

    expect(document['model'], 'opus');
    expect(document['permissions'], {
      'allow': ['Bash'],
    });
    expect(hooks['PreToolUse'], isEmpty);
    expect(hooks['Stop'], hasLength(2));
    expect(
      ((hooks['Stop']! as List).first as Map)['hooks'],
      [
        {'type': 'command', 'command': 'other-tool'},
      ],
    );
  });

  test('copies a backup before the first modification', () async {
    await settings.parent.create(recursive: true);
    await settings.writeAsString('{"model": "opus"}');

    await writer.ensureStopHook(settings, command);

    expect(
      await File('${settings.path}.alfredo-bak').readAsString(),
      '{"model": "opus"}',
    );
  });

  test('is idempotent on a second run', () async {
    expect(await writer.ensureStopHook(settings, command), isTrue);
    final first = await settings.readAsString();

    expect(await writer.ensureStopHook(settings, command), isFalse);

    expect(await settings.readAsString(), first);
  });

  test('adds only the missing event on a partial installation', () async {
    await settings.parent.create(recursive: true);
    await settings.writeAsString(
      jsonEncode({
        'hooks': {
          'Stop': [
            {
              'hooks': [
                {'type': 'command', 'command': command},
              ],
            },
          ],
        },
      }),
    );

    expect(await writer.ensureStopHook(settings, command), isTrue);

    final hooks = (await read())['hooks']! as Map<String, Object?>;
    expect(hooks['Stop'], hasLength(1));
    expect(hooks['SessionEnd'], hasLength(1));
  });

  test('refuses to edit an unparseable settings file', () async {
    await settings.parent.create(recursive: true);
    await settings.writeAsString('not json at all');

    await expectLater(
      writer.ensureStopHook(settings, command),
      throwsA(isA<MemoryException>()),
    );
    expect(await settings.readAsString(), 'not json at all');
  });

  test('refuses a settings file whose root is not an object', () async {
    await settings.parent.create(recursive: true);
    await settings.writeAsString('[1, 2, 3]');

    await expectLater(
      writer.ensureStopHook(settings, command),
      throwsA(isA<MemoryException>()),
    );
  });

  test('refuses malformed hook sections', () async {
    await settings.parent.create(recursive: true);
    await settings.writeAsString('{"hooks": "yes"}');
    await expectLater(
      writer.ensureStopHook(settings, command),
      throwsA(isA<MemoryException>()),
    );

    await settings.writeAsString('{"hooks": {"Stop": "yes"}}');
    await expectLater(
      writer.ensureStopHook(settings, command),
      throwsA(isA<MemoryException>()),
    );
  });
}
