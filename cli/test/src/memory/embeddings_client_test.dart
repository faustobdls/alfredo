import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alfredo_cli/src/memory/memory.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late List<String> requestedPaths;
  late List<String> requestBodies;
  late Future<void> Function(HttpRequest request) handler;

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server.forEach((request) async {
        requestedPaths.add(request.uri.path);
        requestBodies.add(await utf8.decodeStream(request));
        try {
          await handler(request);
        } on Exception {
          // The client may have already closed the connection.
        }
      }),
    );
  }

  OllamaEmbeddingsClient clientFor({
    Duration probeTimeout = const Duration(seconds: 3),
  }) => OllamaEmbeddingsClient(
    baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
    probeTimeout: probeTimeout,
    requestTimeout: const Duration(seconds: 5),
  );

  void respond(HttpRequest request, int status, Object? body) {
    request.response.statusCode = status;
    if (body != null) request.response.write(jsonEncode(body));
  }

  setUp(() async {
    requestedPaths = [];
    requestBodies = [];
    handler = (request) async {
      respond(request, 404, null);
      await request.response.close();
    };
    await start();
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('performs no request until a method is called', () async {
    clientFor();

    expect(requestedPaths, isEmpty);
  });

  test('probes the provider and reports reachability', () async {
    handler = (request) async {
      respond(request, 200, {'models': <Object?>[]});
      await request.response.close();
    };

    expect(await clientFor().probe(), isTrue);
    expect(requestedPaths, ['/api/tags']);
  });

  test('reports an unreachable provider as false', () async {
    handler = (request) async {
      respond(request, 500, null);
      await request.response.close();
    };
    final client = clientFor();
    expect(await client.probe(), isFalse);

    await server.close(force: true);
    expect(await client.probe(), isFalse);
  });

  test('reports a timed-out provider as false', () async {
    handler = (request) async {
      await Future<void>.delayed(const Duration(seconds: 5));
      respond(request, 200, {'models': <Object?>[]});
      await request.response.close();
    };

    expect(
      await clientFor(probeTimeout: const Duration(milliseconds: 50)).probe(),
      isFalse,
    );
  });

  test('parses installed model names', () async {
    handler = (request) async {
      respond(request, 200, {
        'models': [
          {'name': 'nomic-embed-text'},
          {'name': 'llama'},
          {'missing': 'name'},
        ],
      });
      await request.response.close();
    };

    expect(await clientFor().listModels(), [
      'nomic-embed-text',
      'llama',
    ]);
  });

  test('streams progress lines while pulling a model', () async {
    handler = (request) async {
      request.response
        ..statusCode = 200
        ..writeln(jsonEncode({'status': 'pulling manifest'}))
        ..writeln()
        ..writeln('not json')
        ..writeln(jsonEncode({'status': 'success'}));
      await request.response.close();
    };

    final progress = <String>[];
    await clientFor().pull('nomic-embed-text', onProgress: progress.add);

    expect(requestedPaths, ['/api/pull']);
    expect(
      jsonDecode(requestBodies.single),
      {'name': 'nomic-embed-text', 'stream': true},
    );
    expect(progress, ['pulling manifest', 'success']);
  });

  test('surfaces a streamed pull error', () async {
    handler = (request) async {
      request.response
        ..statusCode = 200
        ..writeln(jsonEncode({'error': 'model not found'}));
      await request.response.close();
    };

    await expectLater(
      clientFor().pull('missing'),
      throwsA(isA<MemoryException>()),
    );
  });

  test('embeds a batch and caches the vector length', () async {
    handler = (request) async {
      respond(request, 200, {
        'embeddings': [
          [1.0, 0.0],
          [0.0, 1],
        ],
      });
      await request.response.close();
    };

    final client = clientFor();
    final vectors = await client.embed(['first', 'second']);

    expect(requestedPaths, ['/api/embed']);
    expect(jsonDecode(requestBodies.single), {
      'model': 'nomic-embed-text',
      'input': ['first', 'second'],
    });
    expect(vectors, [
      [1.0, 0.0],
      [0.0, 1.0],
    ]);
    expect(client.dimensions, 2);
  });

  test('falls back to the singular endpoint on 404', () async {
    handler = (request) async {
      if (request.uri.path == '/api/embed') {
        respond(request, 404, null);
      } else {
        respond(request, 200, {
          'embedding': [0.5, 0.5],
        });
      }
      await request.response.close();
    };

    final vectors = await clientFor().embed(['first', 'second']);

    expect(requestedPaths, [
      '/api/embed',
      '/api/embeddings',
      '/api/embeddings',
    ]);
    expect(jsonDecode(requestBodies[1]), {
      'model': 'nomic-embed-text',
      'prompt': 'first',
    });
    expect(vectors, [
      [0.5, 0.5],
      [0.5, 0.5],
    ]);
  });

  test('rejects an unusable embedding response', () async {
    handler = (request) async {
      respond(request, 200, {'embeddings': <Object?>[]});
      await request.response.close();
    };

    await expectLater(
      clientFor().embed(['first']),
      throwsA(isA<MemoryException>()),
    );
  });

  test('returns no vectors for no inputs without a request', () async {
    expect(await clientFor().embed([]), isEmpty);
    expect(requestedPaths, isEmpty);
  });

  test('builds a client from persisted configuration', () {
    final client = OllamaEmbeddingsClient.fromConfig(
      const MemoryConfig(
        embeddings: EmbeddingsConfig(
          enabled: true,
          baseUrl: 'http://127.0.0.1:9999',
          model: 'custom-model',
        ),
        capture: CaptureConfig(),
        defaultScope: MemoryScope.user,
      ),
    );

    expect(client.model, 'custom-model');
    expect(client.baseUri, Uri.parse('http://127.0.0.1:9999'));
    expect(client.dimensions, isNull);
  });
}
