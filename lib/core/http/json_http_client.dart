import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../errors/app_failure.dart';
import 'rate_limiter.dart';

/// GET-JSON client with the policy from guide §15:
/// - per-request timeout (≈ 10 s);
/// - bounded retry (max 2, exponential backoff) for network errors and 5xx only;
/// - 4xx is never retried; 429 → [ApiRateLimited] carrying `Retry-After`;
/// - concurrent identical requests are deduplicated;
/// - optional client-side rate limits: [rateLimiterFor] picks the limiter (if
///   any) for a URI. Each outgoing send, retries included, waits for a grant.
///   The server's own 429 is still mapped as above.
///
/// Every error leaves as a typed [AppFailure].
class JsonHttpClient {
  JsonHttpClient(
    this._client, {
    this.timeout = AppTimings.httpTimeout,
    this.maxRetries = 2,
    this.baseBackoff = const Duration(milliseconds: 500),
    Future<void> Function(Duration)? delay,
    this.rateLimiterFor,
  }) : _delay = delay ?? Future<void>.delayed;

  final http.Client _client;
  final Duration timeout;
  final int maxRetries;
  final Duration baseBackoff;
  final Future<void> Function(Duration) _delay;
  final RequestRateLimiter? Function(Uri uri)? rateLimiterFor;

  final Map<Uri, Future<Object?>> _inFlight = {};

  Future<Object?> getJson(Uri uri) {
    final existing = _inFlight[uri];
    if (existing != null) return existing;
    // Block body on purpose: `remove` returns this very future, and
    // whenComplete would wait on a returned future (a self-deadlock).
    final future = _getWithRetry(uri).whenComplete(() {
      _inFlight.remove(uri);
    });
    _inFlight[uri] = future;
    return future;
  }

  Future<Object?> _getWithRetry(Uri uri) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _getOnce(uri);
      } on _Retryable catch (e) {
        if (attempt >= maxRetries) throw e.failure;
        await _delay(baseBackoff * (1 << attempt));
      }
    }
  }

  Future<Object?> _getOnce(Uri uri) async {
    // Waiting for a grant is not part of the request timeout.
    await rateLimiterFor?.call(uri)?.acquire();
    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'accept': 'application/json'})
          .timeout(timeout);
    } on TimeoutException {
      _debugLog('timeout', uri);
      throw const _Retryable(NetworkUnavailable());
    } on http.ClientException catch (e) {
      _debugLog('network: ${e.message}', uri);
      throw const _Retryable(NetworkUnavailable());
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      try {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        throw const InvalidApiResponse('body is not JSON');
      }
    }
    _debugLog('HTTP $status', uri);
    if (status == 429) {
      throw ApiRateLimited(
        retryAfter: _parseRetryAfter(response.headers['retry-after']),
      );
    }
    if (status == 401 || status == 403) throw const ApiUnauthorized();
    if (status >= 500) throw _Retryable(ApiUnavailable('HTTP $status'));
    throw ApiUnavailable('HTTP $status');
  }

  static Duration? _parseRetryAfter(String? value) {
    final seconds = int.tryParse(value?.trim() ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }

  static void _debugLog(String what, Uri uri) {
    if (kDebugMode) {
      debugPrint('JsonHttpClient: $what (${uri.host}${uri.path})');
    }
  }
}

class _Retryable implements Exception {
  const _Retryable(this.failure);
  final AppFailure failure;
}

final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// The one limiter shared by every data.gov.sg real-time caller (launch,
/// Refresh all, tile Retry, area-picker Retry, future datasets).
final dataGovSgRateLimiterProvider = Provider<RequestRateLimiter>(
  (ref) => RollingWindowRateLimiter(
    maxRequests: DataGovSgRateLimit.maxRequests,
    window: DataGovSgRateLimit.window + DataGovSgRateLimit.safetyMargin,
  ),
);

final jsonHttpClientProvider = Provider<JsonHttpClient>((ref) {
  final dataGovSg = ref.watch(dataGovSgRateLimiterProvider);
  return JsonHttpClient(
    ref.watch(httpClientProvider),
    rateLimiterFor: (uri) =>
        DataGovSgRateLimit.appliesTo(uri) ? dataGovSg : null,
  );
});
