# Architecture

Full specification: [`singapore-smart-commute-implementation-guide.v2.md`](singapore-smart-commute-implementation-guide.v2.md)
(v2.1). This file records the decisions. The guide holds the detail.

## ADR-001 — The project stays front-end-only

**Status:** Accepted (Milestone 0, 2026-10-01). **Evidence:** [`api-feasibility.md`](api-feasibility.md).

**Context.** The project must be a Flutter Android + Web app with no server-side component. Anything shipped
in a Web bundle or APK is publicly inspectable, so the client cannot hold confidential credentials.

**Decision.** Every Phase 1 capability uses a public, keyless, CORS-enabled endpoint, or static data bundled at
build time:

| Capability | Source |
|---|---|
| 2-hr forecast, UV, 1-hr PM2.5, 24-hr PSI | data.gov.sg v2 real-time APIs |
| Bus stops, services, per-direction stop order | busrouter static JSON (`data.busrouter.sg/v1`) |
| Live bus arrival | ArriveLah (`arrivelah2.busrouter.sg`) |
| Place search / geocoding | OneMap elastic search (tokenless), behind `PlaceSearchRepository` |
| MRT stations | Bundled asset generated from the data.gov.sg LTA MRT Station Exit dataset |
| Walking time | Labelled estimate (haversine × 1.3 ÷ 80 m/min), with no routing API |

Capabilities that need confidential credentials or lack browser CORS support are **excluded, never
proxied**:

- **LTA DataMall:** needs an AccountKey, and its CORS preflight is rejected (403, `Failed to fetch` in
  Chrome). A key would not fix the CORS problem.
- **OneMap routing:** needs a token (401).

**Consequences.**
- No backend, proxy, Worker, serverless or Firebase function, now or as a fallback.
- The app needs **no credentials**. Evaluators configure nothing.
- Phase 1 depends on two community services (busrouter, ArriveLah) that have no SLA. They are isolated behind
  repository interfaces, and the app shows a clear degraded state.
- OneMap tokenless search was chosen because it scored best among the tested providers (OneMap, Photon,
  Nominatim) on the M0 51-query test set, not because it is best in general. It may be withdrawn. The
  tested fallbacks are OSM-based (Photon and Nominatim, see `api-feasibility.md` §4). They would be added only when needed, as client-side adapters.
- data.gov.sg anonymous limit: 6 real-time calls per 10 s. Requests are session-cached and deduplicated, and
  every send to the v2 real-time API (launch, Refresh all, tile Retry, HTTP retries) passes
  one shared rolling-window limiter: at most 6 in any 10 s window plus a 1 s latency margin. Calls beyond it
  wait for capacity instead of being sent. A real 429 is still mapped to `ApiRateLimited`.

## Layering (target for Milestone 1+)

Feature-first, with a pragmatic clean architecture (guide §11):

```text
lib/
  app/            app shell, light/dark theme, home screen, RouteCard (origin + destination)
  core/           config (non-secret constants), errors (AppFailure), http, location, geo, time, ui
  features/
    environment/  data.gov.sg adapters → EnvironmentLocator → dashboard
    places/       PlaceSearchRepository (OneMap adapter + normaliser), PlaceSearchField
    destination/  DestinationController + DestinationCard
    journey/      busrouter loader, DirectBusPlanner, MRT asset
    bus_arrival/  BusArrivalRepository (ArriveLah)
```

- State: Riverpod `AsyncValue<T>` with typed `AppFailure`. There is no custom `LoadState`.
- DTOs stay in `data/`. Widgets consume domain models only.
- Time: parse ISO `+08:00`, store UTC, display at a fixed +08:00 offset (no `timezone` package).

## Milestone 1 (location and environment)

- `lib/core/`: `config/app_config.dart` (SG bounds, endpoints, timings, stale thresholds), `errors/app_failure.dart`
  (sealed `AppFailure`), `geo/geo.dart` (`LatLng`, `isWithinSingapore`, haversine), `time/` (SGT formatting,
  injectable `Clock`), `http/json_http_client.dart` (timeout, bounded retry, 429, dedup, optional per-URI rate limiter),
  `http/rate_limiter.dart` (generic `RollingWindowRateLimiter`; only the provider wiring maps data.gov.sg and OneMap
  to their own limiters), `ui/status_rows.dart` (shared `BusyRow` / `ErrorRetryRow`), `ui/motion.dart` (`MotionSize`: one height animation
  per card, instant under reduce motion),
  `location/` (`LocationService` seam + geolocator adapter).
