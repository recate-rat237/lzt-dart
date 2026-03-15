import 'package:test/test.dart';
import 'package:lzt_api/lzt_api.dart';

void main() {
  group('ForumClient', () {
    late ForumClient client;

    setUp(() {
      client = ForumClient(token: 'test_token');
    });

    tearDown(() => client.close());

    test('instantiates with token', () {
      expect(client, isNotNull);
    });

    test('instantiates with proxy', () {
      final c = ForumClient(
        token: 'test_token',
        proxy: 'http://proxy.example.com:8080',
      );
      expect(c, isNotNull);
      c.close();
    });

    test('instantiates with custom retry settings', () {
      final c = ForumClient(
        token: 'test_token',
        maxRetries: 5,
        retryDelay: Duration(seconds: 2),
      );
      expect(c, isNotNull);
      c.close();
    });
  });

  group('MarketClient', () {
    late MarketClient client;

    setUp(() {
      client = MarketClient(token: 'test_token');
    });

    tearDown(() => client.close());

    test('instantiates with token', () {
      expect(client, isNotNull);
    });
  });

  group('Exceptions', () {
    test('LztRateLimitError carries retryAfter', () {
      final e = LztRateLimitError('rate limited', retryAfter: 30);
      expect(e.retryAfter, 30);
      expect(e.toString(), contains('30'));
    });

    test('LztServerError carries statusCode', () {
      final e = LztServerError(502, 'bad gateway');
      expect(e.statusCode, 502);
    });

    test('LztBadRequestError carries details', () {
      final e = LztBadRequestError('bad', {'field': 'error'});
      expect(e.details?['field'], 'error');
    });

    test('all exceptions extend LztApiError', () {
      expect(LztAuthError('x'), isA<LztApiError>());
      expect(LztForbiddenError('x'), isA<LztApiError>());
      expect(LztNotFoundError('x'), isA<LztApiError>());
      expect(LztNetworkError('x'), isA<LztApiError>());
    });
  });
}
