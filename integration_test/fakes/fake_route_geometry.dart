import 'dart:async';

import 'package:sg_smart_commute/core/errors/app_failure.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/map/domain/route_geometry.dart';

import 'fake_bus_network.dart';

/// A precision-5 Google encoded polyline of [points] (busrouter's format).
/// Web-safe: this file is compiled for the Web integration runs, where
/// bitwise operators are unsigned 32-bit, so there is no `~` or shift on a
/// negative value; the zigzag is plain arithmetic.
String encodePolyline(List<LatLng> points) {
  final out = StringBuffer();
  var prevLat = 0, prevLng = 0;
  void write(int delta) {
    var v = delta < 0 ? -2 * delta - 1 : 2 * delta;
    while (v >= 0x20) {
      out.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v = v ~/ 32;
    }
    out.writeCharCode(v + 63);
  }

  for (final p in points) {
    final lat = (p.latitude * 1e5).round();
    final lng = (p.longitude * 1e5).round();
    write(lat - prevLat);
    write(lng - prevLng);
    prevLat = lat;
    prevLng = lng;
  }
  return out.toString();
}

/// For every direction of every service in [fakeBusNetwork], a line straight
/// through that direction's stop positions, in busrouter's direction order.
RouteGeometry fakeRouteGeometry() {
  final network = fakeBusNetwork();
  return RouteGeometry({
    for (final service in network.services.values)
      service.number: [
        for (final codes in service.directions)
          encodePolyline([for (final c in codes) network.stops[c]!.position]),
      ],
  });
}

/// Controllable [RouteGeometryRepository]: returns [geometry], or throws
/// [failure]; [hold] keeps the load pending until [release].
class FakeRouteGeometryRepository implements RouteGeometryRepository {
  FakeRouteGeometryRepository({RouteGeometry? geometry, this.failure})
    : geometry = geometry ?? fakeRouteGeometry();

  RouteGeometry geometry;
  AppFailure? failure;
  int loads = 0;
  Completer<void>? _gate;

  void hold() => _gate = Completer<void>();
  void release() => _gate?.complete();

  @override
  Future<RouteGeometry> load() async {
    loads++;
    final gate = _gate;
    if (gate != null) await gate.future;
    final f = failure;
    if (f != null) throw f;
    return geometry;
  }
}
