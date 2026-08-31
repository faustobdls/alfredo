import 'dart:io';

import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:alfredo_cli/src/package/package.dart';
import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

/// Package identifier that teaches an agent how to use Alfredo memory.
const memoryPackageId = 'memory-core';

final _sincePattern = RegExp(r'^(\d+)([dwm])$');

/// Records and recalls append-only project and user memory.
class MemoryCommand extends Command<int> {
  /// Creates the memory command group.
  MemoryCommand({
    required MemoryRoots roots,
    required Logger logger,
    required PackageResolver resolver,
    required PackageInstaller installer,
    required AgentTargetRoots targetRoots,
    EmbeddingsClient Function(MemoryConfig config)? embeddingsFactory,
  }) {
    final embeddings = embeddingsFactory ?? OllamaEmbeddingsClient.fromConfig;
    addSubcommand(
      _SetupMemory(
        roots: roots,
        logger: logger,
        embeddingsFactory: embeddings,
        resolver: resolver,
        installer: installer,
        targetRoots: targetRoots,
      ),
    );
    addSubcommand(
      _AddMemory(roots: roots, logger: logger, embeddingsFactory: embeddings),
    );
    addSubcommand(
      _SearchMemory(
        roots: roots,
        logger: logger,
        embeddingsFactory: embeddings,
      ),
    );
    addSubcommand(
      _ListMemory(roots: roots, logger: logger, embeddingsFactory: embeddings),
    );
    addSubcommand(
      _DigestMemory(
        roots: roots,
        logger: logger,
        embeddingsFactory: embeddings,
      ),
    );
    addSubcommand(
      _IndexMemory(roots: roots, logger: logger, embeddingsFactory: embeddings),
    );
    addSubcommand(
      _CaptureMemory(
        roots: roots,
        logger: logger,
        embeddingsFactory: embeddings,
        targetRoots: targetRoots,
      ),
    );
  }

  @override
  String get description => 'Record and recall project and user memory.';

  @override
  String get name => 'memory';
}

abstract class _MemorySubcommand extends Command<int> {
  _MemorySubcommand({
    required this.roots,
    required this.logger,
    required this.embeddingsFactory,
  });

  final MemoryRoots roots;
  final Logger logger;
  final EmbeddingsClient Function(MemoryConfig config) embeddingsFactory;

  void addScopeOption({String? defaultsTo, bool includeAll = false}) {
    argParser.addOption(
      'scope',
      defaultsTo: defaultsTo,
      allowed: [
        'user',
        'project',
        if (includeAll) 'all',
      ],
      help: 'Memory store to use.',
    );
  }

  MemoryStore storeFor(MemoryScope scope) => MemoryStore(
    directory: switch (scope) {
      MemoryScope.user => roots.userDirectory,
      MemoryScope.project => roots.projectDirectory,
    },
  );

  /// Returns the requested scope, or [fallback] when `--scope` is absent.
  MemoryScope scopeOption({required MemoryScope fallback}) =>
      switch (argResults!['scope'] as String?) {
        'user' => MemoryScope.user,
        'project' => MemoryScope.project,
        _ => fallback,
      };

  /// Returns every scope selected by `--scope`, honouring `all`.
  List<MemoryScope> selectedScopes() =>
      switch (argResults!['scope'] as String?) {
        'user' => const [MemoryScope.user],
        'project' => const [MemoryScope.project],
        _ => const [MemoryScope.user, MemoryScope.project],
      };

  /// Returns the default scope persisted by `alfredo memory setup`.
  Future<MemoryScope> configuredScope() async =>
      (await storeFor(MemoryScope.user).readConfig()).defaultScope;

  String requireMessage() {
    final message = argResults!.rest.join(' ').trim();
    if (message.isEmpty) {
      throw UsageException('Expected a memory message.', usage);
    }
    return message;
  }

