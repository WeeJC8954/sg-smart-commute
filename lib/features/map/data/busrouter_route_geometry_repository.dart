import 'package:flutter/foundation.dart';

import '../../../core/config/app_config.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/http/json_http_client.dart';
import '../domain/route_geometry.dart';
import 'busrouter_routes_parser.dart';

/// busrouter.sg `routes.min.json` behind [RouteGeometryRepository].
///
/// - Lazy: nothing is fetched until the first [load] (the map opened with a
///   direct-bus journey).
/// - Each [load] downloads and parses the file. `routeGeometryProvider` holds
///   the result for the session, and [JsonHttpClient] merges concurrent
///   identical requests.
/// - Any network, HTTP or schema problem is [StaticDataUnavailable].
class BusrouterRouteGeometryRepository implements RouteGeometryRepository {
  BusrouterRouteGeometryRepository(this._http);

  final JsonHttpClient _http;

  @override
  Future<RouteGeometry> load() async {
    final Object? json;
    try {
      json = await _http.getJson(BusrouterEndpoints.routes);
    } on AppFailure catch (e) {
      throw StaticDataUnavailable(StaticDataset.busRouteGeometry, '$e');
    }
    final geometry = parseBusrouterRoutes(json);
    if (kDebugMode) {
      debugPrint(
        'BusrouterRouteGeometryRepository: ${geometry.serviceCount} services',
      );
    }
    return geometry;
  }
}
