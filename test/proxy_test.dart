import 'package:lzt_api/lzt_api.dart';

void main() async {
  final forum = ForumClient(
    token: 'eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzUxMiJ9.eyJzdWIiOjU3MzAyNDgsImlzcyI6Imx6dCIsImlhdCI6MTc3NDQzNzYzOSwianRpIjoiOTUxMzQzIiwic2NvcGUiOiJiYXNpYyByZWFkIiwiZXhwIjoxOTMyMTE3NjM5fQ.Af2bXrtbqn_s4SvJiMV4HNsSPO-Ek0hQ6XnRw92miA-Xqos36oKx-I2mvunz5sIT2DmaZ14_orm6oVDXgn-H39O-z8lHsTLzwkL8gJ9C3uSNadyK5xrHbH1ia5bfX9xcTy9G3kLDvD128RrgP2SGxsFbssOLp09znp7btpkwHLA',
    proxy: 'socks5://c1Ya41:q1SQQG@178.171.43.132:907',
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