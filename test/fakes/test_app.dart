import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/core/time/clock.dart';
import 'package:sg_smart_commute/features/environment/domain/environment_repository.dart';
import 'package:sg_smart_commute/features/environment/environment_providers.dart';
import 'package:sg_smart_commute/features/origin/domain/origin_controller.dart';
import 'package:sg_smart_commute/main.dart';

import 'fake_environment_repository.dart';

/// The real app with every external provider replaced by a fake (§18).
Widget buildTestApp({
  required LocationService location,
  required EnvironmentRepository environment,
  Duration locationTimeout = const Duration(seconds: 10),
  Clock? clock,
}) {
  return ProviderScope(
    retry: noAutomaticRetry,
    overrides: [
      locationServiceProvider.overrideWithValue(location),
      environmentRepositoryProvider.overrideWithValue(environment),
      locationTimeoutProvider.overrideWithValue(locationTimeout),
      clockProvider.overrideWithValue(clock ?? () => fakeNow),
    ],
    child: const SmartCommuteApp(),
  );
}
