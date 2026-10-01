# Singapore Smart Commute — Zero-Context Implementation Guide (v2)

**Version:** 2.1 (supersedes v1; v1 is preserved unchanged)\
**Revision date:** 2026-10-01 (2.1: scope clarifications approved for Milestone 0, see §0.1)\
**Project type:** University course project\
**Primary platform:** Flutter application for Android and Web\
**Geographic scope:** Singapore only\
**Architecture:** **Strictly front-end-only**, data-driven application with replaceable provider adapters\
**Implementation approach:** Incremental MVP followed by map enhancement

------------------------------------------------------------------------

## 0. Changes from v1 (summary)

| Area | v1 | v2 |
|---|---|---|
| Backend | Front-end-first; a "minimal credential proxy" was an allowed exception | **Front-end-only is absolute.** No backend, proxy, Worker, serverless/Firebase function, or other server-side component, as a fallback or otherwise |
| Secrets | `.env` + `.env.example` | **No secrets anywhere in the client.** `.env`, `--dart-define`, assets and source are all treated as public. Phase 1 needs no credentials |
| Provider selection | All "Verify / TBD" | Pre-selected from live probes run 2026-10-01 (§3), to be re-verified in Milestone 0 |
| LTA DataMall | Candidate | **Excluded from Phase 1** (AccountKey + no CORS preflight support) |
| OneMap | Search + routing candidates; proxy fallback | Tokenless **search only**, behind `PlaceSearchRepository`; **routing excluded**; **no proxy**; open-data fallbacks defined (§8) |
| Bus data | LTA or ArriveLah | busrouter static data (stops/services/route order) + ArriveLah (live arrival) |
| Journey scope | Transfers, multimodal legs | **Direct bus only (0 transfers)** + nearby MRT alternative (informational) |
| Walking time | "Prefer actual walking route" | **Labelled estimate** with a documented formula (§9.3) |
| Location | 10 s timeout from launch | Timeout starts **after permission resolves as granted**; denied/disabled → immediate fallback; **late fix never overwrites manual origin**; **SG boundary validation** |
| Air quality | "PSI", "PM2.5" | **24-hour PSI** (regional), **1-hour PM2.5** (regional), **national UV**, area-based 2-hr forecast — scopes explicit (§6) |
| Bus edge cases | Not covered | Loop services, repeated stops, one-direction services, same stop pair in both directions (§9.4) |
| State | Custom `LoadState` sealed class | Riverpod `AsyncValue` + typed `AppFailure` (no duplicate abstraction) |
| Milestone 0 | Starts with repo init | Starts with **`flutter doctor`** |
| Web deployment | — | **HTTPS required** for browser geolocation (localhost exempt) |

### 0.1 v2.1 scope clarifications (approved 2026-10-01)

1. **Temperature dropped** from Phase 1. The dashboard is the 2-hr forecast, UV, 1-hr PM2.5 and 24-hr PSI.
2. **MRT stays informational:** nearest station, its code/line if reliably available, and the estimated walk.
   MRT routing and direction are deferred.
3. **Manual bus-arrival refresh is required.** Automatic polling is optional and deferred.
4. **Offline cold start:** no persistent cache required. Show a clear *Network unavailable* state with
   *Retry*. Session (in-memory) caching is enough.
5. **Bus scoring weights and the 400 m → 800 m radii** stay as documented assumptions. Review them once
   working test journeys exist.
6. **Don't over-engineer the place-search fallback** before Milestone 0 has established feasibility. The
   composite order in §8.2 is the target design, not a Milestone 1 requirement. Implement only what the M0
   results justify.
7. **Integration tests added (user request, 2026-10-01):** a deterministic happy-path test and a
   fallback/error-path test, using fake providers and no live APIs (§18). Live API behaviour stays in the
   smoke tests.

------------------------------------------------------------------------

## 1. Mission

Build a Singapore-focused Flutter application that combines live environmental conditions with
public-transport first-leg guidance.

It answers two immediate questions:

1. **What are the conditions around me now?**
   - two-hour weather forecast for the user's area;
   - UV index (national);
   - 1-hour PM2.5 (regional);
   - 24-hour PSI (regional) and its official band;
   - data freshness / last-updated time.
2. **How should I start my journey to a destination?**
   - resolve the user's current position (or a manually chosen origin);
   - accept a destination in natural Singapore location terms;
   - recommend a **direct bus** option (stop + service + live ETA) where one exists;
   - show the nearest MRT station as an alternative;
   - explain the first steps clearly enough to act without another app.

This is a **course project**. Favour a demonstrable, maintainable architecture over production-scale
complexity.

------------------------------------------------------------------------

## 2. Non-Negotiable Constraints

- **Flutter / Dart**, one codebase running on **Android** and a **modern web browser**.
- **Singapore locations only.**
- **Front-end-only — no exceptions.** The app communicates directly with publicly accessible APIs and
  static data. Do **not** introduce any backend, API proxy, Cloudflare Worker, serverless function,
  Firebase/Supabase function, custom database, or any other server-side component — not for credential
  storage, not for CORS, not as a fallback.
- Consequently: **any provider that needs a confidential credential, or that does not permit browser
  (CORS) access, is out of scope for the Web build.** Design around it; never work around it with a server.
- **Everything shipped in the Web JS bundle or Android APK is publicly inspectable.** Never put a secret in
  source, assets, `.env` files, `--dart-define` values, or build config. Phase 1 must require **no
  credentials at all**.
