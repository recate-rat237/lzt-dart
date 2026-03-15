/// Base class for all LZT API exceptions.
class LztApiError implements Exception {
  final String message;
  const LztApiError(this.message);

  @override
  String toString() => 'LztApiError: $message';
}

/// Raised on network-level errors (no connection, DNS failure, etc.)
class LztNetworkError extends LztApiError {
  const LztNetworkError(super.message);

  @override
  String toString() => 'LztNetworkError: $message';
}

/// Raised on HTTP 400 Bad Request.
class LztBadRequestError extends LztApiError {
  final Map<String, dynamic>? details;
  const LztBadRequestError(super.message, [this.details]);

  @override
  String toString() => 'LztBadRequestError: $message';
}

/// Raised on HTTP 401 Unauthorized — invalid or missing token.
class LztAuthError extends LztApiError {
  const LztAuthError(super.message);

  @override
  String toString() => 'LztAuthError: $message';
}

/// Raised on HTTP 403 Forbidden — insufficient permissions.
class LztForbiddenError extends LztApiError {
  const LztForbiddenError(super.message);

  @override
  String toString() => 'LztForbiddenError: $message';
}

/// Raised on HTTP 404 Not Found.
class LztNotFoundError extends LztApiError {
  const LztNotFoundError(super.message);

  @override
  String toString() => 'LztNotFoundError: $message';
}

/// Raised on HTTP 429 Too Many Requests.
class LztRateLimitError extends LztApiError {
  /// Seconds to wait before retrying, parsed from Retry-After header.
  final int? retryAfter;

  const LztRateLimitError(super.message, {this.retryAfter});

  @override
  String toString() =>
      'LztRateLimitError: $message${retryAfter != null ? ' (retry after ${retryAfter}s)' : ''}';
}

/// Raised on HTTP 502/503 server errors.
class LztServerError extends LztApiError {
  final int statusCode;
  const LztServerError(this.statusCode, super.message);

  @override
  String toString() => 'LztServerError[$statusCode]: $message';
}
