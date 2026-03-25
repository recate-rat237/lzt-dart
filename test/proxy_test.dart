import 'package:lzt_api/lzt_api.dart';

void main() async {
  final forum = ForumClient(
    token: 'token',
    proxy: 'socks5://user:pass@host:port', // любой прокси
  );

  try {
    final result = await forum.usersGet(userId: 'me');
    print('OK: $result');
  } on LztRateLimitError catch (e) {
    print('Rate limited: retry after ${e.retryAfter}s');
  } on LztAuthError {
    print('Invalid token');
  } on LztNetworkError catch (e) {
    print('Network error (proxy dead?): ${e.message}');
  } finally {
    forum.close();
  }
}