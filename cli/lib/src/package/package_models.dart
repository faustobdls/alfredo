import 'dart:io';

/// A package-level error that can be displayed directly by a CLI adapter.
class PackageException implements Exception {
  /// Creates an actionable package operation error.
  const PackageException(this.message);

  /// User-facing failure description.
  final String message;

  @override
  String toString() => message;
}

/// A declared dependency with an exact semantic version.
class PackageDependency {
  /// Creates a package dependency.
  const PackageDependency({required this.id, required this.version});

  /// Stable dependency package identifier.
  final String id;

  /// Required semantic version.
  final String version;
}

/// A parsed, validated package manifest.
class PackageManifest {
  /// Creates a package manifest.
  const PackageManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.targets,
    required this.contents,
    required this.dependencies,
    required this.conflicts,
  });

  /// Stable package identifier.
  final String id;

  /// Human-readable package name.
  final String name;

  /// Semantic package version.
  final String version;

  /// Human-readable package purpose.
  final String description;

  /// Agent targets supported by the package.
  final Set<String> targets;

  /// Content paths grouped by their canonical content kind.
  final Map<String, List<String>> contents;

  /// Exact package dependencies.
  final List<PackageDependency> dependencies;

  /// Package identifiers that cannot coexist with this package.
  final Set<String> conflicts;
}

/// A package available from a registered Alfredo source.
class PackageCandidate {
  /// Creates a discovered package candidate.
  const PackageCandidate({
    required this.sourceName,
    required this.sourceRoot,
    required this.packageRoot,
    required this.manifest,
    required this.digest,
  });

  /// User-selected registered source name.
  final String sourceName;

  /// Canonical source root.
  final String sourceRoot;

  /// Canonical package directory.
  final String packageRoot;

  /// Parsed package metadata.
  final PackageManifest manifest;

  /// SHA-256 of all declared package content and its manifest.
  final String digest;
}

/// A deterministic package resolution, ordered dependency-first.
class PackageResolution {
  /// Creates a package resolution.
  const PackageResolution({required this.target, required this.packages});

  /// Agent target requested by the caller.
  final String target;

  /// Packages in deterministic dependency-first order.
  final List<PackageCandidate> packages;
}

/// A locked package identity, including the exact source content digest.
class LockedPackage {
  /// Creates a lockfile package entry.
  const LockedPackage({
    required this.id,
    required this.version,
    required this.source,
    required this.digest,
  });

  /// Package identifier.
  final String id;

  /// Resolved semantic version.
  final String version;

  /// Registered source name that supplied the package.
  final String source;

  /// SHA-256 content digest.
  final String digest;

  /// Serializes this entry into the v1 lockfile format.
  Map<String, Object?> toJson() => {
    'id': id,
    'version': version,
    'source': source,
    'digest': digest,
  };
}

/// Reproducible package resolution information.
class PackageLockfile {
  /// Creates a lockfile.
  const PackageLockfile({required this.target, required this.packages});

  /// Produces a lockfile from a resolution without volatile timestamps.
  factory PackageLockfile.fromResolution(PackageResolution resolution) {
    final packages =
        [
          for (final package in resolution.packages)
            LockedPackage(
              id: package.manifest.id,
              version: package.manifest.version,
              source: package.sourceName,
              digest: package.digest,
            ),
        ]..sort((left, right) {
          final id = left.id.compareTo(right.id);
          return id == 0 ? left.source.compareTo(right.source) : id;
        });
    return PackageLockfile(target: resolution.target, packages: packages);
  }

  /// Schema version for persisted lockfiles.
  static const schemaVersion = 1;

  /// Agent target for this resolution.
  final String target;

  /// Locked packages, sorted by ID and source.
  final List<LockedPackage> packages;

  /// Serializes this lockfile into the v1 format.
  Map<String, Object?> toJson() => {
    'version': schemaVersion,
    'target': target,
    'packages': [for (final package in packages) package.toJson()],
  };
}

/// A file owned by an installed Alfredo package.
class ManagedFile {
  /// Creates a managed-file record.
  const ManagedFile({
    required this.path,
    required this.digest,
    required this.packageId,
  });

  /// Portable path relative to the target root.
  final String path;

  /// SHA-256 of the installed file.
  final String digest;

  /// Package that owns the file.
  final String packageId;

  /// Serializes this record into installed state JSON.
  Map<String, Object?> toJson() => {
    'path': path,
    'digest': digest,
    'package_id': packageId,
  };
}

/// Persisted ownership state for one target installation.
class InstalledState {
  /// Creates an installed state document.
  const InstalledState({required this.target, required this.files});

  /// Schema version for persisted state files.
  static const schemaVersion = 1;

  /// Agent target owning the state.
  final String target;

  /// Installed files sorted by portable path.
  final List<ManagedFile> files;

  /// Serializes this state into the v1 format.
  Map<String, Object?> toJson() => {
    'version': schemaVersion,
    'target': target,
    'files': [for (final file in files) file.toJson()],
  };
}

/// The current condition of an Alfredo-managed file.
enum ManagedFileCondition {
  /// The file is present and identical to the recorded digest.
  unchanged,

  /// The file is present but differs from the recorded digest.
  modified,

  /// The file was removed outside Alfredo.
  missing,
}

/// A managed file with its live condition.
class ManagedFileStatus {
  /// Creates a managed file status.
  const ManagedFileStatus({required this.file, required this.condition});

  /// Persisted ownership record.
  final ManagedFile file;

  /// Current filesystem condition.
  final ManagedFileCondition condition;
}

/// Result of an installation transaction.
class InstallationResult {
  /// Creates an installation result.
  const InstallationResult({
    required this.lockfile,
    required this.installedFiles,
  });

  /// Reproducible lock state after the install.
  final PackageLockfile lockfile;

  /// Files written or replaced by the transaction.
  final List<File> installedFiles;
}
