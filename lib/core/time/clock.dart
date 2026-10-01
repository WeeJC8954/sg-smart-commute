import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Injectable clock returning the current instant in UTC (§12).
typedef Clock = DateTime Function();

DateTime systemClock() => DateTime.now().toUtc();

final clockProvider = Provider<Clock>((ref) => systemClock);
