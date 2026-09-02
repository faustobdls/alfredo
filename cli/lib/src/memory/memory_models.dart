/// A rejected memory read, write, or configuration operation.
class MemoryException implements Exception {
  /// Creates a memory exception with an actionable [message].
  const MemoryException(this.message);

  /// User-facing failure description.
  final String message;

  @override
  String toString() => message;
}

/// The store that owns a memory record.
enum MemoryScope {
  /// Memory shared by every project of the current user.
  user,

  /// Memory scoped to the current repository.
  project,
}

/// The durability class of a memory record.
enum MemoryEntryKind {
  /// A durable fact that should outlive the session that produced it.
  note,

  /// A time-bound observation about a working session.
  activity,
}

/// Embedding provider settings for semantic recall.
class EmbeddingsConfig {
  /// Creates embedding settings.
  const EmbeddingsConfig({
    this.enabled = false,
    this.provider = defaultProvider,
    this.baseUrl = defaultBaseUrl,
    this.model = defaultModel,
    this.dimensions,
  });

  /// Recreates persisted embedding settings.
  factory EmbeddingsConfig.fromJson(Map<String, Object?> json) {
    _rejectUnknownKeys(json, const {
      'enabled',
      'provider',
      'baseUrl',
      'model',
      'dimensions',
    }, 'embeddings');
    final enabled = json['enabled'];
    if (enabled is! bool) {
      throw const FormatException('Invalid embeddings.enabled value.');
    }
    final provider = json['provider'] ?? defaultProvider;
    if (provider != defaultProvider) {
      throw const FormatException('Invalid embeddings.provider value.');
    }
    final baseUrl = json['baseUrl'] ?? defaultBaseUrl;
    if (baseUrl is! String || !RegExp('^https?://').hasMatch(baseUrl)) {
      throw const FormatException('Invalid embeddings.baseUrl value.');
    }
    final model = json['model'] ?? defaultModel;
    if (model is! String || model.isEmpty) {
      throw const FormatException('Invalid embeddings.model value.');
    }
    final dimensions = json['dimensions'];
    if (dimensions != null && (dimensions is! int || dimensions < 1)) {
      throw const FormatException('Invalid embeddings.dimensions value.');
    }
    return EmbeddingsConfig(
      enabled: enabled,
      baseUrl: baseUrl,
      model: model,
      dimensions: dimensions as int?,
    );
  }

  /// The only embedding provider supported by the v1 contract.
  static const defaultProvider = 'ollama';

  /// Default local Ollama endpoint.
  static const defaultBaseUrl = 'http://127.0.0.1:11434';

  /// Default embedding model.
  static const defaultModel = 'nomic-embed-text';

  /// Whether semantic recall is enabled.
  final bool enabled;

  /// Embedding provider identifier.
  final String provider;

  /// Provider base URL.
  final String baseUrl;

  /// Embedding model name.
  final String model;

  /// Vector length reported by the provider, when known.
  final int? dimensions;

  /// Converts these settings to the durable configuration format.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'provider': provider,
    'baseUrl': baseUrl,
    'model': model,
    if (dimensions != null) 'dimensions': dimensions,
  };
}

/// End-of-session capture settings.
class CaptureConfig {
  /// Creates capture settings.
  const CaptureConfig({
    this.sessionEndHook = false,
    this.gitDiffStat = true,
    this.targets = const [],
  });

  /// Recreates persisted capture settings.
  factory CaptureConfig.fromJson(Map<String, Object?> json) {
    _rejectUnknownKeys(json, const {
      'sessionEndHook',
      'gitDiffStat',
      'targets',
    }, 'capture');
    final sessionEndHook = json['sessionEndHook'];
    if (sessionEndHook is! bool) {
      throw const FormatException('Invalid capture.sessionEndHook value.');
    }
    final gitDiffStat = json['gitDiffStat'] ?? true;
    if (gitDiffStat is! bool) {
      throw const FormatException('Invalid capture.gitDiffStat value.');
    }
    final rawTargets = json['targets'] ?? const <Object?>[];
    if (rawTargets is! List) {
      throw const FormatException('Invalid capture.targets value.');
    }
    final targets = <String>[];
    for (final target in rawTargets) {
      if (target is! String ||
          !supportedTargets.contains(target) ||
          targets.contains(target)) {
        throw const FormatException('Invalid capture.targets value.');
      }
      targets.add(target);
    }
    return CaptureConfig(
      sessionEndHook: sessionEndHook,
      gitDiffStat: gitDiffStat,
      targets: List.unmodifiable(targets),
    );
  }

  /// Agent targets that can receive the memory package.
  static const supportedTargets = <String>[
    'codex',
    'claude-code',
    'cursor',
    'antigravity',
    'devin',
    'generic',
    'gemini-cli',
    'via',
  ];

  /// Whether an end-of-session hook records an activity entry.
  final bool sessionEndHook;

