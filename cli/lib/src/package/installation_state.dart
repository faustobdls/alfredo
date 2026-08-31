import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/package/package_models.dart';

/// Reads and atomically writes package installation ownership state.
class InstalledStateStore {
  /// Creates a state store backed by [file].
  const InstalledStateStore(this.file);

  /// Persisted JSON ownership state.
  final File file;

  /// Reads current state, returning an empty state for a new installation.
  Future<InstalledState> read(String target) async {
    if (!file.existsSync()) {
      return InstalledState(target: target, files: const []);
    }
    try {
      final document = jsonDecode(await file.readAsString());
      if (document is! Map<String, dynamic> ||
          document['version'] != InstalledState.schemaVersion ||
          document['target'] != target ||
          document['files'] is! List) {
        throw const PackageException('Unsupported installed state format.');
      }
      final files = <ManagedFile>[];
      final paths = <String>{};
      for (final rawFile in document['files'] as List) {
        if (rawFile is! Map<String, dynamic>) {
          throw const PackageException('Invalid installed state entry.');
        }
        final path = rawFile['path'];
        final digest = rawFile['digest'];
        final packageId = rawFile['package_id'];
        if (path is! String ||
            digest is! String ||
            packageId is! String ||
            !_isSafeRelativePath(path) ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
            !paths.add(path)) {
          throw const PackageException('Invalid installed state entry.');
        }
        files.add(
          ManagedFile(path: path, digest: digest, packageId: packageId),
        );
      }
      files.sort((left, right) => left.path.compareTo(right.path));
      return InstalledState(target: target, files: List.unmodifiable(files));
    } on FormatException catch (error) {
      throw PackageException('Cannot read installed state: ${error.message}');
    }
  }

  /// Atomically persists [state].
  Future<void> write(InstalledState state) async {
    final temporary = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final files = [...state.files]
      ..sort((left, right) => left.path.compareTo(right.path));
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(
          InstalledState(target: state.target, files: files).toJson(),
        )}\n',
        flush: true,
      );
      await temporary.rename(file.path);
    } on FileSystemException catch (error) {
      throw PackageException('Cannot update installed state: ${error.message}');
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
  }

  static bool _isSafeRelativePath(String value) {
    return value.isNotEmpty &&
        !value.startsWith('/') &&
        !value.contains(r'\') &&
        !value.split('/').contains('..');
  }
}

/// Reads and atomically writes deterministic package lockfiles.
class PackageLockfileStore {
  /// Creates a lockfile store backed by [file].
  const PackageLockfileStore(this.file);

  /// Persisted JSON lockfile.
  final File file;

  /// Reads a lockfile from disk.
  Future<PackageLockfile> read() async {
    try {
      final document = jsonDecode(await file.readAsString());
      if (document is! Map<String, dynamic> ||
          document['version'] != PackageLockfile.schemaVersion ||
          document['target'] is! String ||
          document['packages'] is! List) {
        throw const PackageException('Unsupported package lockfile format.');
      }
      final packages = <LockedPackage>[];
      final identities = <String>{};
      for (final item in document['packages'] as List) {
        if (item is! Map<String, dynamic>) {
          throw const PackageException('Invalid package lockfile entry.');
        }
        final id = item['id'];
        final version = item['version'];
        final source = item['source'];
        final digest = item['digest'];
        if (id is! String ||
            version is! String ||
            source is! String ||
            digest is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
            !identities.add('$id@$version@$source')) {
          throw const PackageException('Invalid package lockfile entry.');
        }
        packages.add(
          LockedPackage(
            id: id,
            version: version,
            source: source,
            digest: digest,
          ),
        );
      }
      packages.sort((left, right) => left.id.compareTo(right.id));
      return PackageLockfile(
        target: document['target']! as String,
        packages: List.unmodifiable(packages),
      );
    } on FileSystemException catch (error) {
      throw PackageException('Cannot read package lockfile: ${error.message}');
    } on FormatException catch (error) {
      throw PackageException('Cannot read package lockfile: ${error.message}');
    }
  }

  /// Atomically persists [lockfile].
  Future<void> write(PackageLockfile lockfile) async {
    final temporary = File(
      '${file.path}.$pid.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(lockfile.toJson())}\n',
        flush: true,
      );
      await temporary.rename(file.path);
    } on FileSystemException catch (error) {
      throw PackageException(
        'Cannot update package lockfile: ${error.message}',
      );
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
  }
}
