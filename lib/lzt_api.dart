/// Dart API wrapper for Lolzteam Forum & Market.
///
/// Auto-generated from OpenAPI schemas. Supports async, proxy, and
/// automatic retry on 429/502/503.
///
/// ## Quick start
///
/// ```dart
/// import 'package:lzt_api/lzt_api.dart';
///
/// void main() async {
///   final forum = ForumClient(token: 'your_token');
///   final threads = await forum.threadsList();
///   print(threads);
///   forum.close();
///
///   final market = MarketClient(token: 'your_token');
///   final accounts = await market.categoryList();
///   print(accounts);
///   market.close();
/// }
/// ```
///
/// ## Proxy
///
/// ```dart
/// final client = ForumClient(
///   token: 'your_token',
///   proxy: 'http://user:pass@proxy.host:8080',
/// );
/// ```
///
/// ## Error handling
///
/// ```dart
/// try {
///   final result = await forum.threadsGet(threadId: 123);
/// } on LztRateLimitError catch (e) {
///   print('Rate limited, retry after ${e.retryAfter}s');
/// } on LztAuthError {
///   print('Invalid token');
/// } on LztNotFoundError {
///   print('Thread not found');
/// }
/// ```
library lzt_api;

export 'src/forum/forum_client.dart';
export 'src/market/market_client.dart';
export 'src/core/exceptions.dart';
