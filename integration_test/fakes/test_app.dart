import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sg_smart_commute/app/app_info.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/core/time/clock.dart';
import 'package:sg_smart_commute/core/ui/motion.dart';
import 'package:sg_smart_commute/features/appearance/appearance_providers.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
import 'package:sg_smart_commute/features/appearance/domain/palette_store.dart';
import 'package:sg_smart_commute/features/bus_arrival/bus_arrival_providers.dart';
import 'package:sg_smart_commute/features/bus_arrival/domain/bus_arrival_repository.dart';
import 'package:sg_smart_commute/features/environment/domain/environment_repository.dart';
import 'package:sg_smart_commute/features/environment/environment_providers.dart';
import 'package:sg_smart_commute/features/journey/data/mrt_asset_repository.dart';
import 'package:sg_smart_commute/features/journey/domain/bus_network_repository.dart';
import 'package:sg_smart_commute/features/journey/journey_providers.dart';
import 'package:sg_smart_commute/features/map/domain/route_geometry.dart';
import 'package:sg_smart_commute/features/map/map_providers.dart';
import 'package:sg_smart_commute/features/map/presentation/basemap.dart';
import 'package:sg_smart_commute/features/origin/domain/origin_controller.dart';
import 'package:sg_smart_commute/features/places/domain/place.dart';
import 'package:sg_smart_commute/features/places/place_providers.dart';
import 'package:sg_smart_commute/main.dart';

import 'fake_bus_arrival_repository.dart';
import 'fake_bus_network.dart';
import 'fake_environment_repository.dart';
import 'fake_map.dart';
import 'fake_palette_store.dart';
import 'fake_place_search_repository.dart';
import 'fake_route_geometry.dart';

/// The real app with every external provider replaced by a fake (§18). The
/// map's tiles, logo, links and bus route geometry are fakes too: no test
/// fetches a tile or routes.min.json, or opens a browser, and the palette store
/// is a fake: no test touches device or browser storage. The version is the
/// fake [fakeAppInfo] (`appInfo: null` = a build with no version).
Widget buildTestApp({
  required LocationService location,
  required EnvironmentRepository environment,
  PlaceSearchRepository? places,
  BusNetworkRepository? busNetwork,
  MrtAssetRepository? mrt,
  double? mrtMaxDistanceMeters,
  BusArrivalRepository? busArrivals,
  Duration? busArrivalCacheTtl,
  Duration? placeSearchDebounce,
  int? placeSearchMinQueryLength,
  Duration locationTimeout = const Duration(seconds: 10),
  Duration locationPermissionTimeout = const Duration(seconds: 10),
  Clock? clock,
  Duration motionDuration = Duration.zero,
  TileProvider Function()? mapTiles,
  Future<bool> Function(Uri)? openLink,
  RouteGeometryRepository? routeGeometry,
  PaletteStore? paletteStore,
  AppPalette palette = AppPalette.teal,
  AppInfo? appInfo = fakeAppInfo,
}) {
  return ProviderScope(
    retry: noAutomaticRetry,
    overrides: [
      locationServiceProvider.overrideWithValue(location),
      environmentRepositoryProvider.overrideWithValue(environment),
      locationTimeoutProvider.overrideWithValue(locationTimeout),
      locationPermissionTimeoutProvider.overrideWithValue(
        locationPermissionTimeout,
      ),
      clockProvider.overrideWithValue(clock ?? () => fakeNow),
      uiMotionDurationProvider.overrideWithValue(motionDuration),
      placeSearchRepositoryProvider.overrideWithValue(
        places ?? FakePlaceSearchRepository(),
      ),
      busNetworkRepositoryProvider.overrideWithValue(
        busNetwork ?? FakeBusNetworkRepository(),
      ),
      mrtRepositoryProvider.overrideWithValue(mrt ?? fakeMrtRepository()),
      busArrivalRepositoryProvider.overrideWithValue(
        busArrivals ?? FakeBusArrivalRepository(),
      ),
      routeGeometryRepositoryProvider.overrideWithValue(
        routeGeometry ?? FakeRouteGeometryRepository(),
      ),
      paletteStoreProvider.overrideWithValue(
        paletteStore ?? FakePaletteStore(),
      ),
      initialPaletteProvider.overrideWithValue(palette),
      appInfoProvider.overrideWithValue(appInfo),
      mapTileProviderFactoryProvider.overrideWithValue(
        mapTiles ?? FakeTileProvider.new,
      ),
      mapLogoImageProvider.overrideWithValue(MemoryImage(transparentPng)),
      mapLinkOpenerProvider.overrideWithValue(
        openLink ?? FakeLinkOpener().call,
      ),
      if (busArrivalCacheTtl != null)
        busArrivalCacheTtlProvider.overrideWithValue(busArrivalCacheTtl),
      if (mrtMaxDistanceMeters != null)
        mrtMaxDistanceMetersProvider.overrideWithValue(mrtMaxDistanceMeters),
      if (placeSearchDebounce != null)
        placeSearchDebounceProvider.overrideWithValue(placeSearchDebounce),
      if (placeSearchMinQueryLength != null)
        placeSearchMinQueryLengthProvider.overrideWithValue(
          placeSearchMinQueryLength,
        ),
    ],
    child: const SmartCommuteApp(),
  );
}

/// A version no real build has, so a hard-coded "1.0.0 (1)" in the UI fails.
const fakeAppInfo = AppInfo(version: '9.8.7', buildNumber: '42');
