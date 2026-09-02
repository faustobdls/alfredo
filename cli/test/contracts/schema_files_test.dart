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
        'memory-config',
        'task',
        'task-event',
        'session',
        'run',
        'context',
        'template',
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
      'contents': <String, Object?>{'skills': <String>[], 'rules': <String>[]},
      'dependencies': <Object?>[],
      'conflicts': <String>[],
    };

    expect(schema.validate(valid).isValid, isTrue);
    expect(
      schema.validate({
        ...valid,
        'contents': {
          'agents': ['agents'],
        },
      }).isValid,
      isTrue,
    );
    expect(
      schema.validate({
        ...valid,
        'contents': {
          'personas': ['personas/user.md'],
        },
      }).isValid,
      isTrue,
    );
    expect(
      schema.validate({
        ...valid,
        'contents': {
          'templates': ['templates/bank-email'],
        },
      }).isValid,
      isTrue,
    );
    expect(
      schema.validate({
        ...valid,
        'contents': {
          'agents': ['../escape'],
        },
      }).isValid,
      isFalse,
    );
    expect(
      schema.validate({
        ...valid,
        'contents': {
          'unknown-kind': ['x'],
        },
      }).isValid,
      isFalse,
    );
    expect(
      schema.validate({...valid, 'id': ' android-core '}).isValid,
      isFalse,
    );
    expect(schema.validate({...valid, 'version': ' 1.2.3 '}).isValid, isFalse);
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
          'mode': 'seed',
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

  test('memory-config schema executes positive and adversarial fixtures', () {
    final schema = schemas['memory-config']!;
    final valid = <String, Object?>{
      'version': 1,
      'embeddings': <String, Object?>{
        'enabled': true,
        'provider': 'ollama',
        'baseUrl': 'http://127.0.0.1:11434',
        'model': 'nomic-embed-text',
        'dimensions': 768,
      },
      'capture': <String, Object?>{
        'sessionEndHook': true,
        'gitDiffStat': true,
        'targets': ['claude-code'],
      },
      'defaultScope': 'user',
    };

    expect(schema.validate(valid).isValid, isTrue);
    expect(
      schema.validate({
        'version': 1,
        'embeddings': {'enabled': false},
        'capture': {'sessionEndHook': false},
        'defaultScope': 'project',
      }).isValid,
      isTrue,
    );
    expect(schema.validate({...valid, 'version': 2}).isValid, isFalse);
    expect(
      schema.validate({...valid, 'defaultScope': 'global'}).isValid,
      isFalse,
    );
    expect(
      schema.validate({
        ...valid,
        'embeddings': {'enabled': true, 'provider': 'openai'},
      }).isValid,
      isFalse,
    );
    expect(
      schema.validate({
        ...valid,
        'embeddings': {'enabled': true, 'baseUrl': 'ftp://example.com'},
      }).isValid,
      isFalse,
    );
    expect(
      schema.validate({
        ...valid,
        'embeddings': {'enabled': true, 'dimensions': 0},
      }).isValid,
      isFalse,
    );
    expect(
      schema.validate({
        ...valid,
        'capture': {
          'sessionEndHook': true,
          'targets': ['codex', 'codex'],
        },
      }).isValid,
      isFalse,
    );
    expect(
      schema.validate({
        ...valid,
        'capture': {
          'sessionEndHook': true,
          'targets': ['emacs'],
        },
      }).isValid,
      isFalse,
    );
    expect(schema.validate({...valid, 'unknown': true}).isValid, isFalse);
    expect(
      schema.validate({...valid, 'capture': <String, Object?>{}}).isValid,
      isFalse,
    );
  });

  test('task runtime schemas validate durable runtime documents', () {
    final task = schemas['task']!;
    final event = schemas['task-event']!;
    final session = schemas['session']!;
    final run = schemas['run']!;
    final context = schemas['context']!;
    const taskId = 'ALF-01K3Z7H8J9ABCDEFGHJK';
    const sessionId = 'SES-01K3Z7H8J9ABCDEFGHJK';
    const runId = 'RUN-01K3Z7H8J9ABCDEFGHJK';
    const now = '2026-08-31T12:00:00.000Z';
    final validTask = <String, Object?>{
      'schema': 'alfredo.task/v1',
      'id': taskId,
      'title': 'Implement reconnect support',
      'status': 'BACKLOG',
      'priority': 'normal',
      'run': runId,
      'created_at': now,
      'updated_at': now,
      'owner': null,
      'previous_owner': null,
      'dependencies': <String>[],
      'acceptance': ['resume works'],
      'context': {
        'topics': ['multiplayer'],
        'files': ['lib/reconnect.dart'],
      },
      'checkpoint': {
        'completed': <String>[],
        'current': null,
        'remaining': <String>[],
        'changed_files': <String>[],
        'validations': <String, Object?>{},
        'next_action': null,
      },
      'blocker': null,
    };
    final validSession = <String, Object?>{
      'schema': 'alfredo.session/v1',
      'id': sessionId,
      'adapter': 'claude',
      'agent': 'executor',
      'started_at': now,
      'updated_at': now,
      'status': 'ACTIVE',
      'ended_at': null,
      'close_reason': null,
      'tasks_claimed': [taskId],
      'tasks_worked': <String>[],
      'last_checkpoint': null,
    };
    final validEvent = <String, Object?>{
      'schema': 'alfredo.task-event/v1',
      'id': 'EVT-01K3Z7H8J9ABCDEFGHJK',
      'task': taskId,
      'type': 'checkpointed',
      'created_at': now,
      'data': {'next_action': 'resume implementation'},
    };
    final validRun = <String, Object?>{
      'schema': 'alfredo.run/v1',
      'id': runId,
      'title': 'Implement multiplayer MVP',
      'summary': null,
      'created_at': now,
      'updated_at': now,
      'tasks': [taskId],
    };
    final validContext = <String, Object?>{
      'schema': 'alfredo.context/v1',
      'task': taskId,
      'budget': {
        'target_tokens': 6000,
        'hard_limit_tokens': 12000,
        'estimated_tokens': 42,
        'estimator': 'ceil(chars / 4)',
      },
      'sources': {
        'rules': <String>[],
        'skills': <String>[],
        'personas': ['.alfredo/personas/user.md'],
        'templates': <String>[],
        'memory': <String>[],
        'files': ['lib/reconnect.dart'],
        'decisions': <String>[],
      },
      'missing': <String>[],
    };

    expect(task.validate(validTask).isValid, isTrue);
    expect(event.validate(validEvent).isValid, isTrue);
    expect(session.validate(validSession).isValid, isTrue);
    expect(run.validate(validRun).isValid, isTrue);
    expect(context.validate(validContext).isValid, isTrue);
    expect(task.validate({...validTask, 'status': 'READY'}).isValid, isFalse);
    expect(
      event.validate({...validEvent, 'type': 'Checkpointed'}).isValid,
      isFalse,
    );
    expect(
      task.validate({
        ...validTask,
        'context': {
          'topics': ['multiplayer'],
          'files': ['../escape'],
        },
      }).isValid,
      isFalse,
    );
    expect(
      session.validate({...validSession, 'close_reason': 'quota'}).isValid,
      isFalse,
    );
    expect(
      context.validate({...validContext, 'unknown': true}).isValid,
      isFalse,
    );
    expect(
      context.validate({
        ...validContext,
        'sources': {
          'rules': <String>[],
          'skills': <String>[],
          'personas': <String>[],
          'memory': <String>[],
          'files': <String>[],
          'decisions': <String>[],
        },
      }).isValid,
      isFalse,
      reason: 'sources.templates is required',
    );
    expect(
      task.validate({
        ...validTask,
        'context': {
          'topics': <String>[],
          'files': <String>[],
          'template': 'bank-email',
        },
      }).isValid,
      isTrue,
    );
  });

  test('template schema executes positive and adversarial fixtures', () {
    final schema = schemas['template']!;
    final valid = <String, Object?>{
      'schema_version': 1,
      'name': 'bank-email',
      'kind': 'email',
      'description': 'Use for client email in the bank voice. Not for Slack.',
      'voice': {
        'temperature': 'formal',
        'person': 'first-person-plural',
        'greeting': 'Prezado(a),',
        'signoff': 'Atenciosamente,',
      },
      'structure': [
        'opening',
        {'body': 'one idea per paragraph'},
      ],
      'length': {'max_words': 220},
      'format': {'target': 'markdown', 'theme': 'references/bank-theme.md'},
      'constraints': {
        'always': ['cite the account manager'],
        'never': ['emojis'],
      },
      'examples': ['references/example-onboarding.md'],
    };

    expect(schema.validate(valid).isValid, isTrue);
    expect(
      schema.validate({
        'schema_version': 1,
        'name': 'bank-email',
        'kind': 'email',
        'description': 'Minimal template.',
      }).isValid,
      isTrue,
    );
    expect(
      schema.validate({...valid, 'kind': 'Email Blast'}).isValid,
      isFalse,
    );
    expect(schema.validate({...valid, 'schema_version': 2}).isValid, isFalse);
    expect(
      schema.validate({
        ...valid,
        'format': {'target': 'powerpoint'},
      }).isValid,
      isTrue,
    );
    expect(
      schema.validate({
        ...valid,
        'format': {'target': 'Power Point'},
      }).isValid,
      isFalse,
    );
    expect(
      schema.validate({
        ...valid,
        'format': {'theme': '../secrets.md'},
      }).isValid,
      isFalse,
    );
    expect(
      schema.validate({
        ...valid,
        'voice': {'temperature': 'chilly'},
      }).isValid,
      isFalse,
    );
    expect(schema.validate({...valid, 'unknown': true}).isValid, isFalse);
    expect(
      schema.validate({
        'schema_version': 1,
        'name': 'bank-email',
        'kind': 'email',
      }).isValid,
      isFalse,
      reason: 'description is required',
    );
  });
}

Future<JsonSchema> _loadSchema(String name) async {
  final file = File(
    p.join(Directory.current.parent.path, 'schemas', '$name.schema.json'),
  );
  final document = jsonDecode(await file.readAsString()) as Map;
  expect(document[r'$schema'], 'https://json-schema.org/draft/2020-12/schema');
  return JsonSchema.create(document, schemaVersion: SchemaVersion.draft2020_12);
}
