import 'package:flutter/foundation.dart';

import 'app_failure.dart';

/// Runs [body] where its errors become `AsyncValue.error` (or another
/// user-facing state), keeping the §12/§13 contract in one place: every error
/// leaves as a typed [AppFailure], and anything else becomes an
/// [InvalidApiResponse]. In debug builds the failure, with its technical
/// [AppFailure.detail], is logged under [context] (§13); release builds log
/// nothing.
Future<T> guardAppFailure<T>(
  Future<T> Function() body, {
  required String context,
}) async {
  try {
    return await body();
  } catch (e, stack) {
    final failure = asAppFailure(e, context: context);
    if (kDebugMode) debugPrint('$context: $failure');
    Error.throwWithStackTrace(failure, stack);
  }
}

/// Synchronous form of [guardAppFailure] for parsers: maps the error without
/// logging (the provider boundary that calls the parser logs it).
T guardAppFailureSync<T>(T Function() body, {required String context}) {
  try {
    return body();
  } catch (e, stack) {
    Error.throwWithStackTrace(asAppFailure(e, context: context), stack);
  }
}

/// [error] itself if it is an [AppFailure]; otherwise an [InvalidApiResponse]
/// whose detail names [context] and the error (TypeError, FormatException,
/// StateError, …).
AppFailure asAppFailure(Object error, {required String context}) =>
    error is AppFailure ? error : InvalidApiResponse('$context: $error');
