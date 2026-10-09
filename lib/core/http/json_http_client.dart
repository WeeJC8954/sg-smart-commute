import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../errors/app_failure.dart';
import '../time/clock.dart';
import 'rate_limiter.dart';

/// GET-JSON client with the policy from guide §15:
/// - per-request timeout (≈ 10 s);
/// - bounded retry (max 2, exponential backoff) for network errors and 5xx only;
/// - 4xx is never retried; 429 → [ApiRateLimited] carrying `Retry-After`.
///   Until that has passed (at most [AppTimings.maxRetryAfter]) nothing more is
///   sent to that host: its requests fail at once with [ApiRateLimited] and
///   the time left, so a Retry tap cannot re-hit the limit;
/// - concurrent identical requests are deduplicated;
/// - optional client-side rate limits: [rateLimiterFor] picks the limiter (if
///   any) for a URI. Each outgoing send, retries included, waits for a grant.
///   The server's own 429 is still mapped as above;
/// - a 2xx body larger than [maxResponseBytes] (declared or actual) is an
///   [InvalidApiResponse]; reading stops there and it is never retried.
///
/// Every error leaves as a typed [AppFailure].
class JsonHttpClient {
  JsonHttpClient(
    this._client, {
    this.timeout = AppTimings.httpTimeout,
    this.maxResponseBytes = AppTimings.httpMaxResponseBytes,
    Future<void> Function(Duration)? delay,
    this.rateLimiterFor,
    Clock? clock,
  }) : _delay = delay ?? Future<void>.delayed,
       _clock = clock ?? systemClock;

  final http.Client _client;
  final Duration timeout;
  final int maxResponseBytes;
  final Future<void> Function(Duration) _delay;
  final RequestRateLimiter? Function(Uri uri)? rateLimiterFor;
  final Clock _clock;

  final Map<Uri, Future<Object?>> _inFlight = {};

