import 'dart:io';

import 'package:alfredo_cli/src/source/source_models.dart';
import 'package:path/path.dart' as p;

/// Resolves the local source registry file for the current platform.
File defaultSourceRegistryFile({
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final env = environment ?? Platform.environment;
  final override = env['ALFREDO_CONFIG_HOME'];
  if (override != null && override.trim().isNotEmpty) {
    return File(p.join(override, 'sources.json'));
  }

  final os = operatingSystem ?? Platform.operatingSystem;
  if (os == 'windows') {
    final root = env['APPDATA'];
    if (root == null || root.isEmpty) {
      throw const SourceException('APPDATA is required on Windows.');
    }
    return File(
      p.Context(style: p.Style.windows).join(root, 'Alfredo', 'sources.json'),
    );
  }

  final home = env['HOME'];
  if (home == null || home.isEmpty) {
    throw const SourceException(
      'HOME is required to store Alfredo configuration.',
    );
  }
  if (os == 'macos') {
    return File(
      p.join(home, 'Library', 'Application Support', 'Alfredo', 'sources.json'),
    );
  }
  final root = env['XDG_CONFIG_HOME'];
  return File(
    p.join(
      root == null || root.isEmpty ? p.join(home, '.config') : root,
      'alfredo',
      'sources.json',
    ),
  );
}