- `lib/features/origin/`: `OriginController` (Riverpod `Notifier`) is the permission → timeout → fallback →
  late-fix state machine. `Origin` carries provenance (`gps` | `manual`). `OriginCard` is the UI (the origin section of
  `RouteCard`, `lib/app/route_card.dart`). Each
  acquisition attempt has an id, so a superseded attempt's results are dropped. No attempt replaces a manual
  origin: only `useCurrentLocation()` (the "Use my current location" chip) does that.
- `lib/features/environment/`: `data/` (data.gov.sg parsers + repository), `domain/` (models,
  `EnvironmentLocator`, band tables), `environment_providers.dart` (one session-cached `FutureProvider` per
  dataset, refresh cooldown), `presentation/` (dashboard tiles, display strings).
- Seams overridden in tests: `locationServiceProvider`, `locationTimeoutProvider`, `environmentRepositoryProvider`,
  `httpClientProvider` (the rate-limit widget tests swap only the transport for a fake data.gov.sg),
  `clockProvider`, `placeSearchRepositoryProvider`. Fakes are in `integration_test/fakes/` and shared with the widget tests in `test/`. This is a deliberate test-harness arrangement forced by the Web integration build: a Web `flutter drive` build cannot import files outside the target's folder, so the shared fakes must live under `integration_test/`. It is the only thing `test/` imports from `integration_test/`; `test/` does not otherwise depend on it.

## Milestone 2 (places)

- `lib/features/places/`:
  - `domain/place.dart`: `Place`, `PlaceType`, `PlaceSource`, `SearchMode` and `PlaceSearchRepository` (guide §8.1).
  - `domain/place_query.dart`: the normaliser, the postal-code rule and the minimum length.
  - `domain/place_search_session.dart`: debounce, submit and a sequence token, so an older response never
    replaces a newer query.
  - `data/onemap_parser.dart` + `data/onemap_place_search_repository.dart`: the exact-postcode rule, the SG-bounds
    filter, a 5-min cache, and `reverseGeocode` → null.
  - `presentation/place_search_field.dart`: one search component for origin and destination. States: loading,
    too short, no results, no exact postcode, unauthorized, and network/unavailable/malformed with Retry. Shows the
    attribution.
- The origin card uses `PlaceSearchField` for the manual origin. It calls `OriginController.beginManualEntry` /
  `selectManualOrigin`, so the M1 late-fix and attempt-id rules apply.
- `lib/features/destination/`: `DestinationController` (a separate `Notifier`, so a destination can never change
  the origin) and `DestinationCard` ("Where are you heading to today?", shown once an origin exists; the destination section
  of `RouteCard`).
- OneMap calls go through the generic `JsonHttpClient` (timeout, retry, 401/403, 429) with a shared `OneMapRateLimit`
  limiter (1 request per 1 s, FIFO, retries included), on top of the debounce and the bounded cache. Photon / Nominatim / bundled fallbacks are not built (guide §0.1 item 6).
- `ProviderScope(retry: noAutomaticRetry)`: Riverpod 3's automatic retry is off (rate limits; explicit Retry).
- Dependencies added: `flutter_riverpod` 3.4.3, `geolocator` 14.1.1, `clock` 1.1.3 (the fake-time `clock.now()` in
  `http/rate_limiter.dart`), `fake_async` (dev).

## Milestone 3 (direct bus + MRT alternative)

- `lib/features/journey/domain/`: `bus_network.dart` (`BusStop`, `BusService`, `BusNetwork`),
  `bus_network_repository.dart` (interface, so busrouter can be replaced), `walking.dart` (`WalkEstimate`),
  `direct_bus_planner.dart` (pure `planDirectBus` → sealed `JourneyPlan`: `WalkOnly` / `DirectBusOptions` /
  `NoNearbyStops` / `NoDirectBus`), `mrt.dart` (`MrtStation`, `nearestMrtStation`).
- `lib/features/journey/data/`: `busrouter_parser.dart` + `busrouter_repository.dart` (lazy, session-cached,
  `StaticDataUnavailable`), `mrt_grouping.dart` + `mrt_asset.dart` (pure Dart, shared with the `tool/`
  generator), and `mrt_asset_repository.dart` (rootBundle).
- `journey_providers.dart`: `busNetworkProvider` (holds the network for the session), `journeyPlanProvider`
  and `mrtSuggestionProvider` (both watch the origin and destination, so they recalculate on change).
  `presentation/journey_card.dart` shows the result.
- "No direct bus" and "no nearby stop" are planner results, not exceptions (so `RouteNotFound` from the guide's
  §13 list is modelled as `NoDirectBus` / `NoNearbyStops`). Only data failures are `AppFailure`s.
- Tunables live in `JourneyConfig` / `TransportDataBounds` (`app_config.dart`), injectable via
  `plannerConfigProvider`. Test seams: `busNetworkRepositoryProvider`, `mrtRepositoryProvider`.
