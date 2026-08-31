import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/memory/memory_models.dart';

/// Adds an end-of-session command to an agent settings file without loss.
///
/// The merge is additive and idempotent: unrelated keys are preserved, an
/// unreadable file is refused instead of replaced, and the previous contents
/// are copied to `<path>.alfredo-bak` before the first modification.
class HookWriter {
  /// Creates a hook writer.
  const HookWriter();

  /// Hook events that receive [ensureStopHook] commands.
  static const events = <String>['Stop', 'SessionEnd'];

  /// Ensures every event in [events] runs [command]; returns `true` on change.
  Future<bool> ensureStopHook(File settingsFile, String command) async {
    final document = await _read(settingsFile);
    final hooks = document['hooks'] ?? <String, Object?>{};
    if (hooks is! Map) {
      throw MemoryException(
        'Refusing to edit unparseable settings.json: ${settingsFile.path}',
      );
    }
    final merged = <String, Object?>{
      for (final entry in hooks.entries) '${entry.key}': entry.value,
    };

    var changed = false;
    for (final event in events) {
      final current = merged[event] ?? <Object?>[];
      if (current is! List) {
        throw MemoryException(
          'Refusing to edit unparseable settings.json: ${settingsFile.path}',
        );
      }
      if (current.any((matcher) => _containsCommand(matcher, command))) {
        merged[event] = current;
        continue;
      }
      merged[event] = [
        ...current,
        <String, Object?>{
          'hooks': [
            <String, Object?>{'type': 'command', 'command': command},
          ],
        },
      ];
      changed = true;
    }
    if (!changed) return false;

    if (settingsFile.existsSync()) {
      await settingsFile.copy('${settingsFile.path}.alfredo-bak');
    }
    await _write(settingsFile, {...document, 'hooks': merged});
    return true;
  }

  Future<Map<String, Object?>> _read(File settingsFile) async {
    if (!settingsFile.existsSync()) return <String, Object?>{};
    final Object? document;
    try {
      document = jsonDecode(await settingsFile.readAsString());
    } on FormatException {
      throw MemoryException(
        'Refusing to edit unparseable settings.json: ${settingsFile.path}',
      );
    }
    if (document is! Map) {
      throw MemoryException(
        'Refusing to edit unparseable settings.json: ${settingsFile.path}',
      );
    }
    return {for (final entry in document.entries) '${entry.key}': entry.value};
  }

  static Future<void> _write(File file, Map<String, Object?> document) async {
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final temporary = File('${file.path}.$pid.$nonce.tmp');
    try {
      await file.parent.create(recursive: true);
      await temporary.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(document)}\n',
        flush: true,
      );
      await temporary.rename(file.path);
    } on FileSystemException catch (error) {
      throw MemoryException('Cannot update ${file.path}: ${error.message}');
    } finally {
      if (temporary.existsSync()) await temporary.delete();
    }
  }

  static bool _containsCommand(Object? matcher, String command) {
    if (matcher is! Map) return false;
    final hooks = matcher['hooks'];
    if (hooks is! List) return false;
    return hooks.any(
      (hook) => hook is Map && hook['command'] == command,
    );
  }
}
