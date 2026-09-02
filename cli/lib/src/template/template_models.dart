import 'package:yaml/yaml.dart';

/// A rejected template read, parse, or validation operation.
class TemplateException implements Exception {
  /// Creates a template exception with an actionable [message].
  const TemplateException(this.message);

  /// User-facing failure description.
  final String message;

  @override
  String toString() => message;
}

/// Where a resolved template was discovered.
enum TemplateOrigin {
  /// A canonical `templates/` tree at the project root.
  canonical,

  /// An installed `<adapter>/templates/` tree inside the current project.
  project,

  /// An installed `<adapter>/templates/` tree under the user's home.
  user,
}

/// One output template: an artifact contract parsed from a `TEMPLATE.md`.
///
/// Only the four required frontmatter fields are typed. Everything else stays
/// in [frontmatter] as plain maps and lists so a template can carry richer
/// guidance without a model change here.
class Template {
  /// Creates a parsed template.
  const Template({
    required this.name,
    required this.kind,
    required this.description,
    required this.frontmatter,
    required this.body,
    required this.path,
    required this.origin,
  });

  /// Parses [markdown] (a full `TEMPLATE.md`) discovered at [path].
  factory Template.parse(
    String markdown, {
    required String path,
    required TemplateOrigin origin,
  }) {
    final frontmatter = _readFrontmatter(markdown, path);
    validateTemplateFrontmatter(frontmatter, path: path);
    return Template(
      name: frontmatter['name']! as String,
      kind: frontmatter['kind']! as String,
      description: frontmatter['description']! as String,
      frontmatter: frontmatter,
      body: _readBody(markdown),
      path: path,
      origin: origin,
    );
  }

  /// Directory-derived identifier, matching the enclosing folder name.
  final String name;

  /// Artifact class this template governs, for example `email` or `slides`.
  final String kind;

  /// "Use for … Not for …" line an agent reads to decide whether to apply it.
  final String description;

  /// Full parsed frontmatter, including the typed fields above.
  final Map<String, Object?> frontmatter;

  /// The prose contract below the frontmatter.
  final String body;

  /// Repo- or home-relative path to the `TEMPLATE.md`.
  final String path;

  /// Where the template was discovered.
  final TemplateOrigin origin;

  /// The declared render target, for example `markdown` or `pptx`.
  String? get formatTarget {
    final format = frontmatter['format'];
    return format is Map<String, Object?> ? format['target'] as String? : null;
  }

  /// The template-relative theme asset path, if the template declares one.
  String? get themePath {
    final format = frontmatter['format'];
    return format is Map<String, Object?> ? format['theme'] as String? : null;
  }

  /// A one-line summary for `list` and `match` output.
  String get summary => '$name  ($kind)  $description';
}

