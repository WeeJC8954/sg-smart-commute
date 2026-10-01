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
- data.gov.sg anonymous limit: 6 real-time calls per 10 s. Requests are session-cached and deduplicated.

## Layering (target for Milestone 1+)

Feature-first, with a pragmatic clean architecture (guide §11):

```text
lib/
  app/            app shell, router, theme
  core/           config (non-secret constants), errors (AppFailure), http, location, geo, time
  features/
    environment/  data.gov.sg adapters → EnvironmentLocator → dashboard
    places/       PlaceSearchRepository (OneMap adapter + normaliser)
    journey/      busrouter loader, DirectBusPlanner, MRT asset
    bus_arrival/  BusArrivalRepository (ArriveLah)
```

- State: Riverpod `AsyncValue<T>` with typed `AppFailure`. There is no custom `LoadState`.
- DTOs stay in `data/`. Widgets consume domain models only.
- Time: parse ISO `+08:00`, store UTC, display at a fixed +08:00 offset (no `timezone` package).

## Milestone 0 skeleton

- `lib/main.dart` is a placeholder shell, with no features yet.
- `tool/` holds dev-only probes that are not part of the app: `probe_apis.sh` (curl),
  `api_probe_app.dart` (an alternative Flutter entry point for Chrome/Android), and
  `place_search_eval.dart` (Dart VM).
- Dependencies: `http`. Others (Riverpod, geolocator, fake_async) are added in the milestone that first
  needs them.
