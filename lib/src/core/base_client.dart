import 'http_client.dart';

/// Base class for [ForumClient] and [MarketClient].
///
/// Provides shared HTTP request helpers and lifecycle management.
abstract class BaseClient {
  final LztHttpClient _http;

  BaseClient({
    required String token,
    String? proxy,
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 1),
  }) : _http = LztHttpClient(
          token: token,
          proxy: proxy,
          maxRetries: maxRetries,
          retryDelay: retryDelay,
        );

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? params}) {
    final uri = buildUri(path, params);
    return _http.request('GET', uri);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? body,
  }) {
    final uri = buildUri(path, params);
    return _http.request('POST', uri, body: body);
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? body,
  }) {
    final uri = buildUri(path, params);
    return _http.request('PUT', uri, body: body);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? body,
  }) {
    final uri = buildUri(path, params);
    return _http.request('PATCH', uri, body: body);
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? body,
  }) {
    final uri = buildUri(path, params);
    return _http.request('DELETE', uri, body: body);
  }

  Uri buildUri(String path, Map<String, String>? params);

  /// Send a multipart/form-data request.
  ///
  /// [fields] can contain regular values (String, int, bool) and
  /// binary fields (List<int>) which are sent as file parts.
  Future<Map<String, dynamic>> multipart(
    String method,
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? fields,
  }) {
    final uri = buildUri(path, params);
    return _http.multipartRequest(method, uri, fields: fields);
  }

  /// Release underlying HTTP resources.
  void close() => _http.close();
}