- No live calls are made during the candidate search, and no arrival data is fetched in M3.

## Milestone 4 (live bus arrivals)

- `lib/features/bus_arrival/domain/`: `bus_arrival.dart` (`BusArrival`, `BusLoad`, `BusType`, `ServiceArrivals`,
  `StopArrivals`; `nextArrivals` picks one service's next three; `etaLabel` gives `Arr` / `N min`),
  `bus_arrival_repository.dart` (interface, so ArriveLah can be replaced), `bus_arrival_cache.dart`
  (`BusArrivalCache`: the only caller of the repository; 15 s per-stop TTL, in-flight dedup, failures not cached).
- `lib/features/bus_arrival/data/`: `arrivelah_parser.dart` (the only code that knows ArriveLah's JSON; times via
  the shared strict `parseSourceTimestamp`, also used by the NEA parsers; lenient optional fields;
  `{"error"}` → `BusArrivalUnavailable`) and
  `arrivelah_bus_arrival_repository.dart` (one GET per stop through `JsonHttpClient`).
- `bus_arrival_providers.dart`: `journeyArrivalsProvider` awaits `journeyPlanProvider`, and only for
  `DirectBusOptions` requests each distinct boarding stop once. Its `JourneyArrivals` holds the exact plan it was
  fetched for, the check time and a per-stop result (`StopArrivalsLoaded` / `StopArrivalsFailed`). Widgets show it
  only while that same plan is displayed, so a late answer for an older journey never attaches to a new one.
  Refresh and Retry invalidate this provider only: the plan is not recomputed, and the cache prevents
  re-requesting a stop inside the TTL.
- `presentation/option_arrivals.dart`: `OptionArrivals` (under each option, after "Take Bus …") and
  `ArrivalsFooter` (source, check time, "Refresh arrivals"). `OptionArrivals` watches the UI-only
  `uiTickProvider`, so ETAs count down from the clock between checks and give way to a refresh prompt once the
  check is outdated; implausible times are dropped by `nextArrivals` (`isPlausibleEta`). The M3 journey card embeds them; the route itself is
  rendered exactly as in M3 and never depends on arrival state.
- New failure: `BusArrivalUnavailable` (provider error body). Network / timeout / HTTP / malformed reuse the
  existing `NetworkUnavailable` / `ApiUnavailable` / `InvalidApiResponse`.
- Tunables in `ArriveLahEndpoints` / `BusArrivalConfig` (`app_config.dart`). Test seams:
  `busArrivalRepositoryProvider`, `busArrivalCacheTtlProvider` (plus `clockProvider`).
- No polling, no maps, no vehicle tracking, no MRT arrivals.

## Milestone 5 (hardening)

- **Response size cap** (`JsonHttpClient`): a 2xx body over `AppTimings.httpMaxResponseBytes` (4 MiB) is an
  `InvalidApiResponse` and is not retried. A declared `Content-Length` over the cap is refused unread; otherwise
  reading stops as soon as the cap is passed. Non-2xx bodies are not read. The request timeout covers headers
  and body. Numbers and the measured payload sizes: `docs/assumptions.md`.
- **Content-Security-Policy** (`web/index.html`, a `<meta>`, since static hosting such as GitHub Pages cannot
  set headers). Measured in Chrome on 2026-10-02 over a full journey, the app contacts only itself, the four
  keyless APIs (`api-open.data.gov.sg`, `www.onemap.gov.sg`, `data.busrouter.sg`, `arrivelah2.busrouter.sg`), and
  the Flutter engine's CDN (`www.gstatic.com` for CanvasKit script + WebAssembly, `fonts.gstatic.com` for
  fallback fonts). The policy allows exactly those:
  - `connect-src` = self + those six origins; `script-src` = self + `www.gstatic.com` + `'wasm-unsafe-eval'`
    (CanvasKit is WebAssembly) + one `sha256-` hash; no `'unsafe-eval'`, no `'unsafe-inline'` scripts;
  - the hash is the inline snippet that the **debug** web loader (Flutter 3.47.2) runs; without it `flutter run`
    on Web shows a blank page. Release builds never run it. After a Flutter upgrade, a blank debug page plus a
    console line "Executing inline script violates … a hash ('sha256-…')" means: replace the hash;
  - `style-src 'unsafe-inline'` (Flutter sets inline styles), `img-src` self/data/blob, `object-src 'none'`,
    `base-uri 'self'`, `form-action 'none'`, `default-src 'self'`;
  - not settable from a `<meta>`: `frame-ancestors`. A host that can send headers should add it.
  - `test/web/content_security_policy_test.dart` keeps `connect-src` equal to the endpoints in
    `app_config.dart` (+ the engine CDN), so a new provider cannot be added without updating the policy.
  - Using the engine CDN is Flutter's default (`flutter build web`); building with `--no-web-resources-cdn` would
    serve CanvasKit locally, but fallback fonts still come from `fonts.gstatic.com`, so the CDN stays listed.