- All external providers sit behind repository/service interfaces so a provider can be replaced without
  rewriting UI or domain logic.
- Do not invent bus arrival times, weather readings, routes, stops, or MRT recommendations.
- If live data is unavailable, show a clear degraded/error state.
- User-facing timestamps in Singapore time (UTC+08:00).
- WGS84 latitude/longitude internally.
- Keep Phase 1 small enough to complete, test and demonstrate before any map work.
- Respect each open provider's usage policy (rate limits, attribution, no bulk scraping).

------------------------------------------------------------------------

## 3. Provider Feasibility — Probe Results and Milestone 0 Re-verification

The following was verified with live HTTP requests (with a browser-style `Origin` header) on
**2026-10-01**. Milestone 0 must **re-run** these probes (curl + small Dart probes executed in Chrome and on
Android) and update `docs/api-feasibility.md`. Any change in outcome blocks feature work until resolved.

### 3.1 Probe matrix

| Capability | Provider / endpoint | Auth | Browser CORS | Observed 2026-10-01 | Phase 1 decision |
|---|---|---|---|---|---|
| 2-hour forecast | data.gov.sg `v2/real-time/api/two-hr-forecast` | None (optional `x-api-key`) | `ACAO: *` | 200; `area_metadata[]` with `label_location` | **Selected** |
| UV | data.gov.sg `v2/real-time/api/uv` | None | `ACAO: *` | 200; national hourly `index[]`, `updatedTimestamp` | **Selected** |
| PM2.5 | data.gov.sg `v2/real-time/api/pm25` | None | `ACAO: *` | 200; `regionMetadata` (5 regions) | **Selected** |
| PSI / haze | data.gov.sg `v2/real-time/api/psi` | None | `ACAO: *` | 200; includes `psi_twenty_four_hourly` per region | **Selected** |
| Bus stops | busrouter `data.busrouter.sg/v1/stops.min.json` | None | `ACAO: *` | 200; ~317 KB; `{code: [lng, lat, name, road]}` | **Selected (conditional on M0)** |
| Bus services + stop order | busrouter `data.busrouter.sg/v1/services.min.json` | None | `ACAO: *` | 200; ~255 KB; `routes` = ordered stop lists per direction | **Selected (conditional on M0)** |
| Route geometry | busrouter `data.busrouter.sg/v1/routes.min.json` | None | `ACAO: *` | 200; ~289 KB; encoded polylines | Phase 2 only |
| Live bus arrival | ArriveLah `arrivelah2.busrouter.sg/?id={stop}` | None | `ACAO: *` | 200; ISO `+08:00` times, `duration_ms`, load, feature, type | **Selected (conditional on M0)** |
| Place search | OneMap `api/common/elastic/search` | Docs say token; **results still returned without one**, with `"error": "Authentication token missing…"` | `ACAO: *` | 200; HDB postcodes resolved exactly | **Primary, at-risk** (§8) |
| Place search (fallback) | Photon `photon.komoot.io/api` | None | `ACAO: *` | 200; `bbox` restricts to SG; returns postcode, street; **fuzzy** (640512 → 640517) | **Fallback** (§8) |
| Place search / reverse (fallback) | Nominatim `nominatim.openstreetmap.org` | None | `ACAO: *` | 200; postcodes within ~10 m of OneMap for samples; reverse works | **Fallback, submit-only** (§8) |
| MRT stations / exits | data.gov.sg "LTA MRT Station Exit" GeoJSON (`d_b39d3a0871985372d7e1637193335da5`) | None | Download via poll-download → signed S3 URL | 200 | **Bundled static asset** (build-time) |
| Walking / PT routing | OneMap `api/public/routingsvc/route` | Token | `ACAO: *` | **401** | **Excluded** |
| Bus data (official) | LTA DataMall `ltaodataservice/v3/*` | AccountKey | **Preflight → 403** | Unusable from Flutter Web | **Excluded** |

### 3.2 Things Milestone 0 must still confirm

- data.gov.sg anonymous rate limits (no rate-limit headers were returned) and current terms (Singapore
  Open Data Licence).
- busrouter / ArriveLah: availability, licence of the repos (`github.com/cheeaun/busrouter-sg`,
  `github.com/cheeaun/arrivelah`), usage expectations, and that schemas match §3.1.
- OneMap: whether tokenless search still returns results, and its terms of use for unauthenticated calls.
- Photon and Nominatim public-instance usage policies (rate, autocomplete, identification, attribution).
- That every selected endpoint works from **Flutter Web in Chrome** *and* **Android** (a real run, not curl).

### 3.3 Architecture decision (to record in `docs/architecture.md`)

> The project is front-end-only by constraint. Every Phase 1 capability is served by a public, keyless,
> CORS-enabled endpoint or by static data bundled at build time. Capabilities that require confidential
> credentials or lack CORS support (LTA DataMall, OneMap routing) are excluded rather than proxied.

------------------------------------------------------------------------

## 4. MVP Scope

### Included

1. Startup location acquisition with permission handling.
2. Ten-second acquisition timeout (after permission granted).
3. Singapore boundary validation of GPS results.
4. Manual origin fallback.
5. Destination search.
6. Environmental dashboard for the user's area/region.
7. Nearby bus stops and nearest MRT station.
8. **Direct (zero-transfer) bus journey recommendation** where one exists.
9. Live bus arrival estimates for the recommended stop/service.
10. Loading, empty, permission-denied, offline, API-error and stale-data states.
11. Android and Web execution.
12. Unit/widget tests for important logic.

