import 'dart:io';

import 'package:alfredo_cli/src/template/template_models.dart';
import 'package:alfredo_cli/src/template/template_paths.dart';
import 'package:path/path.dart' as p;

/// A template resolved for an artifact request, with why it was chosen.
class TemplateMatch {
  /// Creates a template match.
  const TemplateMatch({required this.template, required this.reason});

  /// The resolved template.
  final Template template;

  /// How it was resolved: `exact-kind`, `name`, or `keyword`.
  final String reason;
}

/// Discovers and resolves templates across the project and user roots.
class TemplateStore {
  /// Creates a template store bound to [roots].
  TemplateStore({required this.roots});

  /// Roots this store scans.
  final TemplateRoots roots;

  /// Every template found, deduped by name with the most authoritative wins.
  Future<List<Template>> list() async {
    final byName = <String, Template>{};
    for (final dir in templateSearchDirs(roots)) {
      if (!dir.existsSync()) continue;
      final origin = _originFor(dir);
      final entries = dir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final entry in entries) {
        final file = File(p.join(entry.path, 'TEMPLATE.md'));
        if (!file.existsSync()) continue;
        final template = Template.parse(
          await file.readAsString(),
          path: _displayPath(file.path),
          origin: origin,
        );
        byName.putIfAbsent(template.name, () => template);
      }
    }
    final templates = byName.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return List.unmodifiable(templates);
  }

  /// The template named [name], or `null` if none is installed.
  Future<Template?> find(String name) async {
    for (final template in await list()) {
      if (template.name == name) return template;
    }
    return null;
  }

  /// Resolves the best template for [query], an artifact kind or free request.
  ///
  /// Deterministic: an exact `name` match wins, then an exact `kind` match.
  /// When [fuzzy] is set, an unresolved query then falls back to the highest
  /// keyword score against name + kind + description, ties broken by name.
  /// A pinned task hint resolves with `fuzzy: false` so it stays predictable.
  Future<TemplateMatch?> match(String query, {bool fuzzy = true}) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final templates = await list();

    for (final template in templates) {
      if (template.name == normalized) {
        return TemplateMatch(template: template, reason: 'name');
      }
    }

    final byKind = templates.where((t) => t.kind == normalized).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (byKind.isNotEmpty) {
      return TemplateMatch(template: byKind.first, reason: 'exact-kind');
    }

    if (!fuzzy) return null;

    final terms = _terms(normalized);
    if (terms.isEmpty) return null;
    final scored = <({Template template, int score})>[];
    for (final template in templates) {
      final haystack = [
        template.name,
        template.kind,
        template.description,
      ].join(' ').toLowerCase();
      var score = 0;
      for (final term in terms) {
        score += haystack.split(term).length - 1;
      }
      if (score > 0) scored.add((template: template, score: score));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.template.name.compareTo(b.template.name);
    });
    return TemplateMatch(template: scored.first.template, reason: 'keyword');
  }

  /// A POSIX-style path relative to the project root when the file lives inside
  /// it, otherwise relative to the user root, otherwise absolute. Forward
  /// slashes keep `sources.templates` and display stable across platforms.
  String _displayPath(String filePath) {
    final project = roots.projectRoot.path;
    if (p.equals(filePath, project) || p.isWithin(project, filePath)) {
      return p.posix.joinAll(p.split(p.relative(filePath, from: project)));
    }
    final user = roots.userRoot.path;
    if (p.isWithin(user, filePath)) {
      return p.posix.joinAll(p.split(p.relative(filePath, from: user)));
    }
    return filePath;
  }

  TemplateOrigin _originFor(Directory dir) {
    final canonical = p.join(roots.projectRoot.path, 'templates');
    if (p.equals(dir.path, canonical)) return TemplateOrigin.canonical;
    if (p.isWithin(roots.projectRoot.path, dir.path)) {
      return TemplateOrigin.project;
    }
    return TemplateOrigin.user;
  }

  static List<String> _terms(String query) => [
    for (final match in RegExp('[a-z0-9]+').allMatches(query))
      if (match[0]!.length > 1) match[0]!,
  ];
}