  DateTime? sinceOption(DateTime now) {
    final value = (argResults!['since'] as String?)?.trim();
    if (value == null || value.isEmpty) return null;
    final match = _sincePattern.firstMatch(value);
    if (match == null) {
      throw UsageException(
        'Invalid --since value: $value. Use 7d, 2w, or 3m.',
        usage,
      );
    }
    final amount = int.parse(match[1]!);
    final days = switch (match[2]) {
      'w' => amount * 7,
      'm' => amount * 30,
      _ => amount,
    };
    return DateTime(now.year, now.month, now.day).subtract(
      Duration(days: days),
    );
  }

  int intOption(String name) {
    final value = argResults![name] as String?;
    final parsed = value == null ? null : int.tryParse(value);
    if (value != null && parsed == null) {
      throw UsageException('Invalid --$name value: $value', usage);
    }
    return parsed ?? 0;
  }
}

class _SetupMemory extends _MemorySubcommand {
  _SetupMemory({
    required super.roots,
    required super.logger,
    required super.embeddingsFactory,
    required this.resolver,
    required this.installer,
    required this.targetRoots,
  }) {
    addScopeOption(defaultsTo: 'user');
    argParser
      ..addFlag(
        'all',
        negatable: false,
        help: 'Accept every recommended default without prompting.',
      )
      ..addFlag(
        'hook',
        defaultsTo: true,
        help: 'Install the end-of-session capture hook.',
      )
      ..addOption(
        'source',
        help: 'Registered source that must provide $memoryPackageId.',
        valueHelp: 'name',
      )
      ..addMultiOption(
        'target',
        allowed: CaptureConfig.supportedTargets,
        help: 'Agent targets that receive the memory package.',
      );
  }

  final PackageResolver resolver;
  final PackageInstaller installer;
  final AgentTargetRoots targetRoots;

  @override
  String get description =>
      'Prepare a memory store and install $memoryPackageId.';

  @override
  String get name => 'setup';

  @override
  Future<int> run() async {
    final unattended = argResults!['all'] == true;
    final scope = scopeOption(fallback: MemoryScope.user);
    final store = storeFor(scope);
    await store.ensureSkeleton();

    final hook = argResults!.wasParsed('hook')
        ? argResults!['hook'] as bool
        : unattended ||
              logger.confirm(
                'Enable end-of-session capture hook?',
                defaultValue: true,
              );
    final embeddings = await _resolveEmbeddings(unattended: unattended);
    final requested = argResults!['target'] as List<String>;
    final targets = requested.isNotEmpty
        ? requested
        : unattended
        ? const ['claude-code']
        : logger.chooseAny(
            'Which agents should receive $memoryPackageId?',
            choices: CaptureConfig.supportedTargets,
            defaultValues: const ['claude-code'],
          );
    final defaultScope = unattended
        ? scope
        : logger.chooseOne(
            'Which store should commands use by default?',
            choices: MemoryScope.values,
            defaultValue: scope,
            display: (value) => value.name,
          );

    await store.writeConfig(
      MemoryConfig(
        embeddings: embeddings,
        capture: CaptureConfig(
          sessionEndHook: hook,
          targets: List.unmodifiable(targets),
        ),
        defaultScope: defaultScope,
      ),
    );

    await _install(targets, scope);
    if (hook) {
      final settings = File(
        p.join(
          switch (scope) {
            MemoryScope.user => targetRoots.userRoot.path,
            MemoryScope.project => targetRoots.projectRoot.path,
          },
          '.claude',
          'settings.json',
        ),
      );
      final written = await const HookWriter().ensureStopHook(
        settings,
        'alfredo memory capture --scope ${scope.name}',
      );
      logger.info(
        written
            ? 'Registered the capture hook in ${settings.path}.'
            : 'Capture hook already present in ${settings.path}.',
      );
    }
    final recall = embeddings.enabled ? embeddings.model : 'keyword only';
    logger.success(
      'Memory ready at ${store.directory.path} (embeddings: $recall).',
    );
    return ExitCode.success.code;
  }

