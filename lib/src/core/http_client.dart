import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:socks5_proxy/socks_client.dart';
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
    if (proxy == null) return http.Client();

    final proxyUri = Uri.parse(proxy!);
    final scheme = proxyUri.scheme.toLowerCase();
    final host = proxyUri.host.isEmpty ? 'localhost' : proxyUri.host;
    final port = proxyUri.hasPort ? proxyUri.port : 1080;

    String? user;
    String? pass;
    if (proxyUri.userInfo.isNotEmpty) {
      final parts = proxyUri.userInfo.split(':');
      user = parts[0];
      pass = parts.length > 1 ? parts[1] : null;
    }

    if (scheme == 'socks5' || scheme == 'socks4') {
      // SOCKS4/SOCKS5 via socks5_proxy package
      final ioClient = HttpClient();
      SocksTCPClient.assignToHttpClient(ioClient, [
        ProxySettings(
          InternetAddress(host, type: InternetAddressType.any),
          port,
          username: user,
          password: pass,
        ),
      ]);
      return IOClient(ioClient);
    }

    // HTTP/HTTPS proxy via dart:io native support
    final defaultPort = (scheme == 'https') ? 443 : 8080;
    final effectivePort = proxyUri.hasPort ? port : defaultPort;
    final ioClient = HttpClient()
      ..findProxy = (_) => 'PROXY $host:$effectivePort';

    if (user != null) {
      ioClient.addProxyCredentials(
        host,
        effectivePort,
        'Basic',
        HttpClientBasicCredentials(user, pass ?? ''),
      );
    }

    return IOClient(ioClient);
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
        _throwNetworkError(e, url);
        rethrow;
      } on HttpException catch (e) {
        throw LztNetworkError('HTTP error: ${e.message}');
      } on HandshakeException catch (e) {
        throw LztNetworkError('TLS handshake failed: ${e.message}');
      } on TimeoutException {
        throw LztTimeoutError('Request timed out: $url');
      } on LztApiError {
        rethrow;
      } catch (e) {
        throw LztNetworkError('Unexpected error: $e');
      }

      if (_retryStatuses.contains(response.statusCode) && attempt <= maxRetries) {
        final delay = _resolveDelay(response, attempt);
        await Future.delayed(delay);
        continue;
      }

      return _handleResponse(response);
    }
  }

  /// Maps [SocketException] to a specific [LztApiError] subtype.
  Never _throwNetworkError(SocketException e, Uri url) {
    final msg = e.message.toLowerCase();
    final osError = e.osError?.message.toLowerCase() ?? '';
    final combined = '$msg $osError';

    if (combined.contains('connection refused') ||
        combined.contains('connection denied') ||
        combined.contains('no route to host')) {
      throw LztProxyError('Proxy connection failed (${url.host}): ${e.message}');
    }

    if (combined.contains('failed host lookup') ||
        combined.contains('name or service not known') ||
        combined.contains('no address associated')) {
      throw LztNetworkError('DNS lookup failed for ${url.host}: ${e.message}');
    }

    throw LztNetworkError('Network error: ${e.message}');
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
    final rawBody = response.body.isEmpty ? '{}' : response.body;

    if (response.statusCode == 407) {
      throw const LztProxyAuthRequiredError(
        'Proxy authentication required — check proxy credentials',
      );
    }

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        data = decoded;
      } else {
        data = {'_raw': decoded};
      }
    } on FormatException catch (e) {
      throw LztParseError(
        'Failed to parse response JSON: ${e.message}',
        rawBody: rawBody,
      );
    }

    switch (response.statusCode) {
      case 200:
      case 201:
      case 204:
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
        throw LztApiError('Unexpected status ${response.statusCode}: $rawBody');
    }
  }

  /// Send a multipart/form-data request.
  /// Fields with List<int> values are sent as binary file parts,
  /// everything else is sent as form fields.
  Future<Map<String, dynamic>> multipartRequest(
    String method,
    Uri url, {
    Map<String, dynamic>? fields,
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      http.Response response;
      try {
        final request = http.MultipartRequest(method, url)
          ..headers.addAll(_headers..remove('Content-Type'));

        if (fields != null) {
          for (final entry in fields.entries) {
            final value = entry.value;
            if (value == null) continue;
            if (value is List<int>) {
              request.files.add(http.MultipartFile.fromBytes(
                entry.key,
                value,
                filename: entry.key,
              ));
            } else {
              request.fields[entry.key] = value.toString();
            }
          }
        }

        response = await _inner.send(request).then(http.Response.fromStream);
      } on SocketException catch (e) {
        _throwNetworkError(e, url);
        rethrow;
      } on HttpException catch (e) {
        throw LztNetworkError('HTTP error: ${e.message}');
      } on TimeoutException {
        throw LztTimeoutError('Request timed out: $url');
      } on LztApiError {
        rethrow;
      } catch (e) {
        throw LztNetworkError('Unexpected error: $e');
      }

      if (_retryStatuses.contains(response.statusCode) && attempt <= maxRetries) {
        final delay = _resolveDelay(response, attempt);
        await Future.delayed(delay);
        continue;
      }

      return _handleResponse(response);
    }
  }

  void close() => _inner.close();
}