### Explicitly excluded from Phase 1

- any server-side component (permanent exclusion — not deferred);
- transfers / multi-leg bus or bus+MRT journeys;
- walking or public-transport routing APIs;
- LTA DataMall;
- live MRT arrivals (no public keyless source);
- interactive map, polylines, markers (Phase 2);
- accounts, history sync, push notifications, analytics.

------------------------------------------------------------------------

## 5. Target User Flow

### 5.1 App Launch

1. Render the app shell immediately; never block the whole screen on location.
2. Start environmental fetches that don't need location (all four data.gov.sg datasets are nationwide
   payloads — fetch them now and select the area/region once a position is known).
3. Check/request location permission.
4. **Permission outcome:**
   - **denied, permanently denied, or location service disabled → show manual origin immediately**
     (with a short reason and, where applicable, a "Open settings" action);
   - **granted → start the 10-second acquisition timeout** and request a position.
5. **Validate the position** (§5.2). An out-of-Singapore or invalid result counts as "unavailable".
6. On a valid position: select the forecast area / PSI & PM2.5 region, render the dashboard, and populate
   the origin field (reverse-geocoded label if available, otherwise "Current location").

### 5.2 Singapore boundary validation

- Reject coordinates that are non-finite or outside the Singapore bounding box:
  **latitude 1.15 – 1.48, longitude 103.60 – 104.10** (store as named constants; document in
  `docs/assumptions.md`).
- A bounding box is a deliberate simplification (it includes some sea and a sliver of Johor Strait). Record
  this; a polygon check is optional, not required.
- Note for testers: the **Android emulator's default location is outside Singapore** (Mountain View, US).
  Out-of-bounds → treated as unavailable → manual origin. Set an emulator location in Singapore for
  "GPS success" tests.

### 5.3 Location failure / manual origin

If permission is refused, the timeout expires, or the position is invalid/out-of-bounds, show:

**"We couldn't determine your location. Where are you now?"**

One search field accepting a 6-digit postal code, street/road, building, shopping mall, or landmark.
Placeholder: `e.g. 238801, Orchard Road, VivoCity, NUS`. Never ask for lat/lng. Results show enough detail
to disambiguate; the user explicitly selects one.

### 5.4 Late GPS results

- A position arriving after the fallback is shown **must never overwrite an origin the user has selected
  manually** (or is in the middle of typing).
- It may be offered non-intrusively, e.g. a "Use my current location" chip.
- If the user has not yet chosen anything, a valid late fix may populate the origin.
- The origin carries its provenance (`gps` | `manual`) so this rule is testable.

### 5.5 Destination

After origin is established: **"Where are you heading to today?"** Same input forms, same disambiguation
rule. Resolve the selected result to coordinates.

### 5.6 Journey result

Bus example:

> ~4 min walk (est.) to Bus Stop 09048 — Orchard Stn/Lucky Plaza\
> Take Bus 65 toward Tampines Int (12 stops)\
> Next buses: 3 min, 11 min, 18 min\
> Alight at 75009 — ~3 min walk (est.) to destination

MRT alternative example:

> Nearest MRT: Bishan (NS17 / CC15) — ~6 min walk (est.)

Include station code/line only if reliably available. No MRT direction in Phase 1 (§9.5). Never label an option
"best"; use "Suggested" and show the scoring rule in `docs/assumptions.md`.

------------------------------------------------------------------------

## 6. Environmental Dashboard

### 6.1 Metrics and spatial scope

| Metric | Field / dataset | Spatial scope | How the user's reading is chosen | Display |
|---|---|---|---|---|
| Weather | 2-hr forecast | **Area** (~47 named areas) | Nearest `area_metadata[].label_location` to the position | Icon + condition + area name |
| UV index | `uv` | **National** (single value) | Latest `index[]` entry | "UV 5 (Moderate) · Singapore" |
| PM2.5 | `pm25`, 1-hour reading | **Region** (north/south/east/west/central) | Nearest `regionMetadata[].labelLocation` (exclude "national") | "PM2.5 (1-hr) 18 µg/m³ · Central" |
| PSI | `psi` → **`psi_twenty_four_hourly`** | **Region** | Same region rule as PM2.5 | "24-hr PSI 54 (Moderate) · Central" |

Rules:

- **Always label PSI as "24-hr PSI" and PM2.5 as "1-hr PM2.5".** They are separate metrics and are never
  combined, substituted, or shown under the same label.
- Always show the scope used (area/region name or "Singapore").
- Plain-language bands only where they map to a **documented official NEA threshold** (24-hr PSI bands;
  1-hr PM2.5 bands; UV categories). Cite the source of each band table in `docs/data-sources.md`. If a band
  source can't be confirmed in M0, show the number without a band.
- **UV is only meaningful in daytime** (readings stop overnight). At night show the last reading with its
  time, or "UV not measured at night"; don't flag this as an error.
- No medical advice.

### 6.2 Domain model