  Future<EmbeddingsConfig> _resolveEmbeddings({
    required bool unattended,
  }) async {
    const disabled = EmbeddingsConfig();
    final client = embeddingsFactory(const MemoryConfig.defaults());
    if (!await client.probe()) {
      logger.info(
        'Ollama not reachable at ${EmbeddingsConfig.defaultBaseUrl}; '
        'memory will use keyword search.',
      );
      return disabled;
    }
    var available = false;
    try {
      available = _modelInstalled(await client.listModels(), client.model);
    } on Exception {
      return disabled;
    }
    if (!available) {
      if (unattended) {
        logger.info(
          'Embedding model ${client.model} is not installed; '
          'memory will use keyword search.',
        );
        return disabled;
      }
      final download = logger.confirm(
        'Download embedding model "${client.model}" (~274 MB) now?',
      );
      if (!download) return disabled;
      try {
        await client.pull(client.model, onProgress: logger.detail);
      } on Exception catch (error) {
        logger.info('Could not download ${client.model}: $error');
        return disabled;
      }
    }
    try {
      final probe = await client.embed(['alfredo']);
      return EmbeddingsConfig(
        enabled: true,
        model: client.model,
        dimensions: probe.isEmpty ? null : probe.first.length,
      );
    } on Exception {
      logger.info(
        'Embedding provider rejected a probe request; '
        'memory will use keyword search.',
      );
      return disabled;
    }
  }

  /// Whether [requested] is already present in [installed].
  ///
  /// Ollama reports models with an explicit tag (`nomic-embed-text:latest`),
  /// while the configured model name is usually tagless. Treat a missing tag as
  /// the implicit `latest` on both sides before comparing.
  static bool _modelInstalled(Iterable<String> installed, String requested) {
    String withTag(String name) => name.contains(':') ? name : '$name:latest';
    final target = withTag(requested);
    return installed.map(withTag).contains(target);
  }

  Future<void> _install(List<String> targets, MemoryScope scope) async {
    if (targets.isEmpty) return;
    final source = (argResults!['source'] as String?)?.trim();
    if (source != null && source.isNotEmpty) {
      final candidates = await resolver.catalog.discover();
      final available = candidates.any(
        (candidate) =>
            candidate.manifest.id == memoryPackageId &&
            candidate.sourceName == source,
      );
      if (!available) {
        throw MemoryException(
          'Source $source does not provide $memoryPackageId. '
          'Register it: alfredo source add $source --local <path>',
        );
      }
    }
    for (final target in targets) {
      final PackageResolution resolution;
      try {
        resolution = await resolver.resolve(
          packageIds: const [memoryPackageId],
          target: target,
        );
      } on PackageException catch (error) {
        throw MemoryException(
          '${error.message} Register a source that provides '
          '$memoryPackageId: alfredo source add <name> --local <path>',
        );
      }
      await installer.install(
        resolution: resolution,
        roots: targetRoots,
        scope: switch (scope) {
          MemoryScope.user => InstallationScope.user,
          MemoryScope.project => InstallationScope.project,
        },
      );
      logger.info('Installed $memoryPackageId for $target (${scope.name}).');
    }
  }
}

class _AddMemory extends _MemorySubcommand {
  _AddMemory({
    required super.roots,
    required super.logger,
    required super.embeddingsFactory,
  }) {
    addScopeOption();
    argParser
      ..addOption(
        'kind',
        defaultsTo: 'activity',
        allowed: const ['note', 'activity'],
        help: 'Durable note or time-bound activity entry.',
      )
      ..addOption(
        'title',
        help: 'Note title; required when --kind is note.',
        valueHelp: 'text',
      )
      ..addMultiOption(
        'tag',
        abbr: 't',
        help: 'Classification tag; repeatable.',
        valueHelp: 'tag',
      );
  }

  @override
  String get description => 'Record one memory entry.';

  @override
  String get name => 'add';

  @override
  Future<int> run() async {
    final message = requireMessage();
    final scope = scopeOption(fallback: await configuredScope());
    final store = storeFor(scope);
    await store.ensureSkeleton();
    final tags = argResults!['tag'] as List<String>;

    if (argResults!['kind'] == 'note') {
      final title = (argResults!['title'] as String?)?.trim();
      if (title == null || title.isEmpty) {
        throw UsageException('--title is required for --kind note.', usage);
      }
      final note = await store.writeNote(
        title: title,
        body: message,
        tags: tags,
      );
      logger.success(
        'Wrote ${p.join(store.notesDirectory.path, '${note.slug}.md')}.',
      );
      return ExitCode.success.code;
    }

    final entry = await store.appendActivity(message: message, tags: tags);
    logger.success('Appended to ${store.journalFileFor(entry.at).path}.');
    return ExitCode.success.code;
  }
}

