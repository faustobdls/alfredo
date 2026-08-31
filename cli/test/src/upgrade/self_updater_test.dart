import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:alfredo_cli/src/upgrade/release_client.dart';
import 'package:alfredo_cli/src/upgrade/self_updater.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _FakeReleaseClient implements ReleaseClient {
  _FakeReleaseClient({required this.version, required this.assets});

  final String version;
  final Map<String, Uint8List> assets;
  int downloads = 0;

  @override
  Future<String> latestVersion() async => version;

  @override
  Uri assetBaseUrl() => Uri.parse('https://example.test/dl/');

  @override
  Future<Uint8List> download(Uri url) async {
    downloads++;
    final bytes = assets[url.pathSegments.last];
    if (bytes == null) {
      throw UpgradeException('missing asset ${url.pathSegments.last}');
    }
    return bytes;
  }
}

Uint8List _zip(String content) {
  final archive = Archive()..add(ArchiveFile.string('alfredo', content));
  return ZipEncoder().encodeBytes(archive);
}

String _sums(String asset, List<int> bytes) =>
    '${sha256.convert(bytes)}  $asset\n';

void main() {
  const asset = 'alfredo-linux-x64.tar.gz';
  late Directory temporary;
  late File executable;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('alfredo-self-updater-');
    executable = File(p.join(temporary.path, 'bin', 'alfredo'));
    await executable.parent.create(recursive: true);
    await executable.writeAsString('OLD');
  });

  tearDown(() async => temporary.delete(recursive: true));

  SelfUpdater updater(_FakeReleaseClient client, {String current = '0.0.1'}) =>
      SelfUpdater(
        client: client,
        currentVersion: current,
        resolveExecutable: () => executable.path,
        abi: Abi.linuxX64,
        isWindows: false,
      );

  test('downloads, verifies, and swaps the executable when newer', () async {
    final archive = _zip('NEW');
    final client = _FakeReleaseClient(
      version: '1.2.0',
      assets: {
        asset: archive,
        'SHA256SUMS': Uint8List.fromList(_sums(asset, archive).codeUnits),
      },
    );

    final outcome = await updater(client).run();

    expect(outcome.applied, isTrue);
    expect(outcome.previousVersion, '0.0.1');
    expect(outcome.latestVersion, '1.2.0');
    expect(await executable.readAsString(), 'NEW');
    expect(
      Directory(
        executable.parent.path,
      ).listSync().map((e) => p.basename(e.path)),
      ['alfredo'],
    );
  });

  test('does nothing when already current and not forced', () async {
    final client = _FakeReleaseClient(version: '0.0.1', assets: const {});

    final outcome = await updater(client).run();

    expect(outcome.applied, isFalse);
    expect(outcome.updateAvailable, isFalse);
    expect(client.downloads, 0);
    expect(await executable.readAsString(), 'OLD');
  });

  test('check only reports availability without downloading', () async {
    final client = _FakeReleaseClient(version: '9.9.9', assets: const {});

    final outcome = await updater(client).run(checkOnly: true);

    expect(outcome.applied, isFalse);
    expect(outcome.updateAvailable, isTrue);
    expect(client.downloads, 0);
    expect(await executable.readAsString(), 'OLD');
  });

  test('reinstalls the current version when forced', () async {
    final archive = _zip('FORCED');
    final client = _FakeReleaseClient(
      version: '0.0.1',
      assets: {
        asset: archive,
        'SHA256SUMS': Uint8List.fromList(_sums(asset, archive).codeUnits),
      },
    );

    final outcome = await updater(client).run(force: true);

    expect(outcome.applied, isTrue);
    expect(await executable.readAsString(), 'FORCED');
  });

  test(
    'rejects a checksum mismatch and leaves the executable intact',
    () async {
      final archive = _zip('TAMPERED');
      final client = _FakeReleaseClient(
        version: '1.0.0',
        assets: {
          asset: archive,
          'SHA256SUMS': Uint8List.fromList(
            _sums(asset, _zip('DIFFERENT')).codeUnits,
          ),
        },
      );

      await expectLater(
        updater(client).run(),
        throwsA(isA<UpgradeException>()),
      );
      expect(await executable.readAsString(), 'OLD');
    },
  );

  test('fails when no release asset exists for the platform', () {
    final client = _FakeReleaseClient(version: '1.0.0', assets: const {});
    final self = SelfUpdater(
      client: client,
      currentVersion: '0.0.0',
      resolveExecutable: () => executable.path,
      abi: Abi.androidArm,
      isWindows: false,
    );

    expect(self.run, throwsA(isA<UpgradeException>()));
  });
}
