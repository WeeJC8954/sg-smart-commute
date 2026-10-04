# Data Sources

All Phase 1 sources are keyless and called directly from the client. Verification:
[`api-feasibility.md`](api-feasibility.md) (2026-10-01).

Every response passes through `JsonHttpClient`, which caps a body at 4 MiB (M5; the largest real one is
busrouter `stops.min.json`, ~317 KB) and enforces the timeouts, retries and rate limits in
`docs/assumptions.md`. On Web, the Content-Security-Policy in `web/index.html` lists exactly these hosts in
`connect-src`, plus the Flutter engine CDN below.

## data.gov.sg / NEA real-time APIs

| | |
|---|---|
| Owner | GovTech (data.gov.sg), data from NEA |
| Endpoints | `https://api-open.data.gov.sg/v2/real-time/api/two-hr-forecast`, `/uv`, `/pm25`, `/psi` |
| Data used | 2-hr forecast per area (`area_metadata[].label_location`, ~47 areas); UV index (national, hourly, daytime); 1-hr PM2.5 per region (5 regions, `regionMetadata`); `psi_twenty_four_hourly` per region |
| Auth | None. An optional API key exists for higher limits. It is not used, and it would be public if it ever were |
| Update cadence | Forecast: 2-hr validity window, update time in the payload; UV, PM2.5 and PSI: hourly readings (`updatedTimestamp` in the payload) |
| Limits | Anonymous: **6 real-time calls per 10 s** → `429` ([guide](https://guide.data.gov.sg/developer-guide/api-overview/api-rate-limits)) |
| Licence / attribution | Singapore Open Data Licence. Attribute "Source: NEA / data.gov.sg" |
| Limitations | Readings are national, regional or area-based, never point-based. UV is not measured at night |
| Fallback | Show the stale reading with its timestamp, or an unavailable state with Retry. Values are never fabricated |
| Fields used (M1, confirmed against live payloads 2026-10-01, `test/fixtures/`) | Forecast `items[].forecasts[]` + `update_timestamp` + `valid_period`; UV latest `records[].index[]` entry by `hour`; PM2.5 `items[].readings.pm25_one_hourly`; PSI `items[].readings.psi_twenty_four_hourly` only. The PSI payload also carries `pm25_twenty_four_hourly` and sub-indices: these are never used |
| Band sources | 24-hr PSI descriptors and 1-hr PM2.5 bands: NEA haze portal, https://www.haze.gov.sg/. UV categories: NEA, https://www.nea.gov.sg/weather/ultraviolet-index. Checked 2026-10-01; values in `assumptions.md` |

## busrouter static data

| | |
|---|---|
| Owner | busrouter.sg (community project by Lim Chee Aun, `github.com/cheeaun/busrouter-sg`), derived from LTA data |
| Endpoints | `https://data.busrouter.sg/v1/stops.min.json` (~317 KB), `services.min.json` (~255 KB); `https://data.busrouter.sg/v1/routes.min.json` (~289 KB; the ride line, P2-M2, see below) |
| Data used (M3) | Stops `{code: [lng, lat, name, road]}` (**lng first**; converted to latitude-first once, in `busrouter_parser.dart`). Services `{number: {name, routes: [[codes], [codes]?]}}`: one list per direction, in stop order. On 2026-10-01: 5,208 stops, 602 services (406 one-direction, 222 loops with first == last stop) |
| Data used (P2-M2) | `routes.min.json`: `{service: [encoded polyline dir 0, dir 1?]}`, one Google-encoded polyline (precision 5) per busrouter direction, 602 services / 798 directions on 2026-10-03 (the same direction order as `services.min.json`; geometry only, no stop indices, so the app matches the ride's stops to the line: `docs/map-feasibility.md` §5). Parsed only in `features/map/data/busrouter_routes_parser.dart`; polylines are decoded only for the ride being drawn. Used **only by the map, lazily**: requested after "Show map" with a direct-bus journey, once per session. A failure (network, HTTP, 429, too large, not JSON, schema) gives markers only plus a note; planning and arrivals are unaffected |
| Auth | None. HTTP 200, CORS `*`, `Cache-Control: public,max-age=86400` (the same for `routes.min.json`) |
| Update cadence | Static; refreshed by the project periodically |
| Licence / attribution | The busrouter README says the data is "© LTA", mostly scraped from lta.gov.sg (via `cheeaun/sgbusdata`); the code is MIT. The app shows "Bus data: busrouter.sg (data © LTA)". Suitable for this course project; re-check before any wider release |
| Caching | Loaded lazily on the first journey request, once per session (see `docs/assumptions.md`) |
| Limitations | No SLA, and the schema could change without notice. Stop 46239 Larkin Ter is in Johor Bahru |
| Fallback | `StaticDataUnavailable` → the journey card shows "Bus data is unavailable right now." with Retry, plus the MRT alternative. Nothing is fabricated |

## ArriveLah

| | |
|---|---|
| Owner | Community project by Lim Chee Aun (`github.com/cheeaun/arrivelah`), hosted on Vercel. Its source (`api/arrival.js`, read 2026-10-02) calls **LTA DataMall v3 BusArrival** with the project's own keys and reshapes the answer. It is **not an official LTA API** and has **no SLA** |
| Endpoint | `GET https://arrivelah2.busrouter.sg/?id={busStopCode}`: one request per stop, listing every service calling there |
| Auth / CORS | None (no key, no token). `Access-Control-Allow-Origin: *`, `Access-Control-Allow-Headers: *` on GET and preflight (curl, 2026-10-02 03:01 UTC). Real Chrome: a page on `http://localhost:8765` fetched and read the JSON (2026-10-02 03:03 UTC). Android: the release APK on the emulator (see `testing.md`) |
| Response (observed 2026-10-02) | `{"services": [{"no", "operator", "next", "subsequent", "next2", "next3"}]}`. Each slot is `null` (no estimate) or `{"time", "duration_ms", "lat", "lng", "load", "feature", "type", "visit_number", "origin_code", "destination_code", "monitored"}`. `subsequent` is a legacy copy of `next2` |
| Fields used | `no` (service number, string, e.g. `10`, `196A`), slot `time` (ISO-8601 with `+08:00`; parsed with its own offset and stored in UTC), `load` (`SEA` seats / `SDA` standing / `LSD` limited standing), `feature` (`WAB` = wheelchair-accessible, empty = not marked), `type` (`SD` / `DD` / `BD`), `monitored` (1 = from the bus's live position, 0 = schedule-based; 65 of 141 buses sampled were 0, all with lat/lng 0), `visit_number` (2 = a loop bus's second visit) |
| Not used | `duration_ms`: computed when the response was made, and the response is cached for 15 s, so it goes stale. The ETA is `time` minus the app clock. Also unused: `lat`/`lng`, `operator`, `origin_code`, `destination_code` |
| Failure / empty bodies (all HTTP 200) | Unknown stop (`?id=99999`) → `{"services":[]}`. Malformed id (`?id=abc`) → `{"error":"Failed to retrieve bus data.","statusCode":500}`. Missing id → an instruction object with no `services`. Upstream exception → `{"error": …}` |
| Caching / rate limit | Responses carry `Cache-Control: max-age=15` (`s-maxage=15` at Vercel's edge). 20 requests for 10 different stops within ~3 s all returned 200, with no rate-limit or `Retry-After` headers. **No published limit**; none is assumed |
| Licence / provenance / attribution | ArriveLah is a **third-party community service**: a proxy of **LTA DataMall** bus-arrival data, run by an individual developer, not by LTA or by this project. **Its repository currently has no explicit licence file** (GitHub `license: null`, checked 2026-10-02), and its README states no terms of use. This project does **not** assign, assume or imply any licence for ArriveLah or its code. **Availability and usage rights are not guaranteed**: the service can change, rate-limit or stop without notice. The arrival data itself originates from LTA DataMall, whose terms apply to it. The app keeps the attribution "Arrivals: ArriveLah (LTA DataMall)" on the journey card and in the footer. Re-check before any wider release or reuse |
| App usage | Only for the boarding stops of the ≤ 3 displayed direct-bus options, after the static plan exists, once per distinct stop; 15 s in-memory cache; manual refresh; no polling |
| Fallback | Missing or absent estimate → "No live arrival available" (never "0 min"). Error / network / malformed → "Live arrivals: …" + Retry, and the static route stays |

## OneMap search (tokenless)

| | |
|---|---|
| Owner | Singapore Land Authority |
| Endpoint | `https://www.onemap.gov.sg/api/common/elastic/search?searchVal=…&returnGeom=Y&getAddrDetails=Y&pageNum=1` |
| Data used (M2) | `SEARCHVAL` (name), `ADDRESS`, `POSTAL` (a string; `"NIL"` → none), `BUILDING` / `BLK_NO` (type inference only), `LATITUDE`, `LONGITUDE` (strings, parsed; out-of-SG or invalid rows are dropped). `X`/`Y` (SVY21) unused. Only page 1 (≤ 10 results) |
| Auth | Documented as token-required. Currently answers without a token (HTTP 200, CORS `*`), with an `error` message in every body, including empty ones (fixtures in `test/fixtures/onemap/`, captured 2026-10-01) |
| Reverse geocode | `/api/public/revgeocode` → **401 Unauthorized** without a token (2026-10-01). Not used |
| Licence / attribution | OneMap terms of use. The app shows "Place search: OneMap © Singapore Land Authority" under every result list and in the footer |
| Limitations | Access could be withdrawn. Weak ranking for some parks (see feasibility §4.3). Upper-case names. No result-type field |
| Rate limit | **Not published as a number.** The search docs list only "429 - API limit exceeded"; the API terms of service give no figure (both checked 2026-10-02). Observed: 429 after 2–3 calls within ~1.5 s. The 429 response is `text/html` and has no `Retry-After`, no rate-limit headers and no `Access-Control-Allow-Origin`, so a browser cannot read it (the page sees `TypeError: Failed to fetch`). Successful responses also carry no rate-limit headers. The app paces its own sends to 1 per second (`OneMapRateLimit`, docs/assumptions.md) |
| Token notice | The OneMap API docs (checked 2026-10-02) show a banner: "Search API now requires token-based authentication". The tokenless call still answered HTTP 200 the same day. This is the main risk for M2/M3 place search; on enforcement the app shows `ApiUnauthorized`, with no credential or proxy added |
| Failure handling | HTTP 401/403, or an `error` with no `results` list → `ApiUnauthorized`: a clear "requires sign-in" state, no workaround. `error` + empty `results` → no results. The tested OSM adapters remain contingency providers (not built) |

## OneMap basemap tiles (P2-M1)

| | |
|---|---|
| Owner | Singapore Land Authority |
| Endpoint | `https://www.onemap.gov.sg/maps/tiles/{Default\|Night}/{z}/{x}/{y}.png` (raster, 256 px), and the logo `https://www.onemap.gov.sg/web-assets/images/logo/om_logo.png` |
| Data used | Default tiles in light mode, Night in dark mode, z11–19 inside OneMap's documented bounds; only while the user has the map open |
| Auth | None (keyless). CORS `*`; same host as search, so no new CSP origin |
| Licence / attribution | OneMap terms of use (accepted in P2-M0, docs/map-feasibility.md §4.2). The logo and "OneMap © contributors \| Singapore Land Authority", both names linked, always visible below the map |
| Limitations | No service-level agreement ("as is", "as available"; may be suspended, restricted, blocked or charged for). **No published volume limit**, which is not read as permission for unlimited traffic: the app keeps the P2-M0 reasonable-use rules (docs/assumptions.md "Map tiles: reasonable use") |
| Failure handling | A failed tile is not retried; a note below the map says tiles are unavailable and the journey is unaffected. No automatic fallback to another tile provider and no proxy |

## Candidate fallbacks (evaluated, not integrated)

- **Photon** (`photon.komoot.io`, ODbL / OSM): keyless, CORS-enabled, suits type-ahead. Terms: "be fair —
  extensive usage will be throttled", with no availability guarantee.
- **Nominatim** (`nominatim.openstreetmap.org`, ODbL / OSM): keyless, CORS-enabled. Policy: ≤ 1 req/s,
  **no client-side autocomplete**, identify the app via Referer/User-Agent, show attribution.

## LTA MRT Station Exit (bundled asset `assets/mrt_stations.json`)

| | |
|---|---|
| Source | data.gov.sg dataset `d_b39d3a0871985372d7e1637193335da5`, "LTA MRT Station Exit (GEOJSON)", published by the Land Transport Authority. Fetched with `poll-download` (HTTP 201 → a signed URL) |
| Licence / attribution | Singapore Open Data Licence v1.0. The app shows "MRT exits: LTA via data.gov.sg (Singapore Open Data Licence)" |
| Fields used | `STATION_NA`, `EXIT_CODE`, Point `[lng, lat]`. There is **no line or station-code field**, so the app shows station names only |
| Generation | `dart run tool/build_mrt_asset.dart` (or `--input exits.geojson --retrieved YYYY-MM-DD` for an offline rebuild). It groups exits with `groupMrtExits`, applies the cited code-only mapping, round-trips the output through the app's parser, and writes sorted, rounded JSON. Two builds from the same input are byte-identical |
| Recorded in the asset | Source and dataset ID, licence, retrieval date (UTC), the latest feature update in the data, each code-only mapping with its evidence, and validation counts |
| Current build | Retrieved 2026-10-01 (UTC); latest feature update 2026-07-17. 613 features, 0 skipped, 613 exits, 0 duplicates → **188 stations**; 7 code-only names mapped, 0 unverified |
| Code-only records | CC9 → Paya Lebar, DT18 → Telok Ayer, DT4 → Hume, NE18 → Punggol Coast, CC30 → Keppel, CC31 → Cantonment, CC32 → Prince Edward Road. Each is verified by OneMap returning exactly that code label 41–85 m from the exits (searched 2026-10-02) |
| Update procedure | Re-run the generator, review the printed counts (any "unverified code-only" warning needs a cited mapping or stays code-labelled), run `flutter test test/features/journey/mrt_test.dart` (update the expected counts if the dataset legitimately changed), and commit the asset |

## Flutter engine CDN (Web only, not a data source)

| | |
|---|---|
| Owner | Google (Flutter) |
| What | `https://www.gstatic.com/flutter-canvaskit/<engine revision>/` (CanvasKit script + WebAssembly) and `https://fonts.gstatic.com` (fallback fonts), loaded by the Flutter Web engine itself |
| Why | Flutter's default for `flutter build web` (`--web-resources-cdn`). Measured over a full journey in Chrome on 2026-10-02 (M5) |
| Auth | None. No user data is sent; the requests are static engine files |
| Limitations | A third-party dependency at load time: if it is blocked or down, the Web app does not start. `--no-web-resources-cdn` would bundle CanvasKit, but fallback fonts would still come from `fonts.gstatic.com` |

## url_launcher (UI/platform package, not a data source)

| | |
|---|---|
| Owner | Flutter team (`url_launcher` on pub.dev) |
| What | Opens the two basemap attribution links in the external browser (P2-M1). It sends and receives no app data |
| Why | OneMap's attribution snippet links "OneMap" and "Singapore Land Authority"; user decision, 2026-10-03 |
| Platform notes | Web: a new browser tab (no CSP change). Android: `launchUrl` starts the browser activity directly, so no `<queries>` entry is needed (only `canLaunchUrl` would need one, and the app does not call it) |

## Excluded

- **LTA DataMall:** needs an AccountKey, and has no browser CORS support. Never called by the app. A local
  reference check is optional and needs the developer's own key (`api-feasibility.md` §5).
- **OneMap routing:** needs a token.
- **Phase 2 map candidates ruled out in P2-M0 and P2-M4** (`docs/map-feasibility.md` §4, §6, §6.1):
  - CARTO basemaps now need a key; keyless tiles are watermarked "API KEY REQUIRED" (seen 2026-10-02).
  - The OSRM demo server: its `/foot/` returns a car route (checked again in the P2-M4 discovery, 2026-10-04),
    and its wiki limits it to reasonable, non-commercial use.
  - FOSSGIS `routed-foot` and Valhalla (`routing.openstreetmap.de`, `valhalla1.openstreetmap.de`): keyless and
    CORS-enabled, but their shared terms don't fit a backend-less public app (no hardcoded URLs recommended, an
    operator email, an app User-Agent, request logging, no high-traffic sites). Not adopted in P2-M4
    (`docs/map-feasibility.md` §6.1).
  - BRouter has no usage policy (checked again in the P2-M4 discovery, 2026-10-04).
  - openrouteservice, GraphHopper, Mapbox, Stadia, MapTiler, Thunderforest, Esri and Google Maps need keys.