- **Integration tests on Web**: the fakes moved to `integration_test/fakes/` (a Web build cannot import outside
  the target's folder), and `initIntegrationTest()` registers the `TestTextInput` stub so `enterText` works in
  the profile builds the Web runs use. How to run them: `docs/testing.md`.
- **Origin**: a prompt answered late (granted) while manual entry is open clears the "not answered" note.
- **Refresh all** (`EnvironmentRefresher.refreshAll` → `RefreshAllResult`): the 15 s cooldown holds only after a
  refresh that fully succeeded. While a dataset is loading, nothing new starts ("still refreshing"); after a
  failure, the refresh runs again at once.
- **Large text**: the arrivals footer stacks its button below the attribution when it has less than
  `HomeLayout.arrivalsFooterMinRowWidth` × the text scale, the same scaling rule as the Conditions grid.
- **Android Location Accuracy** (accepted platform limitation): Play services' "Location Accuracy" dialog
  appears inside `getCurrentPosition`, so the 10 s timeout keeps running behind it. Both answers recover
  ("Turn on" → the late fix fills the origin, "No thanks" → manual entry). Pausing the timers while the app is
  not in the foreground, or switching to `forceLocationManager`, was judged not worth the risk to the origin
  state machine or to fix quality.

## Phase 2 Milestone 1 (journey map)

An optional map of the journey the planner already found (guide §17; decisions and evidence in
`docs/map-feasibility.md`, tunables in `docs/assumptions.md` "Journey map" and after).

- `lib/features/map/domain/map_scene.dart`: pure Dart, no Flutter or map-package import. `buildMapScene` turns
  origin, destination and the current `JourneyPlan` into a `MapScene` (markers in journey order, bounds, a
  screen-reader summary). Only a `DirectBusOptions` adds stops, from its first (suggested) option. It never plans.
- `lib/features/map/map_providers.dart`: `mapSceneProvider` watches the origin, the destination and
  `journeyPlanProvider` (the same provider the journey card watches, so no second plan and no extra bus-data
  load); while the plan is loading or failed it marks only the two ends. `mapExpandedProvider` is session UI state:
  closed by default, so no tile is requested until the user opens the map.
- `lib/features/map/presentation/`: the only files that import `flutter_map` / `latlong2`.
  `journey_map_card.dart` ("Show map" / "Hide map"; nothing until both ends exist), `journey_map.dart`
  (`FlutterMap` with the camera fitted before the first frame and constrained to OneMap's bounds and z11–19;
  markers; the "tiles unavailable" note below the map), `basemap.dart` (OneMap Default/Night by brightness;
  `OneMapTileProvider` with a plain HTTP client, so no automatic retry, and a size-capped Android cache; the
  persistent attribution row).
- The home screen shows `JourneyMapCard` under the journey card. Removing the map removes that one widget; the
  planner, journey card and arrivals never import `features/map`.
- **`url_launcher`** (Flutter team plugin) is a UI/platform dependency, not a data provider: it only opens the
  attribution links (onemap.gov.sg, sla.gov.sg) in the external browser (`LaunchMode.externalApplication`). It
  needs no CSP change (navigation, not a fetch) and no Android `<queries>` entry: `launchUrl` starts the activity
  directly; only `canLaunchUrl`, which the app does not call, needs package visibility.
- **CSP**: no change. Tiles and the logo come from `www.onemap.gov.sg`, already in `connect-src` (flutter_map and
  the engine fetch and decode their bytes). `test/web/content_security_policy_test.dart` now includes the
  basemap endpoints.
- Test seams: `mapTileProviderFactoryProvider`, `mapLogoImageProvider`, `mapLinkOpenerProvider`;
  `buildTestApp` fakes all three (`integration_test/fakes/fake_map.dart`), so no test fetches a tile or opens a
  browser.
- Not in P2-M1: ride polylines (`routes.min.json`), walking lines or routers, transfers, map-based planning,
  automatic OSM fallback, option sync (the map shows the suggested option).

## Phase 2 Milestone 2 (bus ride line)

The suggested bus ride is drawn on the road under the P2-M1 pins (decisions D1–D6 in
`docs/p2-m2-bus-geometry-implementation-plan.md`; evidence in `docs/map-feasibility.md` §5; rules and tunables in
`docs/assumptions.md` "Bus ride line" and "Route geometry load"). The journey planner stays authoritative: the map
never plans and never changes the service, direction, boarding or alighting stop.

- **Files and responsibilities** (`lib/features/map/`):
  - `domain/polyline_codec.dart`: `decodePolyline`, a precision-5 Google polyline decoder. Web-safe: a negative
    delta is `-(result >> 1) - 1`, never `~(result >> 1)`, since dart2js bitwise operators are unsigned 32-bit
    (the P2-M0 spike hit this on Web only).
  - `domain/route_geometry.dart`: `RouteGeometry` (service → encoded polyline per busrouter direction, kept
    encoded) and the `RouteGeometryRepository` interface.
  - `domain/ride_geometry.dart` (pure Dart): `MapRide` (service, `sourceDirection`, `boardIndex`, the ride's
    `stops`, `leadingStops`), `leadingStopCount`, the sealed `RideLine` (`RideLineDrawn` with the points, or
    `RideLineUnavailable` with a `RideLineGap`: `noGeometry`, `malformedGeometry`, `notMatched`),
    `RideMatchConfig` (defaults from `MapConfig`) and `matchRide`.
  - `domain/map_scene.dart`: `MapScene.ride` is built from the suggested option; the scene's bounds include the
    ride's stops.
  - `data/busrouter_routes_parser.dart` (`parseBusrouterRoutes`: `{service: [dir 0, dir 1?]}`, invalid entries
    dropped, the same 5 % rule as the other busrouter files) and `data/busrouter_route_geometry_repository.dart`
    (`JsonHttpClient`, one session-held load shared by concurrent callers, a failure not cached).
  - `map_providers.dart`: `routeGeometryRepositoryProvider`, `routeGeometryProvider` (a `FutureProvider`, a
    failure held) and `rideLineProvider`.
  - `presentation/journey_map.dart`: a `PolylineLayer` (key `map-ride-line`) before the `MarkerLayer`, so the
    pins stay on top, and the `map-ride-unavailable` note below the map.
- **Data flow**: planner `BusOption` (with `boardIndex`) → `buildMapScene` → `MapRide` on the `MapScene` →
  `rideLineProvider` runs the pure `matchRide(ride, geometry)` → `RideLine` → the open map draws a
  `RideLineDrawn` only when its `ride` equals the scene's ride, so an earlier journey's line is never drawn.
  `rideLineProvider` is derived from the current scene and is watched only by the open map, so `routes.min.json`
  is not requested before "Show map" with a direct-bus journey. `rideLineProvider` is auto-disposed (the open map
  is its only listener) while `routeGeometryProvider` is kept for the session. `MapExpanded.show` retries a held,
  settled failure (`ref.exists` and `hasError && !isLoading`) only when the journey being shown has a bus ride
  (`mapSceneProvider.ride != null`), so the invalidated load is watched by the opening map at once. Nothing is
  requested for a walk-only or no-bus journey, however often "Show map" is pressed.
- **D3, `BusOption.boardIndex`**: `planDirectBus` already knew the boarding occurrence; `BusOption` now keeps it.
  One constructor call, no behaviour change (the ranking does not read it). The map therefore never re-derives
  the occurrence, which on a loop could be another one.
- **D4, `BusService.sourceDirectionOf`**: `parseBusrouterServices` drops a direction with fewer than 2 known stops,
  which would shift `BusService.directions` against `routes.min.json`. The parser sets `sourceDirections` only when
  it drops something, and `sourceDirectionOf(d)` maps back to busrouter's index. No behaviour change today
  (live data: 0 dropped directions); this index mapping is what keeps the opposite direction's polyline from being
  drawn. The matcher does not detect a swapped direction (its reversed variant may accept it), so
  `test/features/map/map_scene_test.dart` pins the mapping.
- **Matcher** (all-or-nothing, least along-line length, closed-only doubling, loop span guard): the rules are the
  "Bus ride line" row of `docs/assumptions.md`. A failure to match is markers plus a note, never a straight
  stand-in and never a routing failure.
- **`flutter_map` stays in `features/map/presentation/`**: the codec, geometry, matcher and scene are pure Dart
  with no Flutter or map-package import. `features/journey` still never imports `features/map`; the dependency
  stays one-way (the map reads journey).
- **CSP**: no change. `data.busrouter.sg` is already in `connect-src`; `test/web/content_security_policy_test.dart`
  gains `BusrouterEndpoints.routes` in its provider set.
- Test seam: `routeGeometryRepositoryProvider`; `buildTestApp` fakes it with `FakeRouteGeometryRepository`
  (`integration_test/fakes/fake_route_geometry.dart`), so no test fetches `routes.min.json`. Matcher tests use the
  fixtures in `test/fixtures/busrouter/geometry/`, captured once by `tool/capture_route_geometry_fixtures.dart`.
- Not in P2-M2: walking lines or routers (P2-M3 adds straight dashed "est." connectors), transfers, option sync
  (the map shows the suggested option), live vehicles, automatic OSM fallback, map-based planning.

## Phase 2 Milestone 3 (walk connectors, MRT markers, option sync)

The user can select any displayed direct-bus option in the journey card, and the open map shows that option, with
straight dashed "est." walking connectors, the card's two MRT suggestions and a two-entry legend (decisions D1–D9 in
`docs/p2-m3-map-option-sync-implementation-plan.md`; rules in `docs/assumptions.md` "Journey option selection",
"Walking connectors and legend", "MRT markers" and "Map camera"). The planner stays authoritative and the map stays
a consumer: it never plans, selects, looks up stations or computes walking times.

