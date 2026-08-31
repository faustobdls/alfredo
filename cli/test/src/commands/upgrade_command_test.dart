import 'package:alfredo_cli/src/command_runner.dart';
import 'package:alfredo_cli/src/upgrade/release_client.dart';
import 'package:alfredo_cli/src/upgrade/self_updater.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockLogger extends Mock implements Logger {}

class _MockSelfUpdater extends Mock implements SelfUpdater {}

void main() {
  late Logger logger;
  late SelfUpdater updater;

  setUp(() {
    logger = _MockLogger();
    updater = _MockSelfUpdater();
  });

  AlfredoCliCommandRunner runner() =>
      AlfredoCliCommandRunner(logger: logger, selfUpdater: updater);

  void stub(UpgradeOutcome outcome) {
    when(
      () => updater.run(
        checkOnly: any(named: 'checkOnly'),
        force: any(named: 'force'),
      ),
    ).thenAnswer((_) async => outcome);
  }

  test('reports success after applying an upgrade', () async {
    stub(
      const UpgradeOutcome(
        previousVersion: '0.0.1',
        latestVersion: '0.2.0',
        updateAvailable: true,
        applied: true,
        executablePath: '/tmp/alfredo',
      ),
    );

    final code = await runner().run(['upgrade']);

    expect(code, ExitCode.success.code);
    verify(
      () => logger.success(any(that: contains('Upgraded Alfredo 0.0.1'))),
    ).called(1);
  });

  test('--check announces an available release without applying it', () async {
    stub(
      const UpgradeOutcome(
        previousVersion: '0.0.1',
        latestVersion: '0.2.0',
        updateAvailable: true,
        applied: false,
      ),
    );

    final code = await runner().run(['upgrade', '--check']);

    expect(code, ExitCode.success.code);
    verify(
      () =>
          logger.info(any(that: contains('Update available: 0.0.1 -> 0.2.0'))),
    ).called(1);
  });

  test('reports an up-to-date CLI', () async {
    stub(
      const UpgradeOutcome(
        previousVersion: '0.2.0',
        latestVersion: '0.2.0',
        updateAvailable: false,
        applied: false,
      ),
    );

    final code = await runner().run(['upgrade']);

    expect(code, ExitCode.success.code);
    verify(
      () => logger.info(any(that: contains('already up to date'))),
    ).called(1);
  });

  test('maps an UpgradeException to an unavailable exit code', () async {
    when(
      () => updater.run(
        checkOnly: any(named: 'checkOnly'),
        force: any(named: 'force'),
      ),
    ).thenThrow(const UpgradeException('network down'));

    final code = await runner().run(['upgrade']);

    expect(code, ExitCode.unavailable.code);
    verify(() => logger.err('network down')).called(1);
  });
}
