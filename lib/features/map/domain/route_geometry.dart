/// busrouter routes.min.json: one encoded polyline per service direction, in
/// busrouter's direction order. Decoded only when a ride needs it.
class RouteGeometry {
  const RouteGeometry(this._encoded);
  final Map<String, List<String>> _encoded;

  /// The encoded polyline for [service]'s busrouter direction [direction],
  /// or null when the file has none.
  String? encoded(String service, int direction) {
    final list = _encoded[service];
    if (list == null || direction < 0 || direction >= list.length) return null;
    return list[direction];
  }

  int get serviceCount => _encoded.length;
}

abstract interface class RouteGeometryRepository {
  /// The whole file, loaded once per session. Throws
  /// `StaticDataUnavailable(StaticDataset.busRouteGeometry)`.
  Future<RouteGeometry> load();
}