- **Files and responsibilities:**
  - `features/journey/domain/option_selection.dart` (pure Dart): `OptionSelection(plan, index)` and
    `selectedOptionIndex`, which honours a selection only for the identical plan object (else 0, the suggestion).
  - `features/journey/journey_providers.dart`: `optionSelectionProvider` (`OptionSelectionController.select`). It
    never watches the plan, so selecting never re-plans; it is not auto-disposed, so it survives "Hide map".
  - `features/journey/domain/mrt.dart`: `MrtWording`, the card's MRT words, now shared with the map's markers.
  - `features/journey/presentation/journey_card.dart`: "Select" / "Selected" per option (two or more options).
  - `features/map/domain/map_scene.dart`: `buildMapScene(selectedIndex:, mrt:)`; `MapWalk` and the derived
    `MapScene.walks`; `MapMarkerKind.mrtNearOrigin` / `mrtNearDestination`; `MapScene.isAlternative`; the summary.
  - `features/map/map_providers.dart`: `mapSceneProvider` reads the selection and the settled MRT suggestion.
  - `features/map/presentation/journey_map.dart`: the dashed connector layer, MRT pins (drawn first), the legend,
    and the camera's fit-the-latest-scene rule.
- **Data flow**: the journey card writes `optionSelectionProvider`; `mapSceneProvider` reads it with
  `journeyPlanProvider` and `mrtSuggestionProvider` (both only when settled) → `buildMapScene` → `JourneyMap`.
  `rideLineProvider` follows the scene's ride, so a selection recomputes the line against the same session-held
  `routes.min.json` (no second request), and the P2-M2 guard (`line.ride == scene.ride`) is unchanged. Arrivals
  are untouched: `journeyArrivalsProvider` already covers every displayed option's boarding stop.
