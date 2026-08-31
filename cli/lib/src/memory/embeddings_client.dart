import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/memory/memory_models.dart';

/// A provider that turns memory text into comparable vectors.
abstract class EmbeddingsClient {
  /// Reports whether the provider is reachable, without failing the caller.
  Future<bool> probe();

  /// Lists the model names the provider already has locally.
  Future<List<String>> listModels();

  /// Downloads [model], reporting provider status lines to [onProgress].
  Future<void> pull(String model, {void Function(String status)? onProgress});

  /// Embeds [inputs], returning one vector per input in the same order.
  Future<List<List<double>>> embed(List<String> inputs);

  /// Model used by [embed].
  String get model;

  /// Vector length observed from the last successful [embed], when known.
  int? get dimensions;
}

/// An [EmbeddingsClient] backed by a local Ollama daemon.
///
/// Every request is explicit: constructing the client performs no network
/// call, and a model is only downloaded when [pull] is invoked directly.
class OllamaEmbeddingsClient implements EmbeddingsClient {
  /// Creates a client for a local Ollama daemon.
  OllamaEmbeddingsClient({
    Uri? baseUri,
    this.model = EmbeddingsConfig.defaultModel,
    HttpClient Function()? httpClientFactory,
    this.probeTimeout = const Duration(seconds: 3),
    this.requestTimeout = const Duration(seconds: 30),
  }) : baseUri = baseUri ?? Uri.parse(EmbeddingsConfig.defaultBaseUrl),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// Creates a client from persisted memory configuration.
  factory OllamaEmbeddingsClient.fromConfig(MemoryConfig config) =>
      OllamaEmbeddingsClient(
        baseUri: Uri.parse(config.embeddings.baseUrl),
        model: config.embeddings.model,
      );

  /// Largest number of inputs sent in one batch request.
  static const batchSize = 64;

  /// Provider base URI.
  final Uri baseUri;

  @override
  final String model;

  /// Timeout applied to reachability checks.
  final Duration probeTimeout;

  /// Timeout applied to model and embedding requests.
  final Duration requestTimeout;

  final HttpClient Function() _httpClientFactory;

  int? _dimensions;

  @override
  int? get dimensions => _dimensions;

  @override
  Future<bool> probe() async {
    try {
      final response = await _send('GET', '/api/tags', timeout: probeTimeout);
      return response.statusCode == 200;
    } on Exception {
      return false;
    }
  }

  @override
  Future<List<String>> listModels() async {
    final response = await _send('GET', '/api/tags', timeout: requestTimeout);
    if (response.statusCode != 200) {
      throw MemoryException(
        'Embedding provider returned ${response.statusCode} for /api/tags.',
      );
    }
    final document = _decodeObject(response.body);
    final models = document['models'];
    if (models is! List) return const [];
    return List.unmodifiable(<String>[
      for (final entry in models)
        if (entry is Map && entry['name'] is String) entry['name']! as String,
    ]);
  }

  @override
  Future<void> pull(
    String model, {
    void Function(String status)? onProgress,
  }) async {
    final client = _httpClientFactory();
    try {
      final request = await client.openUrl('POST', _resolve('/api/pull'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'name': model, 'stream': true}));
      final response = await request.close();
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw MemoryException(
          'Cannot download embedding model $model: '
          'provider returned ${response.statusCode}.',
        );
      }
      final lines = response
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final Object? decoded;
        try {
          decoded = jsonDecode(line);
        } on FormatException {
          continue;
        }
        if (decoded is! Map) continue;
        final error = decoded['error'];
        if (error is String) {
          throw MemoryException('Cannot download embedding model: $error');
        }
        final status = decoded['status'];
        if (status is String) onProgress?.call(status);
      }
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<List<List<double>>> embed(List<String> inputs) async {
    if (inputs.isEmpty) return const [];
    final vectors = <List<double>>[];
    for (var start = 0; start < inputs.length; start += batchSize) {
      final batch = inputs.sublist(
        start,
        start + batchSize > inputs.length ? inputs.length : start + batchSize,
      );
      vectors.addAll(await _embedBatch(batch));
    }
    if (vectors.isNotEmpty) _dimensions = vectors.first.length;
    return List.unmodifiable(vectors);
  }

  Future<List<List<double>>> _embedBatch(List<String> batch) async {
    final response = await _send(
      'POST',
      '/api/embed',
      body: {'model': model, 'input': batch},
      timeout: requestTimeout,
    );
    if (response.statusCode == 404 || response.statusCode == 400) {
      return _embedIndividually(batch);
    }
    if (response.statusCode != 200) {
      throw MemoryException(
        'Embedding provider returned ${response.statusCode} for /api/embed.',
      );
    }
    final embeddings = _decodeObject(response.body)['embeddings'];
    if (embeddings is! List || embeddings.length != batch.length) {
      throw const MemoryException('Embedding provider returned no vectors.');
    }
    return [for (final vector in embeddings) _asVector(vector)];
  }

  Future<List<List<double>>> _embedIndividually(List<String> batch) async {
    final vectors = <List<double>>[];
    for (final input in batch) {
      final response = await _send(
        'POST',
        '/api/embeddings',
        body: {'model': model, 'prompt': input},
        timeout: requestTimeout,
      );
      if (response.statusCode != 200) {
        throw MemoryException(
          'Embedding provider returned ${response.statusCode} '
          'for /api/embeddings.',
        );
      }
      vectors.add(_asVector(_decodeObject(response.body)['embedding']));
    }
    return vectors;
  }

  Future<_ProviderResponse> _send(
    String method,
    String path, {
    required Duration timeout,
    Object? body,
  }) async {
    final client = _httpClientFactory()..connectionTimeout = timeout;
    try {
      final request = await client
          .openUrl(method, _resolve(path))
          .timeout(timeout);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      return _ProviderResponse(response.statusCode, text);
    } finally {
      client.close(force: true);
    }
  }

  Uri _resolve(String path) => baseUri.replace(
    path: '${baseUri.path.replaceAll(RegExp(r'/+$'), '')}$path',
  );

  static Map<String, Object?> _decodeObject(String body) {
    final document = jsonDecode(body);
    if (document is! Map) {
      throw const MemoryException(
        'Embedding provider returned an unexpected response.',
      );
    }
    return document.map((key, value) => MapEntry('$key', value));
  }

  static List<double> _asVector(Object? value) {
    if (value is! List) {
      throw const MemoryException('Embedding provider returned no vectors.');
    }
    return List.unmodifiable(<double>[
      for (final item in value)
        if (item is num) item.toDouble() else 0,
    ]);
  }
}

class _ProviderResponse {
  const _ProviderResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}
