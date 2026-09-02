import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/template/template.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

const _prettyJson = JsonEncoder.withIndent('  ');
final _idPattern = RegExp(r'^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$');
const _formatTargetExamples =
    'markdown, plain, email, pptx, marp, gamma, figma-slides, docx, html';

/// Manages output templates: artifact contracts an agent follows when
/// producing an email, a slide deck, a memo, or any other deliverable.
class TemplateCommand extends Command<int> {
  /// Creates the template command group.
  TemplateCommand({required Logger logger, TemplateRoots? roots}) {
    final resolved = roots ?? defaultTemplateRoots();
    addSubcommand(_ListTemplates(logger: logger, roots: resolved));
    addSubcommand(_ShowTemplate(logger: logger, roots: resolved));
    addSubcommand(_NewTemplate(logger: logger, roots: resolved));
    addSubcommand(_ValidateTemplate(logger: logger, roots: resolved));
    addSubcommand(_MatchTemplate(logger: logger, roots: resolved));
  }

  @override
  String get description =>
      'Create, inspect, and resolve output templates for authored artifacts.';

  @override
  String get name => 'template';
}

abstract class _TemplateSubcommand extends Command<int> {
  _TemplateSubcommand({required this.logger, required this.roots});

  /// User-facing command logger.
  final Logger logger;

  /// Project and user roots templates are discovered under.
  final TemplateRoots roots;

  /// A store bound to [roots].
  TemplateStore get store => TemplateStore(roots: roots);
}

class _ListTemplates extends _TemplateSubcommand {
  _ListTemplates({required super.logger, required super.roots}) {
    argParser.addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'List every installed and canonical template.';

  @override
  String get name => 'list';

  @override
  Future<int> run() async {
    final templates = await store.list();
    if (argResults!['json'] as bool) {
      logger.info(
        _prettyJson.convert([
          for (final template in templates)
            {
              'name': template.name,
              'kind': template.kind,
              'description': template.description,
              'origin': template.origin.name,
              'path': template.path,
            },
        ]),
      );
      return ExitCode.success.code;
    }
    if (templates.isEmpty) {
      logger.info(
        'No templates found. Author one with: alfredo template new <name> '
        '--kind <kind> --description <text> --format-target <target>',
      );
      return ExitCode.success.code;
    }
    for (final template in templates) {
      logger.info(
        '${template.name.padRight(24)} ${template.kind.padRight(12)} '
        '${template.description}',
      );
    }
    return ExitCode.success.code;
  }
}

class _ShowTemplate extends _TemplateSubcommand {
  _ShowTemplate({required super.logger, required super.roots}) {
    argParser.addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description => 'Print one template contract in full.';

  @override
  String get name => 'show';

  @override
  String get invocation => 'alfredo template show <name>';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one template name.', usage);
    }
    final template = await store.find(argResults!.rest.single);
    if (template == null) {
      throw UsageException(
        'No template named "${argResults!.rest.single}".',
        usage,
      );
    }
    if (argResults!['json'] as bool) {
      logger.info(
        _prettyJson.convert({
          'name': template.name,
          'kind': template.kind,
          'description': template.description,
          'origin': template.origin.name,
          'path': template.path,
          'frontmatter': template.frontmatter,
          'body': template.body,
        }),
      );
      return ExitCode.success.code;
    }
    logger.info(
      'name: ${template.name}\n'
      'kind: ${template.kind}\n'
      'origin: ${template.origin.name}\n'
      'path: ${template.path}\n'
      'description: ${template.description}\n'
      '\n${template.body}',
    );
    return ExitCode.success.code;
  }
}

class _NewTemplate extends _TemplateSubcommand {
  _NewTemplate({required super.logger, required super.roots}) {
    argParser
      ..addOption(
        'kind',
        help: 'Artifact kind, for example email, slides, doc, memo.',
        valueHelp: 'kind',
      )
      ..addOption(
        'description',
        help: 'What this template is for, written as its applicability rule.',
        valueHelp: 'text',
      )
      ..addOption(
        'format-target',
        help:
            'Rendered artifact format. Suggestions: $_formatTargetExamples. '
            'Project-defined values are allowed.',
        valueHelp: 'target',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Scaffold even if the template directory already has files.',
      );
  }

  @override
  String get description => 'Scaffold a new template under templates/<name>/.';

  @override
  String get name => 'new';

  @override
  String get invocation =>
      'alfredo template new <name> --kind <kind> --description <text> '
      '--format-target <target>';

