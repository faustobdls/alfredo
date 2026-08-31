import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Map<String, JsonSchema> schemas;

  setUpAll(() async {
    schemas = {
      for (final name in [
        'source',
        'package',
        'profile',
        'lockfile',
        'installed-state',
      ])
        name: await _loadSchema(name),
    };
  });

  test('source schema executes positive and adversarial fixtures', () {
    final schema = schemas['source']!;
    final valid = <String, Object?>{
      'schema_version': 1,
      'id': 'alfredo',
      'name': 'Alfredo',
      'kind': 'local',
      'path': '.',
      'read_only': true,
      'packages_path': 'packages',
      'profiles_path': 'profiles',
    };

    expect(schema.validate(valid).isValid, isTrue);
    expect(schema.validate({...valid, 'path': '../escape'}).isValid, isFalse);
    expect(
      schema.validate({...valid, 'profiles_path': '/profiles'}).isValid,
      isFalse,
    );
    expect(schema.validate({...valid, 'unknown': true}).isValid, isFalse);
    expect(schema.validate({...valid, 'kind': 'git'}).isValid, isFalse);
    expect(schema.validate({...valid, 'kind': 'archive'}).isValid, isFalse);
  });

  test('package schema executes positive and adversarial fixtures', () {
    final schema = schemas['package']!;
    final valid = <String, Object?>{
      'schema_version': 1,
      'id': 'android-core',
      'name': 'Android Core',
      'version': '1.2.3',
      'description': 'Android foundation.',
      'targets': ['codex'],
      'contents': <String, Object?>{
        'skills': <String>[],
        'rules': <String>[],
      },
      'dependencies': <Object?>[],
      'conflicts': <String>[],
    };

    expect(schema.validate(valid).isValid, isTrue);
    expect(
      schema.validate({...valid, 'id': ' android-core '}).isValid,
      isFalse,
    );
    expect(
      schema.validate({...valid, 'version': ' 1.2.3 '}).isValid,
      isFalse,
    );
    expect(
      schema.validate({
        ...valid,
        'contents': {
          'skills': ['../escape'],
        },
      }).isValid,
      isFalse,
    );
    expect(
      schema.validate({
        ...valid,
        'targets': ['codex', 'codex'],
      }).isValid,
      isFalse,
    );
    expect(schema.validate({...valid, 'dependencies': null}).isValid, isFalse);
    expect(schema.validate({...valid, 'conflicts': null}).isValid, isFalse);
    expect(schema.validate({...valid, 'unknown': true}).isValid, isFalse);
  });

  test('profile schema executes positive and adversarial fixtures', () {
    final schema = schemas['profile']!;
    final valid = <String, Object?>{
      'schema_version': 1,
      'id': 'work',
      'name': 'Work',
      'scope': 'user',
      'targets': ['codex'],
      'sources': ['alfredo'],
      'packages': [
        {'id': 'android-core', 'version': '1.2.3', 'source': 'alfredo'},
      ],
    };

    expect(schema.validate(valid).isValid, isTrue);
    expect(schema.validate({...valid, 'scope': 'global'}).isValid, isFalse);
    expect(
      schema.validate({
        ...valid,
        'targets': ['codex', 'codex'],
      }).isValid,
      isFalse,
    );
    expect(schema.validate({...valid, 'unknown': true}).isValid, isFalse);
  });

  test('lockfile and installed-state schemas reject unsafe persisted data', () {
    final lockfile = schemas['lockfile']!;
    final state = schemas['installed-state']!;
    const digest =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final validLock = <String, Object?>{
      'version': 1,
      'target': 'codex',
      'packages': [
        {
          'id': 'android-core',
          'version': '1.0.0',
          'source': 'local',
          'digest': digest,
        },
      ],
    };
    final validState = <String, Object?>{
      'version': 1,
      'target': 'codex',
      'files': [
        {
          'path': 'skills/android/SKILL.md',
          'digest': digest,
          'package_id': 'android-core',
        },
      ],
    };

    expect(lockfile.validate(validLock).isValid, isTrue);
    expect(lockfile.validate({...validLock, 'unknown': true}).isValid, isFalse);
    expect(state.validate(validState).isValid, isTrue);
    expect(
      state.validate({
        ...validState,
        'files': [
          {
            'path': '../outside',
            'digest': digest,
            'package_id': 'android-core',
          },
        ],
      }).isValid,
      isFalse,
    );
  });
}

Future<JsonSchema> _loadSchema(String name) async {
  final file = File(
    p.join(Directory.current.parent.path, 'schemas', '$name.schema.json'),
  );
  final document = jsonDecode(await file.readAsString()) as Map;
  expect(document[r'$schema'], 'https://json-schema.org/draft/2020-12/schema');
  return JsonSchema.create(
    document,
    schemaVersion: SchemaVersion.draft2020_12,
  );
}
