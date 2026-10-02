import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

/// Injectable clock returning the current instant in UTC (§12).
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now().toUtc();

final clockProvider = Provider<Clock>((ref) => systemClock);

/// How often [uiTickProvider] ticks. Injectable for tests.
final uiTickIntervalProvider = Provider<Duration>((ref) => AppTimings.uiTick);

/// A UI-only tick. Widgets that show time-relative text watch it and then
/// read [clockProvider], so that text is recomputed every
/// [AppTimings.uiTick] while the screen is open. It never sends a request.
final uiTickProvider = NotifierProvider<UiTick, int>(UiTick.new);

class UiTick extends Notifier<int> {
  @override
  int build() {
    final timer = Timer.periodic(
      ref.watch(uiTickIntervalProvider),
      (_) => state++,
    );
    ref.onDispose(timer.cancel);
    return 0;
  }
}
