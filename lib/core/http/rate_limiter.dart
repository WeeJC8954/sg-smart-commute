import 'dart:async';
import 'dart:collection';

import 'package:clock/clock.dart';

/// Grants permission to send one request; [acquire] completes when the
/// request may go out.
abstract interface class RequestRateLimiter {
  Future<void> acquire();
}

/// At most [maxRequests] grants in any rolling [window].
///
/// Grants are immediate while capacity is free, so a burst up to the limit is
/// not serialised. Beyond it, callers wait in FIFO order until the oldest
/// grant leaves the window. Time comes from `package:clock`, so tests drive it
/// with fake time.
class RollingWindowRateLimiter implements RequestRateLimiter {
  RollingWindowRateLimiter({required this.maxRequests, required this.window})
    : assert(maxRequests > 0);

  final int maxRequests;
  final Duration window;

  /// Grant times inside the window, oldest first.
  final Queue<DateTime> _granted = Queue();

  /// Completes when every earlier caller has been granted (FIFO).
  Future<void> _tail = Future.value();

  @override
  Future<void> acquire() {
    final turn = _tail.then((_) => _waitForSlot());
    _tail = turn;
    return turn;
  }

  Future<void> _waitForSlot() async {
    while (true) {
      final now = clock.now();
      while (_granted.isNotEmpty && now.difference(_granted.first) >= window) {
        _granted.removeFirst();
      }
      if (_granted.length < maxRequests) {
        _granted.addLast(now);
        return;
      }
      await Future<void>.delayed(_granted.first.add(window).difference(now));
    }
  }
}
