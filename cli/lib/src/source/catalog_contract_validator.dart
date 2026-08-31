import 'package:alfredo_cli/src/source/source_models.dart';

/// Runtime validation shared by source and package manifest loaders.
class CatalogContractValidator {
  /// Creates a catalog contract validator.
  const CatalogContractValidator();

  static final _idPattern = RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$');
  static final _semverPattern = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    r'(?:-(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)'
    r'(?:\.(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*))*)?'
    r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
  );
  static final _pathPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._/-]*$');
  static final _sha256Pattern = RegExp(r'^[A-Fa-f0-9]{64}$');
  static const _targets = {
    'codex',
    'claude-code',
    'cursor',
    'antigravity',
    'generic',
  };
  static const _contentKinds = {
    'skills',
    'rules',
    'scripts',
    'assets',
    'references',
  };

  /// Validates a source manifest consumed through `source add --local`.
  void validateLocalSource(Map<String, Object?> source) {
    _rejectUnknownKeys(source, const {
      'schema_version',
      'id',
      'name',
      'description',
      'kind',
      'url',
      'path',
      'revision',
      'sha256',
      'read_only',
      'packages_path',
      'profiles_path',
    }, 'source');
    _requireSchemaVersion(source, 'source');
    requireId(source['id'], 'source id');
    _requireText(source['name'], 'source name');
    _optionalText(source, 'description');
    if (source['kind'] != SourceKind.local.name) {
      throw const SourceException('Only local source manifests are supported.');
    }
    if (source['read_only'] != true) {
      throw const SourceException('Source manifests must be read-only.');
    }
    requireRelativePath(source['path'], field: 'path', allowDot: true);
    requireRelativePath(
      source['packages_path'],
      field: 'packages_path',
      allowDot: true,
    );
    if (source.containsKey('profiles_path')) {
      requireRelativePath(
        source['profiles_path'],
        field: 'profiles_path',
        allowDot: true,
      );
    }
    _optionalText(source, 'revision');
    if (source['url'] case final String url) {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) {
        throw SourceException('Invalid source url: $url');
      }
    } else if (source.containsKey('url')) {
      throw const SourceException('Missing or invalid source url.');
    }
    if (source['sha256'] case final String digest) {
      if (!_sha256Pattern.hasMatch(digest)) {
        throw const SourceException('Invalid source sha256.');
      }
    } else if (source.containsKey('sha256')) {
      throw const SourceException('Missing or invalid source sha256.');
    }
  }

  /// Validates a package manifest against the v1 package contract.
  void validatePackage(Map<String, Object?> package) {
    _rejectUnknownKeys(package, const {
      'schema_version',
      'id',
      'name',
      'version',
      'description',
      'license',
      'targets',
      'contents',
      'dependencies',
      'conflicts',
    }, 'package');
    _requireSchemaVersion(package, 'package');
    final id = requireId(package['id'], 'package id');
    _requireText(package['name'], 'package name');
    _requireText(package['description'], 'package description');
    _optionalText(package, 'license');
    requireVersion(package['version'], id);
    _validateTargets(package['targets'], id);
    _validateContents(package['contents'], id);
    if (package.containsKey('dependencies')) {
      _validateDependencies(package['dependencies']);
    }
    if (package.containsKey('conflicts')) {
      _validateConflicts(package['conflicts']);
    }
  }

  /// Returns a validated lowercase-hyphen identifier.
  String requireId(Object? value, String field) {
    final text = _requireText(value, field, maxLength: 64);
    if (!_idPattern.hasMatch(text)) {
      throw SourceException('Invalid $field: $text');
    }
    return text;
  }

  /// Returns a validated semantic version.
  String requireVersion(Object? value, String packageId) {
    final version = _requireText(value, 'package version');
    if (!_semverPattern.hasMatch(version)) {
      throw SourceException(
        'Invalid semantic version for $packageId: $version',
      );
    }
    return version;
  }

  /// Returns a validated portable relative path.
  String requireRelativePath(
    Object? value, {
    required String field,
    bool allowDot = false,
  }) {
    final path = _requireText(value, field, maxLength: 512);
    if ((allowDot && path == '.') ||
        (_pathPattern.hasMatch(path) &&
            !path.contains('//') &&
            !path.split('/').contains('..'))) {
      return path;
    }
    throw SourceException('$field must stay inside the source: $path');
  }

  void _validateTargets(Object? value, String packageId) {
    final values = _requireList(value, 'Package targets must be a list.');
    if (values.isEmpty) {
      throw SourceException('Package targets cannot be empty: $packageId');
    }
    final seen = <String>{};
    for (final target in values) {
      if (target is! String || !_targets.contains(target)) {
        throw SourceException('Invalid package target for $packageId: $target');
      }
      if (!seen.add(target)) {
        throw SourceException(
          'Duplicate package target for $packageId: $target',
        );
      }
    }
  }

  void _validateContents(Object? value, String packageId) {
    final contents = _requireMap(
      value,
      'Package contents must be an object: $packageId',
    );
    _rejectUnknownKeys(contents, _contentKinds, 'package contents');
    for (final entry in contents.entries) {
      final paths = _requireList(
        entry.value,
        'Package content ${entry.key} must be a list.',
      );
      final seen = <String>{};
      for (final path in paths) {
        final validated = requireRelativePath(path, field: entry.key);
        if (!seen.add(validated)) {
          throw SourceException(
            'Duplicate package content path in ${entry.key}: $validated',
          );
        }
      }
    }
  }

  void _validateDependencies(Object? value) {
    final dependencies = _requireList(
      value,
      'Package dependencies must be a list.',
    );
    final seen = <String>{};
    for (final dependency in dependencies) {
      final map = _requireMap(
        dependency,
        'Each package dependency must be an object.',
      );
      _rejectUnknownKeys(map, const {'id', 'version'}, 'package dependency');
      final id = requireId(map['id'], 'dependency id');
      final version = requireVersion(map['version'], id);
      if (!seen.add('$id@$version')) {
        throw SourceException('Duplicate package dependency: $id@$version');
      }
    }
  }

  void _validateConflicts(Object? value) {
    final conflicts = _requireList(value, 'Package conflicts must be a list.');
    final seen = <String>{};
    for (final conflict in conflicts) {
      final id = requireId(conflict, 'conflict id');
      if (!seen.add(id)) {
        throw SourceException('Duplicate package conflict: $id');
      }
    }
  }

  static void _requireSchemaVersion(
    Map<String, Object?> map,
    String context,
  ) {
    if (map['schema_version'] != 1) {
      throw SourceException('Unsupported $context schema version.');
    }
  }

  static String _requireText(
    Object? value,
    String field, {
    int maxLength = 256,
  }) {
    if (value is! String || value.isEmpty || value.length > maxLength) {
      throw SourceException('Missing or invalid $field.');
    }
    return value;
  }

  static void _optionalText(Map<String, Object?> map, String field) {
    if (map.containsKey(field)) _requireText(map[field], field);
  }

  static Map<String, Object?> _requireMap(Object? value, String message) {
    if (value is! Map<String, Object?>) throw SourceException(message);
    return value;
  }

  static List<Object?> _requireList(Object? value, String message) {
    if (value is! List<Object?>) throw SourceException(message);
    return value;
  }

  static void _rejectUnknownKeys(
    Map<String, Object?> map,
    Set<String> allowed,
    String context,
  ) {
    final unknown = map.keys.where((key) => !allowed.contains(key)).toList()
      ..sort();
    if (unknown.isNotEmpty) {
      throw SourceException(
        'Unknown $context properties: ${unknown.join(', ')}',
      );
    }
  }
}