- **Dependency direction**: the journey feature (and `bus_arrival`) never imports `features/map`; the map reads the
  journey's selection, plan and MRT suggestion. `flutter_map` / `latlong2` stay in `features/map/presentation/`.
- **Camera**: fitted once per scene change (a new journey, the user's selection, the MRT suggestion settling),
  without animation and never on a timer (`docs/map-feasibility.md` §4.2 rule 5). `JourneyMap` remembers the scene
  it last fitted and fits the latest one when the map becomes ready and on each change.
- **No new dependency, provider host or network request**; CSP unchanged. Dashed lines use flutter_map 8.3.2's
  `StrokePattern.dashed`.
- **Decision numbers**: P2-M3's D1–D9 are its plan's own, separate from P2-M2's D1–D6 above (the plan's
  "Decision numbers" note maps them).
- Not in P2-M3: walking routing (the `routed-foot` question went to P2-M4, which closed it with no router: `docs/map-feasibility.md` §6.1), a walk-only connector, MRT
  routing, lines, codes, directions or arrivals, a legend entry for MRT, choosing an option from the map,
  transfers, live vehicles.

## Phase 2 Milestone 4 (hardening) and Phase 2 close-out

Hardening checks from `docs/map-feasibility.md` §10 item 4, with decisions D1–D8, Q1–Q4 and R in
`docs/p2-m4-map-hardening-implementation-plan.md`. Phase 2 closes here.

- **Reduced motion:** `JourneyMap` passes flutter_map one of two constant `InteractionOptions`, chosen by
  `MediaQuery.disableAnimations` (Android "Remove animations", Web `prefers-reduced-motion`): with the setting, no
  `flingAnimation` flag and `doubleTapZoomDuration: Duration.zero`; otherwise today's options. Why: flutter_map ignores
  the setting, and the framework plays a fling 200× faster under it, so the map jumped on release. The camera fit is
  unchanged. flutter_map fixes the double-tap duration when the map is created, so a setting change while the map is
  open does not rebuild it (the camera is kept) and that zoom keeps the framework's reduced timing until reopened.
