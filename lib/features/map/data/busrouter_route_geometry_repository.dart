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
/// - Session cache: the first successful load is kept for the session, and
///   concurrent callers share the same in-flight load.
/// - Any network, HTTP or schema problem is [StaticDataUnavailable]. A failed
///   load is not cached, so the next [load] fetches again.
class BusrouterRouteGeometryRepository implements RouteGeometryRepository {
  BusrouterRouteGeometryRepository(this._http);

  final JsonHttpClient _http;
  Future<RouteGeometry>? _geometry;

  @override
  Future<RouteGeometry> load() {
    final existing = _geometry;
    if (existing != null) return existing;
    final loading = _fetch();
    _geometry = loading;
    loading.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_geometry, loading)) _geometry = null;
      },
    );
    return loading;
  }

  Future<RouteGeometry> _fetch() async {
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