class _SearchMemory extends _MemorySubcommand {
  _SearchMemory({
    required super.roots,
    required super.logger,
    required super.embeddingsFactory,
  }) {
    addScopeOption(defaultsTo: 'all', includeAll: true);
    argParser
      ..addOption('limit', defaultsTo: '8', help: 'Maximum number of hits.')
      ..addFlag(
        'keyword',
        negatable: false,
        help: 'Skip embeddings and rank by term counts only.',
      );
  }

  @override
  String get description => 'Rank memory documents against a query.';

  @override
  String get name => 'search';

  @override
  Future<int> run() async {
    final query = requireMessage();
    final limit = intOption('limit');
    final keywordOnly = argResults!['keyword'] == true;
    final hits = <MemorySearchHit>[];
    for (final scope in selectedScopes()) {
      final store = storeFor(scope);
      if (!store.directory.existsSync()) continue;
      final config = await store.readConfig();
      final client = !keywordOnly && config.embeddings.enabled
          ? embeddingsFactory(config)
          : null;
      final scoped = await store.search(
        query,
        limit: limit,
        keywordOnly: keywordOnly,
        embeddings: client,
      );
      hits.addAll(scoped.map((hit) => hit.withScopeLabel(scope.name)));
    }
    hits.sort((left, right) {
      final score = right.score.compareTo(left.score);
      return score == 0 ? left.path.compareTo(right.path) : score;
    });
    if (hits.isEmpty) {
      logger.info('No matches.');
      return ExitCode.success.code;
    }
    for (final hit in hits.take(limit.clamp(1, 20))) {
      logger.info(
        '${hit.score.toStringAsFixed(3)}\t${hit.scopeLabel}\t${hit.path}\t'
        '${hit.title}\t${hit.excerpt}',
      );
    }
    return ExitCode.success.code;
  }
}

class _ListMemory extends _MemorySubcommand {
  _ListMemory({
    required super.roots,
    required super.logger,
    required super.embeddingsFactory,
  }) {
    addScopeOption(defaultsTo: 'all', includeAll: true);
    argParser
      ..addOption(
        'since',
        defaultsTo: '7d',
        help: 'Relative window such as 7d, 2w, or 3m.',
      )
      ..addOption('limit', help: 'Maximum number of entries.');
  }

  @override
  String get description => 'List recent journal entries, newest first.';

  @override
  String get name => 'list';

  @override
  Future<int> run() async {
    final since = sinceOption(DateTime.now());
    final limit = intOption('limit');
    final entries = <MemoryEntry>[];
    for (final scope in selectedScopes()) {
      final store = storeFor(scope);
      if (!store.directory.existsSync()) continue;
      for (final entry in await store.listActivities(since: since)) {
        entries.add(
          MemoryEntry(
            at: entry.at,
            kind: entry.kind,
            tags: entry.tags,
            message: entry.message,
            scopeLabel: scope.name,
          ),
        );
      }
    }
    entries.sort((left, right) => right.at.compareTo(left.at));
    if (entries.isEmpty) {
      logger.info('No entries.');
      return ExitCode.success.code;
    }
    final visible = limit > 0 ? entries.take(limit) : entries;
    for (final entry in visible) {
      logger.info(
        '${_timestamp(entry.at)}\t${entry.scopeLabel}\t${entry.kind.name}\t'
        '[${entry.tags.join(',')}]\t${_singleLine(entry.message)}',
      );
    }
    return ExitCode.success.code;
  }
}

class _DigestMemory extends _MemorySubcommand {
  _DigestMemory({
    required super.roots,
    required super.logger,
    required super.embeddingsFactory,
  }) {
    addScopeOption(defaultsTo: 'all', includeAll: true);
    argParser
      ..addOption(
        'since',
        defaultsTo: '14d',
        help: 'Relative window such as 14d, 2w, or 3m.',
      )
      ..addOption(
        'max-chars',
        defaultsTo: '2000',
        help: 'Truncate the rendered digest at this length.',
      );
  }

