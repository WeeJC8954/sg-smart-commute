import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/http/json_http_client.dart';
import '../domain/bus_network.dart';
import '../domain/bus_network_repository.dart';
import 'busrouter_parser.dart';

/// busrouter.sg static data behind [BusNetworkRepository] (guide v2.1 §9.1).
///
/// - Lazy: nothing is fetched until the first [load] (the first journey).
/// - Session cache: the first successful load is kept for the session, and
///   concurrent callers share the same in-flight load.
/// - Any network, HTTP or schema problem is [StaticDataUnavailable]. A failed
///   load is not cached, so a Retry fetches again.
class BusrouterRepository implements BusNetworkRepository {
  BusrouterRepository(this._http);

  final JsonHttpClient _http;
  Future<BusNetwork>? _network;

  @override
  Future<BusNetwork> load() {
    final existing = _network;
    if (existing != null) return existing;
    final loading = _fetch();
    _network = loading;
    loading.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_network, loading)) _network = null;
      },
    );
    return loading;
  }

  Future<BusNetwork> _fetch() async {
    final List<Object?> both;
    try {
      both = await Future.wait([
        _http.getJson(BusrouterEndpoints.stops),
        _http.getJson(BusrouterEndpoints.services),
      ]);
    } on AppFailure catch (e) {
      throw StaticDataUnavailable(StaticDataset.busRoutes, '$e');
    }
    final [stopsJson, servicesJson] = both;
    final stops = parseBusrouterStops(stopsJson);
    final services = parseBusrouterServices(servicesJson, stops);
    if (kDebugMode) {
      debugPrint(
        'BusrouterRepository: ${stops.length} stops, '
        '${services.length} services',
      );
    }
    return BusNetwork(stops: stops, services: services);
  }
}
