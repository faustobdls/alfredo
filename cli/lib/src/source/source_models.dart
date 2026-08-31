/// The supported source transport.
enum SourceKind {
  /// A directory that already exists on the local filesystem.
  local,

  /// A snapshot materialized from an immutable Git commit.
  git,

  /// A snapshot extracted from a checksum-verified archive.
  archive,
}

/// The immutable transport details that produced a source snapshot.
class SourceTransport {
  /// Creates transport metadata for a non-local source.
  const SourceTransport({
    required this.kind,
    required this.url,
    this.revision,
    this.resolvedRevision,
    this.sha256,
  });

  /// Recreates persisted transport metadata.
  factory SourceTransport.fromJson(Map<String, Object?> json) {
    final kindValue = json['kind'];
    final url = json['url'];
    if (kindValue is! String || url is! String) {
      throw const FormatException('Invalid source transport metadata.');
    }
    final kind = switch (kindValue) {
      'git' => SourceKind.git,
      'archive' => SourceKind.archive,
      _ => throw const FormatException('Invalid source transport kind.'),
    };
    final revision = json['revision'];
    final resolvedRevision = json['resolved_revision'];
    final sha256 = json['sha256'];
    if ((revision != null && revision is! String) ||
        (resolvedRevision != null && resolvedRevision is! String) ||
        (sha256 != null && sha256 is! String)) {
      throw const FormatException('Invalid source transport metadata.');
    }
    if (kind == SourceKind.git &&
        (revision is! String || resolvedRevision is! String)) {
      throw const FormatException('Git source metadata is incomplete.');
    }
    if (kind == SourceKind.archive && sha256 is! String) {
      throw const FormatException('Archive source metadata is incomplete.');
    }
    return SourceTransport(
      kind: kind,
      url: url,
      revision: revision as String?,
      resolvedRevision: resolvedRevision as String?,
      sha256: sha256 as String?,
    );
  }

  /// Source transport.
  final SourceKind kind;

  /// Canonical remote URI.
  final String url;

  /// User-requested Git revision, when [kind] is [SourceKind.git].
  final String? revision;

  /// Full Git commit resolved from [revision], when applicable.
  final String? resolvedRevision;

  /// Expected archive SHA-256, when [kind] is [SourceKind.archive].
  final String? sha256;

  /// Converts this transport to the durable registry format.
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'url': url,
    if (revision != null) 'revision': revision,
    if (resolvedRevision != null) 'resolved_revision': resolvedRevision,
    if (sha256 != null) 'sha256': sha256,
  };
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

/// A registered local or immutable remote source.
class RegisteredSource {
  /// Creates a registered source.
  const RegisteredSource({
    required this.name,
    required this.kind,
    required this.location,
    required this.sourceId,
    required this.sourceName,
    this.transport,
  });

  /// Parses a registration from persisted JSON.
  factory RegisteredSource.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    final kind = json['kind'];
    final location = json['location'];
    final sourceId = json['source_id'];
    final sourceName = json['source_name'];
    if (name is! String ||
        kind is! String ||
        location is! String ||
        sourceId is! String ||
        sourceName is! String) {
      throw const FormatException('Invalid source registry entry.');
    }
    final sourceKind = switch (kind) {
      'local' => SourceKind.local,
      'git' => SourceKind.git,
      'archive' => SourceKind.archive,
      _ => throw const FormatException('Invalid source registry kind.'),
    };
    final transportValue = json['transport'];
    final transport = transportValue == null
        ? null
        : SourceTransport.fromJson(_asMap(transportValue));
    if ((sourceKind == SourceKind.local && transport != null) ||
        (sourceKind != SourceKind.local &&
            (transport == null || transport.kind != sourceKind))) {
      throw const FormatException('Invalid source registry transport.');
    }
    return RegisteredSource(
      name: name,
      kind: sourceKind,
      location: location,
      sourceId: sourceId,
      sourceName: sourceName,
      transport: transport,
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

  /// Immutable origin metadata for Git and archive registrations.
  final SourceTransport? transport;

  /// Converts this registration to persisted JSON.
  Map<String, Object?> toJson() {
    final sourceTransport = transport;
    return {
      'name': name,
      'kind': kind.name,
      'location': location,
      'source_id': sourceId,
      'source_name': sourceName,
      if (sourceTransport != null) 'transport': sourceTransport.toJson(),
    };
  }

  static Map<String, Object?> _asMap(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid source transport metadata.');
    }
    return value.map((key, item) => MapEntry('$key', item));
  }
}

/// The kind of change a source registry refresh applied to a registration.
enum SourceRefreshKind {
  /// A local source whose content is always read live.
  live,

  /// A remote source already at its newest resolved revision.
  unchanged,

  /// A remote source advanced to a newer resolved revision.
  updated,

  /// A checksum-pinned archive source that cannot be moved.
  pinned,
}

/// The result of revalidating and possibly advancing a registered source.
class SourceRefresh {
  /// Creates a source refresh result.
  const SourceRefresh({
    required this.kind,
    required this.source,
    this.previousRevision,
    this.newRevision,
  });

  /// What happened to the registration.
  final SourceRefreshKind kind;

  /// The registration after the refresh.
  final RegisteredSource source;

  /// Resolved revision before the refresh, for remote sources.
  final String? previousRevision;

  /// Resolved revision after the refresh, for remote sources.
  final String? newRevision;
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
