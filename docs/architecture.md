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
  app/            app shell, router, theme
  core/           config (non-secret constants), errors (AppFailure), http, location, geo, time
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
  to their own limiters), `ui/status_rows.dart` (shared `BusyRow` / `ErrorRetryRow`),
  `location/` (`LocationService` seam + geolocator adapter).
- `lib/features/origin/`: `OriginController` (Riverpod `Notifier`) is the permission → timeout → fallback →
  late-fix state machine. `Origin` carries provenance (`gps` | `manual`). `OriginCard` is the UI. Each
  acquisition attempt has an id, so a superseded attempt's results are dropped. No attempt replaces a manual
  origin: only `useCurrentLocation()` (the "Use my current location" chip) does that.
- `lib/features/environment/`: `data/` (data.gov.sg parsers + repository), `domain/` (models,
  `EnvironmentLocator`, band tables), `environment_providers.dart` (one session-cached `FutureProvider` per
  dataset, refresh cooldown), `presentation/` (dashboard tiles, display strings).
- Seams overridden in tests: `locationServiceProvider`, `locationTimeoutProvider`, `environmentRepositoryProvider`,
  `httpClientProvider` (the rate-limit widget tests swap only the transport for a fake data.gov.sg),
  `clockProvider`, `placeSearchRepositoryProvider`. Fakes are in `test/fakes/` and shared with `integration_test/`.

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
  the origin) and `DestinationCard` ("Where are you heading to today?", shown once an origin exists).
- OneMap calls go through the generic `JsonHttpClient` (timeout, retry, 401/403, 429) with a shared `OneMapRateLimit`
  limiter (1 request per 1 s, FIFO, retries included), on top of the debounce and the bounded cache. Photon / Nominatim / bundled fallbacks are not built (guide §0.1 item 6).
- `ProviderScope(retry: noAutomaticRetry)`: Riverpod 3's automatic retry is off (rate limits; explicit Retry).
- Dependencies added: `flutter_riverpod` 3.4.3, `geolocator` 14.1.1, `fake_async` (dev).

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

## Dev tools (M0)

- `tool/` holds dev-only probes that are not part of the app: `probe_apis.sh` (curl),
  `api_probe_app.dart` (an alternative Flutter entry point for Chrome/Android), and
  `place_search_eval.dart` (Dart VM). M3 adds `build_mrt_asset.dart` (generates the bundled MRT asset) and
  `journey_smoke.dart` (a real-data planner check against live busrouter, with a raw-route cross-check).