  /// Host → when its `Retry-After` ends.
  final Map<String, DateTime> _heldUntil = {};

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
        if (attempt >= AppTimings.httpMaxRetries) throw e.failure;
        await _delay(AppTimings.httpBaseBackoff * (1 << attempt));
      }
    }
  }

  Future<Object?> _getOnce(Uri uri) async {
    // Checked before the grant (a held request takes none) and again after
    // it: a request that queued in the limiter while a 429 set the hold must
    // not go out either.
    _throwIfHeld(uri);
    // Waiting for a grant is not part of the request timeout.
    await rateLimiterFor?.call(uri)?.acquire();
    _throwIfHeld(uri);
    final _Received response;
    try {
      // The timeout covers the headers and the whole body.
      response = await _receive(uri).timeout(timeout);
    } on TimeoutException {
      _debugLog('timeout', uri);
      throw const _Retryable(NetworkUnavailable());
    } on http.ClientException catch (e) {
      _debugLog('network: ${e.message}', uri);
      throw const _Retryable(NetworkUnavailable());
    }

    final status = response.status;
    if (status >= 200 && status < 300) {
      try {
        return jsonDecode(utf8.decode(response.body));
      } on FormatException {
        throw const InvalidApiResponse('body is not JSON');
      }
    }
    _debugLog('HTTP $status', uri);
    if (status == 429) {
      final retryAfter = _parseRetryAfter(response.headers['retry-after']);
      if (retryAfter != null) _hold(uri.host, retryAfter);
      throw ApiRateLimited(retryAfter: retryAfter);
    }
    if (status == 401 || status == 403) throw const ApiUnauthorized();
    if (status >= 500) throw _Retryable(ApiUnavailable('HTTP $status'));
    throw ApiUnavailable('HTTP $status');
  }

  /// Sends the GET and reads a 2xx body of at most [maxResponseBytes]; a
  /// larger one (declared or actual) is an [InvalidApiResponse] and is not
  /// read further. Other statuses are mapped from the headers alone, so their
  /// body is not read.
  Future<_Received> _receive(Uri uri) async {
    final request = http.Request('GET', uri)
      ..headers['accept'] = 'application/json';
    final response = await _client.send(request);
    final status = response.statusCode;
    final declared = response.contentLength;
    final ok = status >= 200 && status < 300;
    if (!ok || (declared != null && declared > maxResponseBytes)) {
      // Not read; completion of the cancel is not needed.
      unawaited(response.stream.listen(null).cancel());
      if (ok) {
        _debugLog('response too large ($declared bytes declared)', uri);
        throw const InvalidApiResponse('response too large');
      }
      return _Received(status, response.headers, const []);
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      body.add(chunk);
      if (body.length > maxResponseBytes) {
        _debugLog('response too large (over $maxResponseBytes bytes)', uri);
        throw const InvalidApiResponse('response too large');
      }
    }
    return _Received(status, response.headers, body.takeBytes());
  }

  /// Throws [ApiRateLimited] with the time left while [uri]'s host is held;
  /// forgets an expired hold.
  ///
  /// The hold uses the device clock. A forward jump only ends it early (the
  /// next send may draw a fresh 429 and a new hold). A backward jump would
  /// stretch it by the jump, so more than [AppTimings.maxRetryAfter] left is
  /// cut back to the cap from now: a hold never outlasts the cap.
  void _throwIfHeld(Uri uri) {
    final heldUntil = _heldUntil[uri.host];
    if (heldUntil == null) return;
    final now = _clock();
    var left = heldUntil.difference(now);
    if (left > AppTimings.maxRetryAfter) {
      left = AppTimings.maxRetryAfter;
      _heldUntil[uri.host] = now.add(left);
    }
    if (left > Duration.zero) {
      _debugLog('held for Retry-After', uri);
      throw ApiRateLimited(retryAfter: left);
    }
    _heldUntil.remove(uri.host);
  }

  /// Holds [host] for [wait]. Concurrent 429s never shorten a hold: the
  /// later end wins.
  void _hold(String host, Duration wait) {
    final until = _clock().add(wait);
    final current = _heldUntil[host];
    if (current == null || until.isAfter(current)) _heldUntil[host] = until;
  }

  /// RFC 9110 delay-seconds only: digits, nothing else (a sign, a fraction or
  /// an HTTP-date is treated as absent, as is 0). Capped at
  /// [AppTimings.maxRetryAfter], so a bad header cannot lock a provider out;
  /// the cap is applied to the number before it becomes a [Duration], so a
  /// huge value cannot overflow.
  static Duration? _parseRetryAfter(String? value) {
    final text = value?.trim() ?? '';
    if (!RegExp(r'^[0-9]+$').hasMatch(text)) return null;
    const max = AppTimings.maxRetryAfter;
    final seconds = int.tryParse(text); // null: too big for an int
    if (seconds == null || seconds > max.inSeconds) return max;
    return seconds == 0 ? null : Duration(seconds: seconds);
  }

  static void _debugLog(String what, Uri uri) {
    if (kDebugMode) {
      debugPrint('JsonHttpClient: $what (${uri.host}${uri.path})');
    }
  }
}

class _Received {
  const _Received(this.status, this.headers, this.body);
  final int status;
  final Map<String, String> headers;
  final List<int> body;
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
/// Refresh all, tile Retry, future datasets).
final dataGovSgRateLimiterProvider = Provider<RequestRateLimiter>(
  (ref) => RollingWindowRateLimiter(
    maxRequests: DataGovSgRateLimit.maxRequests,
    window: DataGovSgRateLimit.window + DataGovSgRateLimit.safetyMargin,
  ),
);

/// The one limiter shared by every OneMap search (origin and destination).
final oneMapRateLimiterProvider = Provider<RequestRateLimiter>(
  (ref) => RollingWindowRateLimiter(
    maxRequests: OneMapRateLimit.maxRequests,
    window: OneMapRateLimit.window,
  ),
);

final jsonHttpClientProvider = Provider<JsonHttpClient>((ref) {
  final dataGovSg = ref.watch(dataGovSgRateLimiterProvider);
  final oneMap = ref.watch(oneMapRateLimiterProvider);
  return JsonHttpClient(
    ref.watch(httpClientProvider),
    clock: ref.watch(clockProvider),
    rateLimiterFor: (uri) => DataGovSgRateLimit.appliesTo(uri)
        ? dataGovSg
        : OneMapRateLimit.appliesTo(uri)
        ? oneMap
        : null,
  );
});
