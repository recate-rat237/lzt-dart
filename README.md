# lzt-api-dart

Dart API wrapper for Lolzteam Forum & Market. Auto-generated from OpenAPI schemas. Supports async, proxy, and automatic retry on 429/502/503.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

## Quick Start

```dart
import 'package:lzt_api/lzt_api.dart';

void main() async {
  final forum = ForumClient(token: 'your_token');
  final threads = await forum.threadsList();
  print(threads);
  forum.close();

  final market = MarketClient(token: 'your_token');
  final accounts = await market.categoryList();
  print(accounts);
  market.close();
}
```

## Proxy

```dart
final forum = ForumClient(
  token: 'your_token',
  proxy: 'http://user:pass@proxy.host:8080',
);
```

## Error Handling

```dart
import 'package:lzt_api/lzt_api.dart';

try {
  final result = await forum.threadsGet(threadId: 123);
} on LztRateLimitError catch (e) {
  print('Rate limited, retry after ${e.retryAfter}s');
} on LztAuthError {
  print('Invalid token');
} on LztNotFoundError {
  print('Thread not found');
} on LztServerError catch (e) {
  print('Server error ${e.statusCode}');
} on LztApiError catch (e) {
  print('API error: ${e.message}');
}
```

## Retry Behaviour

By default the client retries up to **3 times** on:
- `429 Too Many Requests` — honours `Retry-After` header if present, otherwise exponential backoff
- `502 Bad Gateway` — exponential backoff
- `503 Service Unavailable` — exponential backoff

Customise via constructor:

```dart
final client = ForumClient(
  token: 'your_token',
  maxRetries: 5,
  retryDelay: Duration(seconds: 2), // base delay, doubles each attempt
);
```

## Code Generation

Methods and response models are auto-generated from OpenAPI schemas.

To regenerate after updating a schema:

```sh
dart run codegen/generate.dart \
  --schema schemas/forum.json \
  --output lib/src/forum/forum_client.dart \
  --class-name ForumClient \
  --base-url https://api.lzt.market

dart run codegen/generate.dart \
  --schema schemas/market.json \
  --output lib/src/market/market_client.dart \
  --class-name MarketClient \
  --base-url https://api.lzt.market
```

The CI pipeline will fail if the generated files are out of date with the schemas.

## Features

- Async via Dart's native `async/await`
- Auto-retry on 429/502/503 with exponential backoff
- `Retry-After` header support for 429
- Proxy support (`http://user:pass@host:port`)
- Typed exception hierarchy
- Auto-generated from OpenAPI schemas (Forum + Market)
- MIT licensed

## License

MIT