- **No walking router:** `docs/map-feasibility.md` §6.1, so no new host, client, header or CSP change; the map stays
  a consumer of the plan, and the straight dashed connectors are final.
- **Verified, unchanged:** the Android tile cache follows `max-age`; no HD tiles; OneMap's terms re-checked.
- **Dev tool:** `tool/map_performance_probe.dart` (profile, Android only, live OneMap tiles, not a gate).
- Not in P2-M4: any new map feature, routing, keyboard-animation changes, the simplification refactor, UI polish.

## UI polish follow-ups (after Phase 2)

`docs/ui-polish-implementation-plan.md` was implemented by PR #35, before Phase 2. This closes the drift and
evidence gaps Phase 2 left (`docs/ui-polish-followups-implementation-plan.md`): presentation, tests and docs only.

- **Colours:** only from the theme scheme. The map pins' shadow, added in P2-M1 as a fixed colour, uses
  `colorScheme.shadow`. `test/app/app_theme_test.dart` scans `lib/`, and the teal seed is the one fixed colour.
- **Motion:** `MotionSize` as documented. Growing reveals new content as the card grows; shrinking removes the
  content at once and only the freed space below closes over the resize duration (existing presentation behaviour, not a
  defect). Known limitation: content changing on adjacent frames settles directly
  to the later layout. Whole-app tests at the real 250 ms are in `test/app/home_screen_test.dart`. The map card's
  Show/Hide stays instant (D2).
- **Home list:** lazy, with no keep-alive. Known presentation limitation: at 2× text, a deep scroll resets open
  alternative steps and a panned map's camera; the selection, the open map and the data are unaffected
  (assumptions, "Home list scrolling (D3)").

## Post-submission enhancement E1: colour themes

Added after the project was submitted; it is not a milestone, and Phase 1, Phase 2 and UI polish are not reopened.
The user picks Teal, Blue, Rose, Purple or Orange from an app-bar button; the choice is remembered on the device or
browser (plan: `docs/e1-colour-themes-implementation-plan.md`; rules: `docs/assumptions.md`, "Colour palettes (E1)",
"Palette persistence (E1)", "Palette selector (E1)"). The code is `lib/features/appearance/`: `domain/app_palette.dart`
(`AppPalette`: id, label, seed), `domain/palette_store.dart` (the store interface),
`data/shared_preferences_palette_store.dart`, `appearance_providers.dart` (`loadInitialPalette`,
`initialPaletteProvider`, `paletteStoreProvider`, `paletteProvider`), `presentation/palette_theme.dart` and `presentation/palette_menu_button.dart`.

- **ADR E1-1: one new dependency, `shared_preferences` 2.5.5 (pinned exactly).** It is the only direct dependency added. It
  keeps one string on the device (Android app storage, Web `localStorage` per origin), so ADR-001 holds: no server,
  account, secret, new host or CSP change, and tests use an in-memory fake. Cost: a private window forgets the choice.
- **ADR E1-2: the stored palette is read once before `runApp`, bounded to 500 ms.** The first frame is then already in
  the right colours, with no flash of Teal. Trade-off: if storage hangs, startup waits up to
  `AppearanceConfig.paletteLoadTimeout` (500 ms) and shows Teal; normally the read takes a few milliseconds. A missing
  or unknown value, an error or a timeout gives Teal, and a result that arrives late is ignored, so the running session
  never changes colour on its own. No splash or loading screen is added. A failed
  write is silent: the choice stays for the session, nothing claims it was saved, and the next launch shows what
  storage holds.
- **ADR E1-3: `MenuAnchor` with `RadioMenuButton`s for the selector.** Stock Material gives arrow-key navigation, Enter
  or Space to choose, Escape to close, focus back on the button, and a radio's checked state per option, so the only
  custom code is a small `MergeSemantics(Semantics(expanded: ...))` wrapper (plain Material exposed no open or closed
  state); there is no custom focus code and no live-region announcement. Compared and rejected: `PopupMenuButton` with
  `CheckedPopupMenuItem` (checked state but not a mutually exclusive group, and the older API), a bottom sheet (odd on a
  wide Web page, needs closing), a dialog (modal, more taps) and a drawer (unjustified for one setting). Real-Chrome keyboard and semantics behaviour matched the widget tests in the E1 live checks (`docs/testing.md`).