  /// Whether the capture command records `git diff --stat` output.
  final bool gitDiffStat;

  /// Agent targets that received the memory package.
  final List<String> targets;

  /// Converts these settings to the durable configuration format.
  Map<String, Object?> toJson() => {
    'sessionEndHook': sessionEndHook,
    'gitDiffStat': gitDiffStat,
    'targets': [...targets],
  };
}

/// Durable memory configuration for one scope.
class MemoryConfig {
  /// Creates a memory configuration.
  const MemoryConfig({
    required this.embeddings,
    required this.capture,
    required this.defaultScope,
  });

  /// Creates the configuration used before `alfredo memory setup` runs.
  const MemoryConfig.defaults()
    : embeddings = const EmbeddingsConfig(),
      capture = const CaptureConfig(),
      defaultScope = MemoryScope.user;

  /// Recreates a persisted configuration body.
  factory MemoryConfig.fromJson(Map<String, Object?> json) {
    final embeddings = json['embeddings'];
    final capture = json['capture'];
    if (embeddings is! Map || capture is! Map) {
      throw const FormatException('Invalid memory configuration body.');
    }
    final scope = switch (json['defaultScope']) {
      'user' => MemoryScope.user,
      'project' => MemoryScope.project,
      _ => throw const FormatException('Invalid defaultScope value.'),
    };
    return MemoryConfig(
      embeddings: EmbeddingsConfig.fromJson(_asMap(embeddings)),
      capture: CaptureConfig.fromJson(_asMap(capture)),
      defaultScope: scope,
    );
  }

  /// Schema version for persisted memory configuration.
  static const schemaVersion = 1;

  /// Embedding provider settings.
  final EmbeddingsConfig embeddings;

  /// End-of-session capture settings.
  final CaptureConfig capture;

  /// Scope used when a command omits `--scope`.
  final MemoryScope defaultScope;

  /// Converts this configuration into the versioned document format.
  Map<String, Object?> toJson() => {
    'version': schemaVersion,
    'embeddings': embeddings.toJson(),
    'capture': capture.toJson(),
    'defaultScope': defaultScope.name,
  };

  static Map<String, Object?> _asMap(Map<Object?, Object?> value) =>
      value.map((key, item) => MapEntry('$key', item));
}

/// A single journal record.
class MemoryEntry {
  /// Creates a journal entry.
  const MemoryEntry({
    required this.at,
    required this.kind,
    required this.tags,
    required this.message,
    this.scopeLabel = '',
  });

  /// Instant the entry describes.
  final DateTime at;

  /// Durability class of the entry.
  final MemoryEntryKind kind;

  /// Free-form classification tags.
  final List<String> tags;

  /// Entry body.
  final String message;

  /// Human-readable owning scope, when a command merges several stores.
  final String scopeLabel;
}

/// A durable note file.
class MemoryNote {
  /// Creates a durable note.
  const MemoryNote({
    required this.slug,
    required this.title,
    required this.body,
    required this.at,
    required this.tags,
  });

  /// Dated, filesystem-safe identifier without its extension.
  final String slug;

  /// Human-readable note title.
  final String title;

  /// Note body.
  final String body;

  /// Instant the note was written.
  final DateTime at;

  /// Free-form classification tags.
  final List<String> tags;
}

/// A searchable memory file.
class MemoryDocument {
  /// Creates a searchable document.
  const MemoryDocument({
    required this.path,
    required this.kind,
    required this.title,
    required this.text,
    this.at,
  });

  /// Portable path relative to the memory directory.
  final String path;

  /// Durability class of the document.
  final MemoryEntryKind kind;

  /// Human-readable document title.
  final String title;

  /// Full document text.
  final String text;

  /// Date encoded in the document path, when present.
  final DateTime? at;
}

/// A ranked search result.
class MemorySearchHit {
  /// Creates a search hit.
  const MemorySearchHit({
    required this.path,
    required this.title,
    required this.excerpt,
    required this.score,
    this.scopeLabel = '',
  });

  /// Portable path relative to the memory directory.
  final String path;

  /// Human-readable document title.
  final String title;

  /// Single-line context around the first match.
  final String excerpt;

  /// Ranking score; term counts for keyword search, cosine for embeddings.
  final double score;

  /// Human-readable owning scope, when a command merges several stores.
  final String scopeLabel;

  /// Returns a copy of this hit that records its owning [label].
  MemorySearchHit withScopeLabel(String label) => MemorySearchHit(
    path: path,
    title: title,
    excerpt: excerpt,
    score: score,
    scopeLabel: label,
  );
}

void _rejectUnknownKeys(
  Map<String, Object?> value,
  Set<String> allowed,
  String context,
) {
  for (final key in value.keys) {
    if (!allowed.contains(key)) {
      throw FormatException('Unknown $context key: $key');
    }
  }
}