/// Validates the parsed frontmatter of a template.
///
/// Mirrors the hand-rolled contract style of `CatalogContractValidator`; the
/// CLI does not depend on a JSON Schema runtime.
void validateTemplateFrontmatter(
  Map<String, Object?> frontmatter, {
  required String path,
}) {
  void fail(String reason) =>
      throw TemplateException('Invalid template $path: $reason');

  const known = {
    'schema_version',
    'name',
    'kind',
    'description',
    'voice',
    'structure',
    'length',
    'format',
    'constraints',
    'examples',
  };
  final unknown = frontmatter.keys.where((key) => !known.contains(key)).toList()
    ..sort();
  if (unknown.isNotEmpty) {
    fail('unknown frontmatter keys: ${unknown.join(', ')}');
  }

  if (frontmatter['schema_version'] != 1) {
    fail('schema_version must be 1');
  }

  final idPattern = RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$');
  for (final field in const ['name', 'kind']) {
    final value = frontmatter[field];
    if (value is! String || !idPattern.hasMatch(value) || value.length > 64) {
      fail('$field must be a lowercase-hyphen identifier');
    }
  }

  final description = frontmatter['description'];
  if (description is! String ||
      description.isEmpty ||
      description.length > 1024) {
    fail('description must be a non-empty string');
  }

  final voice = frontmatter['voice'];
  if (voice != null) {
    if (voice is! Map<String, Object?>) fail('voice must be a map');
    const voiceKeys = {'temperature', 'person', 'greeting', 'signoff'};
    final extra = (voice as Map<String, Object?>).keys
        .where((key) => !voiceKeys.contains(key))
        .toList();
    if (extra.isNotEmpty) fail('unknown voice keys: ${extra.join(', ')}');
    final temperature = voice['temperature'];
    if (temperature != null &&
        !const ['formal', 'neutral', 'warm', 'casual'].contains(temperature)) {
      fail('voice.temperature must be formal, neutral, warm, or casual');
    }
  }

  final format = frontmatter['format'];
  if (format != null) {
    if (format is! Map<String, Object?>) fail('format must be a map');
    const formatKeys = {'target', 'theme'};
    final extra = (format as Map<String, Object?>).keys
        .where((key) => !formatKeys.contains(key))
        .toList();
    if (extra.isNotEmpty) fail('unknown format keys: ${extra.join(', ')}');
    final target = format['target'];
    const targets = [
      'markdown',
      'plain',
      'email',
      'pptx',
      'marp',
      'gamma',
      'figma-slides',
      'docx',
      'html',
    ];
    if (target != null && !targets.contains(target)) {
      fail('format.target must be one of: ${targets.join(', ')}');
    }
    final theme = format['theme'];
    if (theme != null && (theme is! String || !_isSafeRelativePath(theme))) {
      fail('format.theme must be a template-relative path');
    }
  }

  final examples = frontmatter['examples'];
  if (examples != null) {
    if (examples is! List) fail('examples must be a list');
    for (final example in examples as List) {
      if (example is! String || !_isSafeRelativePath(example)) {
        fail('examples entries must be template-relative paths');
      }
    }
  }

  final constraints = frontmatter['constraints'];
  if (constraints != null) {
    if (constraints is! Map<String, Object?>) fail('constraints must be a map');
    const constraintKeys = {'always', 'never'};
    final extra = (constraints as Map<String, Object?>).keys
        .where((key) => !constraintKeys.contains(key))
        .toList();
    if (extra.isNotEmpty) {
      fail('unknown constraints keys: ${extra.join(', ')}');
    }
    for (final key in constraintKeys) {
      final value = constraints[key];
      if (value != null && value is! List) {
        fail('constraints.$key must be a list');
      }
    }
  }

  final length = frontmatter['length'];
  if (length != null) {
    if (length is! Map<String, Object?>) fail('length must be a map');
    const lengthKeys = {'min_words', 'max_words', 'max_chars', 'max_slides'};
    final extra = (length as Map<String, Object?>).keys
        .where((key) => !lengthKeys.contains(key))
        .toList();
    if (extra.isNotEmpty) fail('unknown length keys: ${extra.join(', ')}');
    for (final entry in length.entries) {
      if (entry.value is! int) fail('length.${entry.key} must be an integer');
    }
  }
}

bool _isSafeRelativePath(String value) {
  if (value.isEmpty || value.length > 512) return false;
  if (value.startsWith('/') || value.contains('//')) return false;
  final segments = value.split('/');
  if (segments.contains('..')) return false;
  return RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]*$').hasMatch(value);
}

Map<String, Object?> _readFrontmatter(String markdown, String path) {
  final normalized = markdown.replaceAll('\r\n', '\n');
  if (!normalized.startsWith('---\n')) {
    throw TemplateException(
      'Invalid template $path: missing --- frontmatter block',
    );
  }
  final end = normalized.indexOf('\n---', 4);
  if (end == -1) {
    throw TemplateException(
      'Invalid template $path: unterminated frontmatter block',
    );
  }
  final yamlText = normalized.substring(4, end + 1);
  final Object? parsed;
  try {
    parsed = loadYaml(yamlText);
  } on YamlException catch (error) {
    throw TemplateException('Cannot parse template $path: ${error.message}');
  }
  if (parsed is! Map) {
    throw TemplateException(
      'Invalid template $path: frontmatter must be a YAML map',
    );
  }
  return _plain(parsed)! as Map<String, Object?>;
}

String _readBody(String markdown) {
  final normalized = markdown.replaceAll('\r\n', '\n');
  final end = normalized.indexOf('\n---', 4);
  if (end == -1) return '';
  final afterFence = normalized.indexOf('\n', end + 1);
  if (afterFence == -1) return '';
  return normalized.substring(afterFence + 1).trim();
}

Object? _plain(Object? value) {
  if (value is Map) {
    return value.map<String, Object?>(
      (key, item) => MapEntry('$key', _plain(item)),
    );
  }
  if (value is List) {
    return value.map<Object?>(_plain).toList(growable: false);
  }
  return value;
}
