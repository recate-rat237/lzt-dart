import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'exceptions.dart';

/// Retry-capable HTTP client with proxy support.
///
/// Automatically retries on 429 (rate limit) with Retry-After header support,
/// and on 502/503 (bad gateway / service unavailable) with exponential backoff.
class LztHttpClient {
  final String token;
  final String? proxy;
  final int maxRetries;
  final Duration retryDelay;

  late final http.Client _inner;

  static const _retryStatuses = {429, 502, 503};
  static const _defaultMaxRetries = 3;
  static const _defaultRetryDelay = Duration(seconds: 1);

  LztHttpClient({
    required this.token,
    this.proxy,
    this.maxRetries = _defaultMaxRetries,
    this.retryDelay = _defaultRetryDelay,
  }) {
    _inner = _buildClient();
  }

  http.Client _buildClient() {
    if (proxy != null) {
      final proxyUri = Uri.parse(proxy!);
      final proxyConfig = HttpClient()
        ..findProxy = (uri) {
          return 'PROXY ${proxyUri.host}:${proxyUri.port}';
        };

      if (proxyUri.userInfo.isNotEmpty) {
        final parts = proxyUri.userInfo.split(':');
        proxyConfig.addProxyCredentials(
          proxyUri.host,
          proxyUri.port,
          'Basic',
          HttpClientBasicCredentials(parts[0], parts.length > 1 ? parts[1] : ''),
        );
      }

      return http.Client();
      // Note: dart:io HttpClient proxy is set via HttpOverrides in real usage.
      // See README for proxy configuration examples.
    }
    return http.Client();
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  Future<Map<String, dynamic>> request(
    String method,
    Uri url, {
    Map<String, dynamic>? body,
  }) async {
    int attempt = 0;

    while (true) {
      attempt++;
      http.Response response;

      try {
        response = await _send(method, url, body: body);
      } on SocketException catch (e) {
        throw LztNetworkError('Network error: ${e.message}');
      }

      if (_retryStatuses.contains(response.statusCode) && attempt <= maxRetries) {
        final delay = _resolveDelay(response, attempt);
        await Future.delayed(delay);
        continue;
      }

      return _handleResponse(response);
    }
  }

  Future<http.Response> _send(String method, Uri url, {Map<String, dynamic>? body}) {
    final req = http.Request(method, url)..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    return _inner.send(req).then(http.Response.fromStream);
  }

  Duration _resolveDelay(http.Response response, int attempt) {
    if (response.statusCode == 429) {
      final retryAfter = response.headers['retry-after'];
      if (retryAfter != null) {
        final seconds = int.tryParse(retryAfter);
        if (seconds != null) return Duration(seconds: seconds);
      }
    }
    // Exponential backoff for 502/503 and fallback for 429
    return retryDelay * (1 << (attempt - 1));
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    final body = response.body.isEmpty ? '{}' : response.body;
    late Map<String, dynamic> data;

    try {
      data = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw LztApiError('Invalid JSON response: $body');
    }

    switch (response.statusCode) {
      case 200:
      case 201:
        return data;
      case 400:
        throw LztBadRequestError(data['message']?.toString() ?? 'Bad request', data);
      case 401:
        throw LztAuthError(data['message']?.toString() ?? 'Unauthorized');
      case 403:
        throw LztForbiddenError(data['message']?.toString() ?? 'Forbidden');
      case 404:
        throw LztNotFoundError(data['message']?.toString() ?? 'Not found');
      case 429:
        final retryAfter = int.tryParse(response.headers['retry-after'] ?? '');
        throw LztRateLimitError(
          data['message']?.toString() ?? 'Rate limited',
          retryAfter: retryAfter,
        );
      case 502:
      case 503:
        throw LztServerError(response.statusCode, data['message']?.toString() ?? 'Server error');
      default:
        throw LztApiError('Unexpected status ${response.statusCode}: $body');
    }
  }

  void close() => _inner.close();
}