```dart
enum SpatialScope { national, region, area, station }

class EnvironmentalReading<T> {
  final T value;
  final DateTime observedAt;   // from source, stored as UTC
  final DateTime fetchedAt;    // device time, UTC
  final String source;         // e.g. "data.gov.sg / NEA"
  final SpatialScope scope;
  final String scopeName;      // "Bishan", "central", "Singapore"
  bool isStale(DateTime nowUtc); // per-dataset threshold
}
```

Area/region selection lives in a pure domain service (`EnvironmentLocator`), independent of UI.

### 6.3 Staleness and time

- Per-dataset stale thresholds, documented in `docs/assumptions.md`. Suggested starting values: 2-hr forecast
  stale after 3 h of `valid_period`/update; PM2.5 & PSI after 2 h; UV after 2 h in daytime.
- "Updated X min ago" is computed from `observedAt`. If the device clock is behind the source (negative
  age), show "just now". Never show a negative age.
- Parse ISO-8601 timestamps with their `+08:00` offset, store UTC, and format for display at a fixed +08:00
  offset. Singapore has no DST, so the `timezone` package isn't needed.
- Stale data is shown **marked stale**, never replaced with fabricated values.

------------------------------------------------------------------------

## 7. Haze and Air-Quality Presentation

- Show 24-hr PSI and 1-hr PM2.5 **as separate tiles**, each with region and timestamp.
- Bands only from official NEA tables (see §6.1).
- Don't communicate the band by colour alone. Include the band text.
- Acceptable text: "24-hr PSI: Moderate". Not acceptable: advice such as "avoid going outside".

------------------------------------------------------------------------

## 8. Location Search and Geocoding (front-end-only)

### 8.1 Model and interface

```dart
enum PlaceType { postalCode, address, building, mall, poi, mrtStation, busStop, other }
enum PlaceSource { oneMap, photon, nominatim, bundled }

class Place {
  final String id;            // provider-scoped
  final String displayName;
  final String? address;
  final String? postalCode;
  final double latitude;
  final double longitude;
  final PlaceType type;
  final PlaceSource source;
}

abstract interface class PlaceSearchRepository {
  Future<List<Place>> search(String query, {required SearchMode mode}); // typeahead | submit
  Future<Place?> reverseGeocode(double latitude, double longitude);
}
```

### 8.2 Provider strategy

No provider here needs a credential. None needs a server.

1. **OneMap tokenless search (primary while it works).** It currently returns results along with an
   "Authentication token missing" message. That strongly suggests enforcement may arrive later. Treat
   these responses as failure, which triggers the fallback: a 401/403, or an `error` with empty `results`.
2. **Photon (OSM) — type-ahead fallback.** Use `bbox=103.6,1.15,104.1,1.48` and require
   `countrycode == "SG"`. Its matching is **fuzzy**, so for a 6-digit postal-code query, only accept results
   whose postcode **equals** the query. Otherwise show "No exact match for 640512".
3. **Nominatim (OSM) — submit-only and reverse-geocode fallback.** The public instance's policy forbids
   search-as-you-type and limits clients to **≤ 1 request/second**. Call it only on explicit submit and for
   reverse geocoding. Throttle client-side, cache results, send `countrycodes=sg`, and identify the app
   (Referer on Web, a descriptive User-Agent on Android).
4. **Bundled gazetteer — offline last resort.** A small static asset generated at build time from open
   data: MRT stations (from the LTA MRT Station Exit dataset) plus a short, hand-curated list of major
   malls, universities and landmarks. Matching runs locally. Record the licence (SODL / ODbL) in
   `docs/data-sources.md`.

**Target design, not a Milestone 1 requirement (§0.1 item 6).** Implement only the providers that the
Milestone 0 place-search evaluation justifies. Add fallbacks when a demonstrated need appears.

A `CompositePlaceSearchRepository` applies this order. It records which provider answered, and the UI shows
the matching attribution ("© OpenStreetMap contributors" / "OneMap"). Every provider is individually
replaceable.

Explicitly **not** used: Google Places, Mapbox, Geoapify, LocationIQ, HERE, and similar keyed services. A
client-side key would be shipped publicly, which conflicts with §2.

### 8.3 Search requirements

- Debounce type-ahead (≈ 300–400 ms). Minimum 3 characters, except a valid 6-digit postal code.
- Postal-code validation: exactly 6 digits, leading zero allowed (e.g. `098585`). The value is a string,
  never an int.
- Cancel or ignore obsolete responses (sequence token).
- Rank results but let the user choose. Show road + postcode to disambiguate duplicates.
- Drop results outside the SG bounding box. Validate coordinate ranges.
- Never auto-select an ambiguous result. A single exact postal-code match may be pre-highlighted, but the
  user still confirms it.
- Short in-memory cache per normalised query.

------------------------------------------------------------------------

## 9. Transport Recommendation (Phase 1: direct bus + MRT alternative)

### 9.1 Data

- `stops.min.json`: stop code → `[lng, lat, name, road]`. **Note the order is lng, lat.**
- `services.min.json`: service → `{ name, routes: [[stopCodes…], [stopCodes…]?] }`. There is one or two
  ordered stop lists, one per direction.
- Load both lazily on the first journey request and cache them for the session (~570 KB). On Web, the
  browser HTTP cache can also be used. No live calls are made during the candidate search.

### 9.2 Algorithm (deterministic, zero transfers)

1. **Origin candidates:** stops within `R_o` (default 400 m, configurable) of origin, by haversine. If
   none, widen once to 800 m, then report `RouteNotFound("No bus stop nearby")`.
