/// The supported source transport.
enum SourceKind {
  /// A directory that already exists on the local filesystem.
  local,
}

/// A package entry declared by an Alfredo source manifest.
class SourcePackage {
  /// Creates a package entry.
  const SourcePackage({
    required this.id,
    required this.path,
    required this.version,
    required this.description,
  });

  /// Stable package identifier.
  final String id;

  /// Portable path to the package manifest, relative to the source root.
  final String path;

  /// Semantic package version.
  final String version;

  /// Human-readable package purpose.
  final String description;
}

/// A validated Alfredo source and its package summaries.
class SourceCatalog {
  /// Creates a validated source catalog.
  const SourceCatalog({
    required this.id,
    required this.name,
    required this.root,
    required this.packages,
  });

  /// Stable source identifier.
  final String id;

  /// Human-readable source name.
  final String name;

  /// Canonical source directory.
  final String root;

  /// Packages declared by the source.
  final List<SourcePackage> packages;
}

/// A locally registered source.
class RegisteredSource {
  /// Creates a registered source.
  const RegisteredSource({
    required this.name,
    required this.kind,
    required this.location,
    required this.sourceId,
    required this.sourceName,
  });

  /// Parses a registration from persisted JSON.
  factory RegisteredSource.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final kind = json['kind'];
    final location = json['location'];
    final sourceId = json['source_id'];
    final sourceName = json['source_name'];
    if (name is! String ||
        kind != SourceKind.local.name ||
        location is! String ||
        sourceId is! String ||
        sourceName is! String) {
      throw const FormatException('Invalid source registry entry.');
    }
    return RegisteredSource(
      name: name,
      kind: SourceKind.local,
      location: location,
      sourceId: sourceId,
      sourceName: sourceName,
    );
  }

  /// User-selected registration name.
  final String name;

  /// Source transport.
  final SourceKind kind;

  /// Canonical source location.
  final String location;

  /// ID read from the source manifest when it was registered.
  final String sourceId;

  /// Name read from the source manifest when it was registered.
  final String sourceName;

  /// Converts this registration to persisted JSON.
  Map<String, Object?> toJson() => {
    'name': name,
    'kind': kind.name,
    'location': location,
    'source_id': sourceId,
    'source_name': sourceName,
  };
}

/// A rejected source, manifest, or registry operation.
class SourceException implements Exception {
  /// Creates a source exception with an actionable [message].
  const SourceException(this.message);

  /// User-facing failure description.
  final String message;

  @override
  String toString() => message;
}