- **ADR E1-4: palette x brightness.** Each palette is a `ColorScheme.fromSeed` seed (default variant, no role
  hand-tuned) used for both brightnesses, and the system keeps choosing light or dark (`ThemeMode.system`; there is no
  manual dark control). Teal's seed is `Colors.teal`'s value, so the default is identical to the previous scheme.
  Measured during planning: 0 contrast failures over 14 pairs x 5 palettes x light and dark, the lowest 4.03:1 against
  a 3:1 target and text pairs at 5.8:1 or more; the closest pair is Rose and Purple (delta E 25.3 light, 25.6 dark).
- **ADR E1-5: the map-state contract and why it holds.** A palette change only recolours: the map's open state,
  camera and pan, the plan, arrivals, route geometry and the selected option are kept, and no tile is requested. It
  holds without a map change because only the `ThemeData` that `MaterialApp` provides changes: nothing keyed or rebuilt
  from scratch depends on the palette, and the plan, arrivals, geometry and selection live in providers that never
  watch `paletteProvider`. OneMap Default or Night tiles follow the brightness only, so Teal to Rose in light keeps
  Default and a dark system keeps Night. Pinned by `test/features/appearance/palette_change_invariants_test.dart` and
  by mutation checks (keying `FlutterMap` or `HomeScreen` by palette, or choosing the tile style from the palette)
  that fail as required.
- **ADR E1-6: the colour guard.** `test/app/app_theme_test.dart` allows exactly the five seed lines in
  `lib/features/appearance/domain/app_palette.dart` and fails any other fixed colour, including any `Colors.*`, in
  `lib/`; it replaces "the teal seed is the one fixed colour" from the UI polish follow-ups.
- **ADR E1-7: the transition is `MaterialApp`'s existing theme cross-fade.** There is no custom colour animation. The
  existing 200 ms cross-fade shows in-between frames under normal motion and none when the system asks for reduced
  motion; both are tested.

## Post-submission enhancements E3 and E4: app icon and About

Added after E1, outside the milestones (plan: `docs/enhancement-phase-a-identity-about-implementation-plan.md`; rules:
`docs/assumptions.md`, "App icons (E3)", "App name and Web colours (E3)", "About (E4)"). E3 changes only platform
resources and names; E4 lives in the app shell next to `AppTitle` and `AppLogo`: `lib/app/app_info.dart` (`AppInfo`,
`appInfoFrom`, `appInfoProvider`) and `lib/app/about_dialog.dart` (`AboutButton`, `AboutAppDialog`).

- **ADR E3-1: one master, generated platform icons, no new dependency.** The owner's original artwork is committed
  unmodified under `tool/icon/` and every Android and Web icon is generated from it: `flutter_launcher_icons` 0.14.4 as a
  pinned global tool (so `pubspec.yaml` and `pubspec.lock` are unchanged) plus `tool/icon/maskable_icons.dart`
  (`dart:io` only) for the padded maskable icons. The generated files are committed; regenerating is three commands
  (`docs/testing.md`). The in-app `assets/app_icon.png` stays as it was.
- **ADR E3-2: safe zones are measured, not assumed.** The adaptive inset (17 %) is the smallest that keeps the bus, the
  Singapore Flyer and the pin inside Android's 66 dp safe zone with clearance; the maskable icons get their own padding
  (1.16×) so the same art stays inside the 40 % maskable safe zone, while the ordinary Web icons keep the whole artwork.
- **ADR E4-1: the version comes from Flutter's compiled-in build name and number, not `package_info_plus`.** Flutter
  3.47 exports `appBuildName`/`appBuildNumber`, which the flutter tool fills from pubspec `version` in `build`, `run`,
  `drive` and `test`: the same values as Android `versionName`/`versionCode` and Web `version.json`. Compared with the
  plugin (already a transitive dependency), this needs no direct dependency, no async call, no Web `version.json`
  request and no failure handling beyond "the build carried no version", which shows "Version unavailable".
- **ADR E4-2: a small custom `AlertDialog`, not `showAboutDialog`.** The standard dialog fixes the version line second
  and puts the icon beside the name; the approved reading order (name, description, author, version, actions) and a
  360 dp screen at 2× text need the icon above and the version last. It is still a plain dialog route (focus trap,
  Escape, Back, focus returning to the button), with Flutter's own licence page behind "View licenses".

## Dev tools (M0)

- `tool/` holds dev-only probes that are not part of the app: `probe_apis.sh` (curl),
  `api_probe_app.dart` (an alternative Flutter entry point for Chrome/Android), and
  `place_search_eval.dart` (Dart VM). M3 adds `build_mrt_asset.dart` (generates the bundled MRT asset) and
  `journey_smoke.dart` (a real-data planner check against live busrouter, with a raw-route cross-check).
  P2-M4 adds `map_performance_probe.dart` (journey-map frame timings, `flutter drive --profile`, Android only).