  @override
  String get description => 'Summarize recent activity for a task briefing.';

  @override
  String get name => 'digest';

  @override
  Future<int> run() async {
    final since = sinceOption(DateTime.now());
    final maxChars = intOption('max-chars');
    final scopes = selectedScopes();
    var rendered = false;
    for (final scope in scopes) {
      final store = storeFor(scope);
      if (!store.directory.existsSync()) continue;
      final digest = await store.digest(since: since, maxChars: maxChars);
      if (digest.isEmpty) continue;
      rendered = true;
      logger.info(scopes.length > 1 ? '# ${scope.name}\n$digest' : digest);
    }
    if (!rendered) logger.info('No entries.');
    return ExitCode.success.code;
  }
}

class _IndexMemory extends _MemorySubcommand {
  _IndexMemory({
    required super.roots,
    required super.logger,
    required super.embeddingsFactory,
  }) {
    addScopeOption(defaultsTo: 'all', includeAll: true);
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Re-embed every document instead of only changed ones.',
    );
  }

  @override
  String get description => 'Rebuild the embedding index for a memory store.';

  @override
  String get name => 'index';

  @override
  Future<int> run() async {
    final force = argResults!['force'] == true;
    for (final scope in selectedScopes()) {
      final store = storeFor(scope);
      if (!store.directory.existsSync()) continue;
      final config = await store.readConfig();
      if (!config.embeddings.enabled) {
        throw const MemoryException(
          'Embeddings are disabled. Run: alfredo memory setup',
        );
      }
      final client = embeddingsFactory(config);
      if (!await client.probe()) {
        throw MemoryException(
          'Ollama not reachable at ${config.embeddings.baseUrl}.',
        );
      }
      final report = await store.updateIndex(client, force: force);
      logger.success(
        '${scope.name}: embedded ${report.embedded}, reused ${report.reused}, '
        'pruned ${report.pruned}.',
      );
    }
    return ExitCode.success.code;
  }
}

class _CaptureMemory extends _MemorySubcommand {
  _CaptureMemory({
    required super.roots,
    required super.logger,
    required super.embeddingsFactory,
    required this.targetRoots,
  }) {
    addScopeOption();
  }

  final AgentTargetRoots targetRoots;

  @override
  String get description => 'Record the end of a working session.';

  @override
  String get name => 'capture';

  @override
  Future<int> run() async {
    final scope = scopeOption(fallback: await configuredScope());
    final store = storeFor(scope);
    await store.ensureSkeleton();
    final config = await store.readConfig();

    await store.appendActivity(
      message: 'session ended',
      tags: const [
        'session',
      ],
    );
    if (config.capture.gitDiffStat) {
      final diff = await _gitDiffStat();
      if (diff != null) {
        await store.appendActivity(
          message: 'session diff\n\n$diff',
          tags: const ['session', 'diff'],
        );
      }
    }
    await store.appendActivity(
      message: 'TODO: summarize what was done this session',
      tags: const ['todo'],
    );
    logger.success('Captured session memory in ${store.directory.path}.');
    return ExitCode.success.code;
  }

  Future<String?> _gitDiffStat() async {
    try {
      final result = await Process.run(
        'git',
        const ['diff', '--stat'],
        workingDirectory: targetRoots.projectRoot.path,
      );
      if (result.exitCode != 0) return null;
      final lines = '${result.stdout}'
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .take(20)
          .toList();
      return lines.isEmpty ? null : lines.join('\n');
    } on Exception {
      return null;
    }
  }
}

String _timestamp(DateTime moment) =>
    '${moment.year.toString().padLeft(4, '0')}-'
    '${moment.month.toString().padLeft(2, '0')}-'
    '${moment.day.toString().padLeft(2, '0')} '
    '${moment.hour.toString().padLeft(2, '0')}:'
    '${moment.minute.toString().padLeft(2, '0')}';

String _singleLine(String value) =>
    value.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).join(' ');