  @override
  Future<int> run() async {
    if (argResults!.rest.length != 1) {
      throw UsageException('Expected exactly one template name.', usage);
    }
    final name = argResults!.rest.single.trim();
    if (!_idPattern.hasMatch(name)) {
      throw UsageException(
        'Template name "$name" must match ${_idPattern.pattern}.',
        usage,
      );
    }
    final kind = (argResults!['kind'] as String?)?.trim();
    if (kind == null || kind.isEmpty) {
      throw UsageException('Pass --kind (email, slides, doc, memo, …).', usage);
    }
    if (!_idPattern.hasMatch(kind)) {
      throw UsageException(
        'Template kind "$kind" must match ${_idPattern.pattern}.',
        usage,
      );
    }
    final description = (argResults!['description'] as String?)?.trim();
    if (description == null || description.isEmpty) {
      throw UsageException(
        'Pass --description to explain what this template is for.',
        usage,
      );
    }
    final formatTarget = (argResults!['format-target'] as String?)?.trim();
    if (formatTarget == null || formatTarget.isEmpty) {
      throw UsageException(
        'Pass --format-target ($_formatTargetExamples, or a project-defined '
        'target).',
        usage,
      );
    }
    if (!_idPattern.hasMatch(formatTarget)) {
      throw UsageException(
        'Template format target "$formatTarget" must match '
        '${_idPattern.pattern}.',
        usage,
      );
    }
    final force = argResults!['force'] as bool;

    final dir = Directory(
      p.join(roots.projectRoot.path, 'templates', name),
    );
    final file = File(p.join(dir.path, 'TEMPLATE.md'));
    if (file.existsSync() && !force) {
      throw UsageException(
        '${file.path} already exists. Re-run with --force to overwrite.',
        usage,
      );
    }
    if (dir.existsSync() && dir.listSync().isNotEmpty && !force) {
      throw UsageException(
        '${dir.path} is not empty. Re-run with --force to scaffold anyway.',
        usage,
      );
    }

    await dir.create(recursive: true);
    await file.writeAsString(
      _skeleton(
        name: name,
        kind: kind,
        description: description,
        formatTarget: formatTarget,
      ),
    );

    logger
      ..success('Scaffolded template "$name" at ${file.path}.')
      ..info('Next steps:')
      ..info('  1. Fill in voice, structure, and constraints in TEMPLATE.md.')
      ..info('  2. Validate it: alfredo template validate $name')
      ..info(
        '  3. Ship it in a package via contents.templates, or keep it local.',
      );
    return ExitCode.success.code;
  }

  String _skeleton({
    required String name,
    required String kind,
    required String description,
    required String formatTarget,
  }) =>
      '''
---
schema_version: 1
name: $name
kind: $kind
description: $description
voice:
  temperature: neutral
  person: first-person-plural
structure:
  - opening: state the purpose in one sentence
  - body: one idea per paragraph
  - close: the explicit next step
length:
  max_words: 300
format:
  target: $formatTarget
constraints:
  always: []
  never: []
examples: []
---

Blank template contract for "$kind".

Describe, in prose, what this artifact is, how it should come out, the tone to
hold, phrasing to prefer and avoid, and the reasoning behind the structure
above. An agent reads this before it writes.
''';
}

class _ValidateTemplate extends _TemplateSubcommand {
  _ValidateTemplate({required super.logger, required super.roots});

  @override
  String get description =>
      'Validate one template, or every template when no name is given.';

  @override
  String get name => 'validate';

  @override
  String get invocation => 'alfredo template validate [<name>]';

  @override
  Future<int> run() async {
    if (argResults!.rest.length > 1) {
      throw UsageException('Expected at most one template name.', usage);
    }

    if (argResults!.rest.length == 1) {
      final requested = argResults!.rest.single;
      final template = await store.find(requested);
      if (template == null) {
        logger.err('No template named "$requested".');
        return ExitCode.config.code;
      }
      logger.success('${template.name}: valid (${template.path})');
      return ExitCode.success.code;
    }

    // list() parses and validates every TEMPLATE.md; a bad one throws.
    final templates = await store.list();
    if (templates.isEmpty) {
      logger.info('No templates to validate.');
      return ExitCode.success.code;
    }
    for (final template in templates) {
      logger.success('${template.name}: valid (${template.path})');
    }
    return ExitCode.success.code;
  }
}

class _MatchTemplate extends _TemplateSubcommand {
  _MatchTemplate({required super.logger, required super.roots}) {
    argParser.addFlag('json', negatable: false, help: 'Emit JSON.');
  }

  @override
  String get description =>
      'Resolve the best template for an artifact kind or request.';

  @override
  String get name => 'match';

  @override
  String get invocation => 'alfredo template match <kind-or-request>';

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      throw UsageException('Expected an artifact kind or request.', usage);
    }
    final query = argResults!.rest.join(' ');
    final match = await store.match(query);
    final asJson = argResults!['json'] as bool;

    if (match == null) {
      if (asJson) {
        logger.info(_prettyJson.convert({'match': null, 'query': query}));
      } else {
        logger.info('No template matches "$query".');
      }
      return ExitCode.success.code;
    }

    final template = match.template;
    if (asJson) {
      logger.info(
        _prettyJson.convert({
          'query': query,
          'reason': match.reason,
          'name': template.name,
          'kind': template.kind,
          'description': template.description,
          'path': template.path,
          'format_target': template.formatTarget,
          'theme': template.themePath,
        }),
      );
      return ExitCode.success.code;
    }
    logger.info(
      '${template.name} (${match.reason})\n'
      'path: ${template.path}\n'
      '${template.description}',
    );
    return ExitCode.success.code;
  }
}
