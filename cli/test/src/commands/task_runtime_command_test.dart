import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/command_runner.dart';
import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:alfredo_cli/src/task_runtime/task_runtime.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

void main() {
  late Directory temporary;
  late Logger logger;
  late AlfredoCliCommandRunner runner;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'alfredo-runtime-command-',
    );
    logger = _MockLogger();
    runner = AlfredoCliCommandRunner(
      logger: logger,
      taskRuntime: TaskRuntimeStore(projectRoot: temporary),
      memoryRoots: MemoryRoots(
        userDirectory: Directory(p.join(temporary.path, 'user-memory')),
        projectDirectory: Directory(
          p.join(temporary.path, '.alfredo', 'memory'),
        ),
      ),
    );
  });

  tearDown(() async => temporary.delete(recursive: true));

  test('runs an end-to-end durable task workflow', () async {
    expect(
      await runner.run([
        'task',
        'create',
        '--title',
        'Implement reconnect support',
        '--acceptance',
        'resume packet explains next action',
        '--file',
        'lib/reconnect.dart',
      ]),
      ExitCode.success.code,
    );
    final taskId = captureSuccess(logger, 'Created ');

    expect(await runner.run(['task', 'list']), ExitCode.success.code);
    expect(await runner.run(['task', 'ready']), ExitCode.success.code);

    expect(
      await runner.run([
        'session',
        'start',
        '--adapter',
        'claude',
        '--json',
      ]),
      ExitCode.success.code,
    );
    final session =
        jsonDecode(
              captureInfo(logger, '{'),
            )
            as Map<String, dynamic>;
    final sessionId = session['id']! as String;

    expect(
      await runner.run([
        'task',
        'claim',
        taskId,
        '--adapter',
        'claude',
        '--session',
        sessionId,
      ]),
      ExitCode.success.code,
    );
    expect(await runner.run(['task', 'start', taskId]), ExitCode.success.code);
    expect(
      await runner.run([
        'task',
        'checkpoint',
        taskId,
        '--completed',
        'protocol',
        '--current',
        'client reconnect',
        '--remaining',
        'tests',
        '--file',
        'lib/reconnect.dart',
        '--validation',
        'unit_tests=pending',
        '--next-action',
        'write tests',
      ]),
      ExitCode.success.code,
    );
    expect(
      await runner.run([
        'session',
        'close',
        sessionId,
        '--reason',
        'context-limit',
        '--capture-memory',
      ]),
      ExitCode.success.code,
    );
    expect(await runner.run(['task', 'resume', taskId]), ExitCode.success.code);
    expect(
      await runner.run([
        'session',
        'start',
        '--adapter',
        'codex',
        '--json',
      ]),
      ExitCode.success.code,
    );
    final codexSession =
        jsonDecode(
              captureInfo(logger, '{'),
            )
            as Map<String, dynamic>;
    final codexSessionId = codexSession['id']! as String;
    expect(
      await runner.run([
        'task',
        'claim',
        taskId,
        '--adapter',
        'codex',
        '--session',
        codexSessionId,
      ]),
      ExitCode.success.code,
    );
    expect(await runner.run(['task', 'start', taskId]), ExitCode.success.code);
    expect(await runner.run(['task', 'verify', taskId]), ExitCode.success.code);
    expect(await runner.run(['task', 'done', taskId]), ExitCode.success.code);

    expect(
      File(
        p.join(temporary.path, '.alfredo', 'tasks', '$taskId.json'),
      ).existsSync(),
      isTrue,
    );
    expect(
      Directory(
        p.join(temporary.path, '.alfredo', 'memory', 'journal'),
      ).existsSync(),
      isTrue,
    );
    verify(
      () => logger.info(any(that: contains('Next action: write tests'))),
    ).called(1);
  });

  test('session close captures memory when configured', () async {
    final projectMemory = MemoryStore(
      directory: Directory(p.join(temporary.path, '.alfredo', 'memory')),
    );
    await projectMemory.ensureSkeleton();
    await projectMemory.writeConfig(
      const MemoryConfig(
        embeddings: EmbeddingsConfig(),
        capture: CaptureConfig(sessionEndHook: true),
        defaultScope: MemoryScope.user,
      ),
    );

    expect(
      await runner.run([
        'session',
        'start',
        '--adapter',
        'codex',
        '--json',
      ]),
      ExitCode.success.code,
    );
    final session =
        jsonDecode(
              captureInfo(logger, '{'),
            )
            as Map<String, dynamic>;

    expect(
      await runner.run([
        'session',
        'close',
        session['id']! as String,
        '--reason',
        'manual',
      ]),
      ExitCode.success.code,
    );

    final journals = Directory(
      p.join(temporary.path, '.alfredo', 'memory', 'journal'),
    ).listSync(recursive: true).whereType<File>().toList();
    expect(journals, isNotEmpty);
    expect(journals.single.readAsStringSync(), contains('session '));
  });
}

String captureSuccess(Logger logger, String prefix) {
  final captured =
      verify(
            () => logger.success(captureAny(that: startsWith(prefix))),
          ).captured.last!
          as String;
  return captured.split(':').first.substring(prefix.length);
}

String captureInfo(Logger logger, String prefix) {
  return verify(
        () => logger.info(captureAny(that: startsWith(prefix))),
      ).captured.last!
      as String;
}
