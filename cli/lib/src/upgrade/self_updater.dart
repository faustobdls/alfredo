import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:alfredo_cli/src/upgrade/release_client.dart';
import 'package:alfredo_cli/src/version.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Outcome of an [SelfUpdater.run] invocation.
class UpgradeOutcome {
  /// Creates an upgrade outcome.
  const UpgradeOutcome({
    required this.previousVersion,
    required this.latestVersion,
    required this.updateAvailable,
    required this.applied,
    this.executablePath,
    this.note,
  });

  /// Version the CLI reported before the operation.
  final String previousVersion;

  /// Latest version published upstream.
  final String latestVersion;

  /// Whether [latestVersion] is newer than [previousVersion].
  final bool updateAvailable;

  /// Whether a new binary was written to disk.
  final bool applied;

  /// Absolute path of the replaced executable, when [applied] is true.
  final String? executablePath;

  /// Optional advisory shown to the user (for example a leftover old binary).
  final String? note;
}

/// Downloads, verifies, and swaps the running Alfredo executable.
class SelfUpdater {
  /// Creates a self updater.
  SelfUpdater({
    required this.client,
    this.currentVersion = packageVersion,
    String Function()? resolveExecutable,
    Abi? abi,
    bool? isWindows,
  }) : resolveExecutable =
           resolveExecutable ?? (() => Platform.resolvedExecutable),
       abi = abi ?? Abi.current(),
       isWindows = isWindows ?? Platform.isWindows;

  /// Release metadata and asset provider.
  final ReleaseClient client;

  /// Version the running CLI identifies as.
  final String currentVersion;

  /// Resolves the absolute path of the executable to replace.
  final String Function() resolveExecutable;

  /// Application binary interface used to pick the release asset.
  final Abi abi;

  /// Whether the host requires the Windows binary-swap strategy.
  final bool isWindows;

  static const _assetNames = <Abi, String>{
    Abi.linuxX64: 'alfredo-linux-x64.tar.gz',
    Abi.linuxArm64: 'alfredo-linux-arm64.tar.gz',
    Abi.macosX64: 'alfredo-macos-x64.tar.gz',
    Abi.macosArm64: 'alfredo-macos-arm64.tar.gz',
    Abi.windowsX64: 'alfredo-windows-x64.zip',
  };

  /// Name of the release asset for the current platform.
  String assetName() {
    final name = _assetNames[abi];
    if (name == null) {
      throw UpgradeException(
        'No Alfredo release is published for this platform ($abi).',
      );
    }
    return name;
  }

  /// Resolves the latest version and, unless [checkOnly], applies the upgrade.
  Future<UpgradeOutcome> run({
    bool checkOnly = false,
    bool force = false,
  }) async {
    final latest = await client.latestVersion();
    final available = _isNewer(latest, currentVersion);
    if (checkOnly || (!available && !force)) {
      return UpgradeOutcome(
        previousVersion: currentVersion,
        latestVersion: latest,
        updateAvailable: available,
        applied: false,
      );
    }

    final asset = assetName();
    final base = client.assetBaseUrl();
    final archiveBytes = await client.download(base.resolve(asset));
    final sumsBytes = await client.download(base.resolve('SHA256SUMS'));
    _verifyChecksum(asset, archiveBytes, sumsBytes);

    final binary = _extractExecutable(archiveBytes);
    final note = await _swap(binary);

    return UpgradeOutcome(
      previousVersion: currentVersion,
      latestVersion: latest,
      updateAvailable: available,
      applied: true,
      executablePath: resolveExecutable(),
      note: note,
    );
  }

  void _verifyChecksum(String asset, List<int> bytes, List<int> sumsBytes) {
    final actual = sha256.convert(bytes).toString();
    final expected = _checksumFor(asset, String.fromCharCodes(sumsBytes));
    if (expected == null) {
      throw UpgradeException('No checksum published for $asset.');
    }
    if (expected != actual) {
      throw UpgradeException(
        'Checksum verification failed for $asset.',
      );
    }
  }

  static String? _checksumFor(String asset, String sums) {
    for (final line in const LineSplitter().convert(sums)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length == 2 && (parts[1] == asset || parts[1] == '*$asset')) {
        return parts[0].toLowerCase();
      }
    }
    return null;
  }

  List<int> _extractExecutable(List<int> archiveBytes) {
    final exeName = isWindows ? 'alfredo.exe' : 'alfredo';
    Archive archive;
    try {
      if (_isZip(archiveBytes)) {
        archive = ZipDecoder().decodeBytes(archiveBytes, verify: true);
      } else if (_isGzip(archiveBytes)) {
        archive = TarDecoder().decodeBytes(
          const GZipDecoder().decodeBytes(archiveBytes),
        );
      } else {
        archive = TarDecoder().decodeBytes(archiveBytes);
      }
    } on Object catch (error) {
      throw UpgradeException('Cannot decode release archive: $error');
    }
    for (final entry in archive) {
      if (entry.isDirectory) continue;
      if (entry.name == exeName || p.posix.basename(entry.name) == exeName) {
        return entry.content as List<int>;
      }
    }
    throw UpgradeException('Release archive did not contain $exeName.');
  }

  Future<String?> _swap(List<int> binary) async {
    final executable = resolveExecutable();
    final directory = p.dirname(executable);
    final name = p.basename(executable);
    final nonce =
        '$pid-${DateTime.now().microsecondsSinceEpoch}-'
        '${Random.secure().nextInt(1 << 32)}';
    final staged = File(p.join(directory, '.$name.new-$nonce'));
    try {
      await staged.writeAsBytes(binary, flush: true);
      if (!isWindows) {
        final result = await Process.run('chmod', ['755', staged.path]);
        if (result.exitCode != 0) {
          throw UpgradeException(
            'Cannot mark the new binary executable: '
            '${(result.stderr as String).trim()}',
          );
        }
        await staged.rename(executable);
        return null;
      }
      final backup = File('$executable.old-$nonce');
      await File(executable).rename(backup.path);
      try {
        await staged.rename(executable);
      } on FileSystemException {
        await backup.rename(executable);
        rethrow;
      }
      try {
        await backup.delete();
        return null;
      } on FileSystemException {
        return 'Previous binary kept at ${backup.path}; '
            'delete it after restarting your shell.';
      }
    } on FileSystemException catch (error) {
      throw UpgradeException('Cannot replace the executable: ${error.message}');
    } finally {
      if (staged.existsSync()) {
        try {
          await staged.delete();
        } on FileSystemException {
          // Best effort cleanup of the staging file.
        }
      }
    }
  }

  static bool _isNewer(String candidate, String current) {
    final left = _parseVersion(candidate);
    final right = _parseVersion(current);
    if (left == null || right == null) {
      return candidate != current;
    }
    for (var index = 0; index < 3; index++) {
      if (left[index] != right[index]) return left[index] > right[index];
    }
    return false;
  }

  static List<int>? _parseVersion(String value) {
    final core = value.split('-').first.split('+').first.split('.');
    if (core.length != 3) return null;
    final parsed = <int>[];
    for (final part in core) {
      final number = int.tryParse(part);
      if (number == null || number < 0) return null;
      parsed.add(number);
    }
    return parsed;
  }

  static bool _isZip(List<int> bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0x50 &&
      bytes[1] == 0x4b &&
      bytes[2] >= 0x03 &&
      bytes[2] <= 0x07;

  static bool _isGzip(List<int> bytes) =>
      bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b;
}
