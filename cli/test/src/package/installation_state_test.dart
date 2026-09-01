import 'dart:io';

import 'package:alfredo_cli/src/package/installation_state.dart';
import 'package:alfredo_cli/src/package/package_models.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-state-');
  });

  tearDown(() async => temporary.delete(recursive: true));

  test('persists deterministic installed state and lockfiles', () async {
    final stateStore = InstalledStateStore(
      File('${temporary.path}/state.json'),
    );
    await stateStore.write(
      const InstalledState(
        target: 'codex',
        files: [
          ManagedFile(
            path: 'skills/a/SKILL.md',
            digest: _digest,
            packageId: 'a',
            mode: ManagedFileMode.seed,
          ),
        ],
      ),
    );
    final state = await stateStore.read('codex');
    expect(state.files.single.packageId, 'a');
    expect(state.files.single.mode, ManagedFileMode.seed);

    final locks = PackageLockfileStore(File('${temporary.path}/lock.json'));
    await locks.write(
      const PackageLockfile(
        target: 'codex',
        packages: [
          LockedPackage(
            id: 'a',
            version: '1.0.0',
            source: 'local',
            digest: _digest,
          ),
        ],
      ),
    );
    expect((await locks.read()).packages.single.digest, _digest);
  });
}

const _digest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