2. **Destination candidates:** stops within `R_d` (default 400 m → 800 m) of destination.
3. **Direct matches:** for each service and each direction's stop list, find pairs (o, d) where o is an
   origin candidate, d is a destination candidate, and **index(o) < index(d)** in that same list (§9.4).
4. For each match compute:
   - `walkO` = estimated walk time origin → o (§9.3);
   - `walkD` = estimated walk time d → destination;
   - `stops` = index(d) − index(o) (in-vehicle proxy);
5. **Score** (lower is better, documented in `docs/assumptions.md`):
   `score = walkO_min + walkD_min + 1.5 × stops`. Tie-break by fewer stops, then by service number.
   These weights, and the 400 m → 800 m radii, are **documented assumptions**. Review them after working
   test journeys exist (§0.1 item 5).
6. Keep the best match per service. Keep the top 3 overall.
7. **Only then** fetch live arrivals (ArriveLah) for the ≤ 3 chosen origin stops. Never fetch arrivals
   for every candidate.
8. Show one "Suggested" option plus up to 2 alternatives. If no direct match: `RouteNotFound` ("No direct
   bus found") and show the MRT alternative.
9. If origin and destination are within ~300 m, suggest walking (est.) instead of a bus.

### 9.3 Walking estimate (no routing API in Phase 1)

```
distance_m = haversine(a, b)
walk_m     = distance_m × 1.3        // detour factor for street network
walk_min   = ceil(walk_m / 80)       // 80 m/min ≈ 4.8 km/h
```

- Always display as `~N min walk (est.)`. It's an estimate, not a route.
- Record the formula, the 1.3 detour factor and the 80 m/min speed in `docs/assumptions.md`. Note what it
  can't see: overhead bridges, barriers, expressways and rivers can make the real walk much longer.

### 9.4 Bus-route edge cases (must be handled and unit-tested)

- **Loop services.** The start/end interchange appears at both ends of one stop list, and other stops
  may repeat. Use the **first occurrence of o** followed by the **first occurrence of d after it**. Never
  match d before o.
- **Repeated stops within a direction.** A stop may appear more than once. Evaluate every valid (o, d)
  occurrence pair with o before d, and keep the smallest `stops` value.
- **One-direction services.** `routes` holds a single list. Don't assume a second direction exists.
- **Same stop pair served in both directions.** Choose only the direction where o precedes d. If both
  directions qualify (loops), keep the one with fewer stops.
- **Opposite-side stops.** Stops across the road from each other have different codes, and only one of
  them serves the required direction. The index rule handles this automatically. Test that the wrong-side
  stop is not recommended.
- **Origin stop == destination stop**, or o and d both within the same candidate set → skip that pair.
- **Destination label.** "Toward X" is the last stop name of that direction's list (or the service `name`),
  never guessed.

### 9.5 MRT alternative

- Source: the bundled MRT station asset, built from the LTA MRT Station Exit GeoJSON. Use the nearest
  station (by its nearest exit) to the origin, plus the nearest station to the destination.
- Phase 1 is **informational only**: station name and estimated walk, plus station code/line **only** if
  a bundled, cited code/line table is reliably available.
- MRT routing and direction ("toward …") are **deferred** beyond Phase 1.
- Never show live MRT arrival times.

------------------------------------------------------------------------

## 10. Bus Arrival (ArriveLah adapter)

```dart
class BusArrival {
  final String serviceNo;
  final String busStopCode;
  final DateTime? estimatedArrival; // UTC; null if absent
  final BusLoad? load;              // SEA / SDA / LSD → seats / standing / limited
  final bool? wheelchairAccessible; // feature == "WAB"
  final String source;              // "ArriveLah"
}
```

- UI formats ETA as `Arr` (≤ 0–1 min), `N min`. The timestamp stays in the domain layer.
- Missing arrival → `No live arrival available`. Never show 0 min or a fabricated value.
- Refresh: a **manual refresh button is required**. Cache for ≤ 20 s. Automatic polling (30–60 s while
  visible, stopping when off-screen) is **optional and deferred**.
- Treat ArriveLah as a replaceable adapter (`BusArrivalRepository`). Its upstream is LTA via a community
  project, so it has no SLA. Show the source.

------------------------------------------------------------------------

## 11. Flutter Architecture

Pragmatic feature-first layout. Skip any layer that would contain no logic.

```text
lib/
  app/            app.dart, router.dart, theme.dart
  core/
    config/       non-secret config only (endpoints, radii, thresholds)
    errors/       AppFailure hierarchy
    http/         client, timeout, bounded retry, request dedup
    location/     permission + acquisition + SG bounds validation
    geo/          haversine, walking estimate, bounding box
    time/         SGT formatting, staleness, injectable Clock
    widgets/
  features/
    environment/  data (data.gov.sg DTOs/adapters) · domain (models, EnvironmentLocator) · presentation
    places/       data (OneMap, Photon, Nominatim, bundled) · domain (Place, Composite repo) · presentation
    journey/      data (busrouter static loader, MRT asset) · domain (DirectBusPlanner, scoring) · presentation
    bus_arrival/  data (ArriveLah) · domain · presentation
assets/
  mrt_stations.json   generated from open data, with source + licence noted
  gazetteer.json      small curated landmarks list
main.dart
```

Package selection: check current compatibility, and add nothing just for popularity. Likely: Riverpod,
`http` or Dio, `geolocator`, and `fake_async` (dev, for timeout tests). No map packages in Phase 1.

------------------------------------------------------------------------

## 12. State Management

- Use **Riverpod**, with `AsyncValue<T>` for asynchronous state. **Do not create a parallel generic
  `LoadState` type.**
- Errors carried in `AsyncValue.error` must be typed `AppFailure`s (§13), so widgets can switch on them.
- Inject `Clock` / timeout durations through providers, so tests can drive time deterministically.
- DTOs never reach widgets. Widgets consume domain/view models.

------------------------------------------------------------------------

## 13. Error Model

```text
LocationPermissionDenied
LocationPermissionPermanentlyDenied
LocationServiceDisabled
LocationTimeout
LocationOutsideSingapore
NetworkUnavailable
ApiRateLimited
ApiUnauthorized           // e.g. OneMap starts enforcing tokens → trigger fallback provider
ApiUnavailable
InvalidApiResponse
PlaceNotFound
NoExactPostalMatch
RouteNotFound             // includes "no nearby stop" / "no direct bus"
BusArrivalUnavailable
StaticDataUnavailable     // busrouter JSON failed to load
```

Every user-visible error has a friendly message, a retry action where useful, and a manual fallback where
possible. Technical detail is logged in debug mode only.

------------------------------------------------------------------------

## 14. Security and Privacy Rules

- The client holds **no secrets**, and Phase 1 uses no credentials.
- **Don't use `.env` files, `flutter_dotenv`, `--dart-define`, assets or source for anything confidential.**
  All of these end up in the shipped bundle.
- Non-secret configuration (endpoint URLs, radii, thresholds) lives in Dart constants in `core/config/`.
- If an optional data.gov.sg API key is ever used, treat it as **public** and document it that way. The app
  must work without it.
- Never disable TLS validation. Don't log precise user coordinates outside debug builds.
- If a provider later requires a confidential credential, it **leaves scope** (use another adapter). It is
  not proxied.
- Document in the README that evaluators need **no credentials**.

------------------------------------------------------------------------

## 15. Caching and API Efficiency

| Data | Policy |
|---|---|
| busrouter stops/services | Load once per session (lazy); in-memory |
| data.gov.sg datasets | One fetch per dataset; refetch when stale or on pull-to-refresh; never per widget |
| Place search | Short in-memory cache by normalised query; debounce; Nominatim ≤ 1 req/s, submit-only |
| Bus arrival | ≤ 20 s cache; only for ≤ 3 shortlisted stops |

Caching is **session-only** (in memory). Nothing persists across launches. On an offline cold start, show
a clear *Network unavailable* state with *Retry*. No persistent offline cache is required in Phase 1.

Deduplicate concurrent identical requests. Request timeout ≈ 10 s. Bounded retry (max 2, with backoff) for
network errors and 5xx only. Never retry 4xx blindly. On 429, respect `Retry-After` if present.

------------------------------------------------------------------------

## 16. UX Requirements

### Home screen hierarchy (information order, not a visual spec)

```text
┌──────────────────────────────────┐
│ Singapore Smart Commute          │
│ Cloudy · Bishan                  │
│ UV 5 (SG) · 24-hr PSI 54 (Central)│
│ 1-hr PM2.5 18 (Central)          │
│ Updated 4 min ago                │
├──────────────────────────────────┤
│ From: Current location ▾         │
│ Where are you heading today?     │
├──────────────────────────────────┤
│ Suggested journey                │
│ ~4 min walk (est.) → Stop 09048  │
│ Bus 65 · 3 min / 11 min          │
│ Nearest MRT: Bishan · ~6 min est.│
├──────────────────────────────────┤
│ Data: NEA/data.gov.sg · OneMap/  │
│ © OSM · busrouter · ArriveLah    │
└──────────────────────────────────┘
```

### Accessibility

Adequate touch targets. Semantic labels. Readable contrast. Never use colour alone for bands or bus load.
Scalable text. Loading indicators with semantics. Keyboard-friendly web search.

### Web deployment

**Browser geolocation requires a secure context (HTTPS).** `localhost` is exempt during development. Any
hosted demo must be served over HTTPS (static hosting only, e.g. GitHub Pages, which is not a backend).
Note this in the README.

------------------------------------------------------------------------

## 17. Phase 2 — Map Component

Only start after Phase 1's Definition of Done passes.

- Basemap: OneMap basemap tiles if they're still tokenless and the terms allow it, or OSM-based tiles in
  line with the chosen tile provider's usage policy. Verify both in a Phase 2 spike.
- Markers for origin, destination, recommended stop, and MRT station.
- Bus route geometry from busrouter `routes.min.json` (encoded polylines).
- Walking-route geometry **only** if a keyless, CORS-enabled routing provider is found and its policy allows
  client use. Otherwise keep straight-line "est." connectors. The public OSRM demo server is not intended
  for app traffic, so evaluate it as a spike only.
- Keep the map behind an abstraction. The planner must not depend on map widgets.

------------------------------------------------------------------------

## 18. Testing Strategy

### Unit tests

- Haversine and walking estimate (formula and rounding).
- **SG bounding box** (inside, outside, emulator default, NaN).
- Postal-code validation (leading zero, 5/7 digits, non-digits).
- Nearest forecast area / PSI region selection.
- DTO → domain mapping per provider, including **lng/lat order** in busrouter stops.
- Staleness and clock-skew handling. SGT formatting.
- ETA formatting (`Arr`, `N min`, missing → unavailable).
- Direct-bus planner: basic match; **loop service; repeated stop; one-direction service; same pair in both
  directions; wrong-side stop; origin == destination stop**; no match → `RouteNotFound`.
- Scoring and tie-breaks.
- Photon postcode exact-match filter (`640512` must not resolve to `640517`).
- Composite place search fallback order (OneMap failure → Photon → Nominatim on submit → bundled).

### Repository tests (mock HTTP)

Success, malformed payload, timeout, 401/403, 429, 5xx, empty results, stale data. Also OneMap's
"error + results" and "error + no results" variants.

### Widget tests

- Initial loading.
- Environmental card with scope labels.
- **Permission denied → immediate fallback.**
- **Granted → 10 s timeout → fallback** (driven by `fake_async`).
- **Late GPS fix does not overwrite a manual origin.**
- **Out-of-SG fix → fallback.**
- Origin/destination search, ambiguous results.
- Journey result, bus arrival display, "No live arrival available", retry state.

### Integration tests (`integration_test/`, deterministic, no live APIs)

These tests run the **real app end to end on a device or browser**. Every external provider is replaced with
a controlled fake through the repository interfaces (Riverpod provider overrides). They inject location,
place search, environment, bus data and bus arrival. **They must never call live external APIs.** Live API
behaviour stays covered by the smoke tests below.

Phase 1 minimum:

1. **Happy path:** fake GPS inside Singapore → dashboard shows the fake forecast/UV/PM2.5/PSI with scope
   labels → the user searches for and selects a destination → a direct-bus suggestion appears with stop,
   service and fake ETA → manual refresh updates the ETA.
2. **Fallback/error path:** permission denied (or a fake fix outside Singapore) → the manual origin prompt
   appears immediately → the user selects an origin → a provider fails (e.g. bus arrival throws
   `NetworkUnavailable`) → a clear error state with Retry, and no fabricated ETA. Retry with a recovered fake
   succeeds.

Rules:
- Time is controlled. The 10 s timeout uses the injected clock/duration, so tests never sleep in real time.
- Fakes live under `integration_test/fakes/` (or `test/fakes/`, shared with widget tests). They return fixed
  domain objects, with no HTTP.
- Run on Android with `flutter test integration_test -d <device>`. Run on Web with `flutter drive
  --driver=test_driver/integration_test.dart --target=integration_test/<file>.dart -d chrome`, which needs a
  matching `chromedriver` on port 4444.
- Milestone 0 sets up the harness (one boot test). The two tests above are written in the milestone that first
  delivers their features: happy path built up across M1–M4, fallback path in M1 with error states extended in
  M4. They must pass before Phase 1 is complete.

### Smoke tests (manual, documented in `docs/testing.md`)

1. Chrome (localhost).
2. Android emulator with a Singapore location set.
3. Emulator with its default (non-SG) location.
4. GPS denied.
5. GPS timeout.
6. Postal-code origin.
7. Mall destination.
8. Direct bus journey with live ETA.
9. Journey with no direct bus.
10. A provider unavailable (simulated offline).

------------------------------------------------------------------------

## 19. Quality Gates

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
flutter test integration_test -d <android-device>   # from Milestone 1; Web via flutter drive (§18)
```

Fix real warnings; don't suppress lints to go green. Never report a gate as passing unless it actually ran
successfully.

------------------------------------------------------------------------

## 20. Required Documentation

```text
README.md
docs/
  api-feasibility.md   probe commands + dated results (§3)
  architecture.md      incl. the front-end-only decision (§3.3)
  data-sources.md      owner, endpoint, data used, auth (none), cadence, licence/attribution, limits, fallback
  assumptions.md       bounds box, walking formula, scoring weights, stale thresholds, radii, band tables
  testing.md
```

The README covers: purpose, screenshots, prerequisites, Flutter version, setup, **"no credentials
required"**, running on Web (HTTPS note) and Android (emulator location note), tests, known limitations
(estimates, third-party dependencies), and the Phase 2 roadmap.

------------------------------------------------------------------------

## 21. Milestones

### Milestone 0 — Environment and feasibility (no features)

1. **`flutter doctor`**: Flutter, Chrome, Android SDK and licences, emulator. Record the output.
2. Initialise the repository (on a feature branch, merged via PR).
3. `flutter create` for Android and Web; confirm a blank app runs on both.
4. Re-run every probe in §3.1 as curl **and** as a small Dart probe run in Chrome and on Android.
5. Complete `docs/api-feasibility.md`, `docs/data-sources.md`, and the architecture decision.
6. Generate and commit the bundled MRT station asset with its source and licence noted (or record why it's
   deferred).
7. README setup instructions. Pass the quality gates.

**Stop and report. No feature work until reviewed.**

### Milestone 1 — Location and environment
Permission flow, SG bounds, timeout/fallback, late-fix rule, the four NEA datasets, scope selection, dashboard.

### Milestone 2 — Places
Composite search (OneMap → Photon → Nominatim → bundled), disambiguation, reverse geocode, attribution.

### Milestone 3 — Direct bus planner and MRT alternative
Static data loader, planner and edge cases, scoring, walking estimate, MRT alternative.

### Milestone 4 — Live bus arrival
ArriveLah adapter, ETA formatting, refresh, unavailable state.

### Milestone 5 — Hardening
Tests, Web/Android QA, error states, caching, accessibility, docs.

### Milestone 6 — Map (Phase 2)

Each milestone is one reviewable PR.

------------------------------------------------------------------------

## 22. Definition of Done — Phase 1

- [ ] Runs in Chrome and on an Android emulator/device.
- [ ] The app contains **no backend/proxy and no secrets**. It needs no credentials.
- [ ] Permission denied/disabled → manual origin immediately.
- [ ] Granted but no fix within ~10 s → manual origin.
- [ ] Out-of-Singapore fix → manual origin.
- [ ] A late fix never overwrites a manual origin.
- [ ] Origin and destination accept postal code, street, building, mall and POI, with explicit selection.
- [ ] Dashboard shows forecast (area), UV (national), 1-hr PM2.5 and 24-hr PSI (region), each with
      scope and timestamp. PSI and PM2.5 are never confused.
- [ ] Direct-bus recommendation, where one exists, shows stop code/name, service, direction and estimated
      walks.
- [ ] Live ETA shown when available. Missing ETA is never fabricated.
- [ ] No direct bus → clear message plus MRT alternative.
- [ ] Walking times are labelled as estimates. The formula is documented.
- [ ] Attribution shown for every data source.
- [ ] Error, offline, empty and stale states are usable.
- [ ] Integration tests (happy path + fallback/error path, fake providers, no live APIs) pass on Android
      and Web.
- [ ] Quality gates pass (actually executed).
- [ ] A zero-context developer can reproduce the project from the README.

------------------------------------------------------------------------

## 23. Instructions to the Coding Agent

1. Inspect before changing (README, docs, `pubspec.yaml`, tests).
2. Use the applicable coding, review and testing skills.
3. Don't assume an API still behaves as described. Re-probe in M0.
4. Prefer official Singapore government data, within the front-end-only constraint.
5. **Never introduce a server-side component or embed a secret to make a feature work.** If a feature
   can't be done front-end-only, report it and propose a scope change.
6. Keep providers replaceable. Implement one milestone at a time.
7. After each milestone: format, analyse, test, build affected targets, and report exactly what changed and what remains.
8. Don't broaden scope silently. Don't start Phase 2 before Phase 1 is stable.
9. Record ambiguity resolutions in `docs/assumptions.md`.
10. Never claim a command passed unless it ran successfully.
11. Small descriptive commits on a feature branch. Never commit or push to `main`. Merge via PR. No
    force-push or history rewrites.

------------------------------------------------------------------------

## 24. Open Risks and Assumptions

| # | Risk / assumption | Impact | Mitigation |
|---|---|---|---|
| R1 | OneMap starts enforcing tokens on search | Primary geocoder lost | Composite fallback to Photon/Nominatim/bundled (§8.2) |
| R2 | busrouter / ArriveLah unavailable or changed (community project, no SLA) | No bus planning / ETA | Adapter interfaces; clear degraded state; MRT alternative still works. No official keyless substitute exists, so this is accepted |
| R3 | Photon/Nominatim public fair-use limits or blocking | Fallback degraded | Debounce, submit-only Nominatim, caching, attribution |
| R4 | OSM postcode coverage is incomplete for some addresses | "No exact match" | Exact-match rule; user can search by street/building instead |
| R5 | Official NEA band tables for 1-hr PM2.5 / UV not confirmable in M0 | No band text | Show the number only |
| R6 | MRT code/line data has no clean open source | No code/line shown | Show station + walk only (direction is deferred anyway) |
| R7 | Walking estimate understates real walks | Misleading times | "(est.)" label, documented formula, Phase 2 spike |
| R8 | data.gov.sg anonymous rate limits | Throttling under testing | One fetch per dataset, caching |
| R9 | Bounding box includes small non-SG areas | Rare false accept | Documented simplification |

------------------------------------------------------------------------

## 25. References (re-verify in Milestone 0)

- data.gov.sg real-time APIs: https://guide.data.gov.sg/developer-guide/real-time-apis
- data.gov.sg endpoints: `https://api-open.data.gov.sg/v2/real-time/api/{two-hr-forecast,uv,pm25,psi}`
- LTA MRT Station Exit dataset: https://data.gov.sg/datasets/d_b39d3a0871985372d7e1637193335da5/view
- OneMap API docs: https://www.onemap.gov.sg/apidocs/
- busrouter.sg: https://busrouter.sg · data: `https://data.busrouter.sg/v1/` · source: https://github.com/cheeaun/busrouter-sg
- ArriveLah: https://arrivelah2.busrouter.sg · source: https://github.com/cheeaun/arrivelah
- Photon: https://photon.komoot.io · https://github.com/komoot/photon
- Nominatim usage policy: https://operations.osmfoundation.org/policies/nominatim/
- OSM copyright/attribution: https://www.openstreetmap.org/copyright
- LTA DataMall (excluded, for reference): https://datamall.lta.gov.sg/

------------------------------------------------------------------------

## 26. Design Principle

The app should be useful before the map exists. Phase 1 already answers:

**"What is it like outside, where am I going, where should I walk first, which bus can take me there
directly, and when is it arriving?"**

The Phase 2 map makes that answer easier to see. It must not be required to make the answer correct.

------------------------------------------------------------------------

