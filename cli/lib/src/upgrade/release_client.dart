import 'dart:io';
import 'dart:typed_data';

/// An upgrade error that can be displayed directly by a CLI adapter.
class UpgradeException implements Exception {
  /// Creates an actionable upgrade operation error.
  const UpgradeException(this.message);

  /// User-facing failure description.
  final String message;

  @override
  String toString() => message;
}

/// Resolves the latest published CLI release and downloads its assets.
abstract class ReleaseClient {
  /// Latest published version as a bare `X.Y.Z` string.
  Future<String> latestVersion();

  /// Base URL that release assets are downloaded from.
  Uri assetBaseUrl();

  /// Downloads [url] and returns its raw bytes.
  Future<Uint8List> download(Uri url);
}

/// A [ReleaseClient] backed by GitHub Releases for `faustobdls/alfredo`.
///
/// The latest version is resolved from the `releases/latest` redirect target
/// rather than the REST API to avoid unauthenticated rate limits.
class GithubReleaseClient implements ReleaseClient {
  /// Creates a GitHub release client.
  GithubReleaseClient({
    Map<String, String>? environment,
    HttpClient Function()? httpClientFactory,
  }) : _environment = environment ?? Platform.environment,
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final Map<String, String> _environment;
  final HttpClient Function() _httpClientFactory;

  String get _repository {
    final value = _environment['ALFREDO_GITHUB_REPOSITORY']?.trim();
    return value == null || value.isEmpty ? 'faustobdls/alfredo' : value;
  }

  @override
  Uri assetBaseUrl() {
    final value = _environment['ALFREDO_DOWNLOAD_BASE_URL']?.trim();
    if (value != null && value.isNotEmpty) {
      return Uri.parse(value.endsWith('/') ? value : '$value/');
    }
    return Uri.parse(
      'https://github.com/$_repository/releases/latest/download/',
    );
  }

  @override
  Future<String> latestVersion() async {
    final override = _environment['ALFREDO_LATEST_VERSION']?.trim();
    if (override != null && override.isNotEmpty) {
      return _stripLeadingV(override);
    }
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(
        Uri.parse('https://github.com/$_repository/releases/latest'),
      );
      request.followRedirects = false;
      final response = await request.close();
      await response.drain<void>();
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (response.statusCode < 300 ||
          response.statusCode >= 400 ||
          location == null) {
        throw UpgradeException(
          'Cannot resolve the latest release: HTTP ${response.statusCode}.',
        );
      }
      final tag = location.split('/').last;
      if (tag.isEmpty) {
        throw const UpgradeException(
          'Cannot resolve the latest release: empty tag.',
        );
      }
      return _stripLeadingV(tag);
    } on SocketException catch (error) {
      throw UpgradeException('Cannot reach GitHub: ${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<Uint8List> download(Uri url) async {
    if (url.scheme == 'file') {
      final file = File.fromUri(url);
      if (!file.existsSync()) {
        throw UpgradeException('Release asset does not exist: ${file.path}');
      }
      return file.readAsBytes();
    }
    if (url.scheme != 'http' && url.scheme != 'https') {
      throw UpgradeException('Unsupported release URL scheme: ${url.scheme}');
    }
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(url)
        ..followRedirects = true
        ..maxRedirects = 5;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw UpgradeException(
          'Cannot download release asset: HTTP ${response.statusCode}',
        );
      }
      final bytes = await response.fold<List<int>>(<int>[], (value, chunk) {
        value.addAll(chunk);
        return value;
      });
      return Uint8List.fromList(bytes);
    } on SocketException catch (error) {
      throw UpgradeException('Cannot download release asset: ${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  static String _stripLeadingV(String value) {
    final trimmed = value.trim();
    return trimmed.startsWith('v') ? trimmed.substring(1) : trimmed;
  }
}
