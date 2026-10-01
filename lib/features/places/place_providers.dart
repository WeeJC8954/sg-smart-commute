import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/http/json_http_client.dart';
import '../../core/time/clock.dart';
import 'data/onemap_place_search_repository.dart';
import 'domain/place.dart';

/// The place-search provider for origin and destination (guide v2.1 §8):
/// OneMap tokenless. Overridden with a fake in widget and integration tests.
final placeSearchRepositoryProvider = Provider<PlaceSearchRepository>(
  (ref) => OneMapPlaceSearchRepository(
    ref.watch(jsonHttpClientProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Type-ahead debounce, injectable for tests.
final placeSearchDebounceProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 350),
);
