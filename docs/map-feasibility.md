# Phase 2 Milestone 0 — Map feasibility

Research and design only. P2-M0 adds **no app dependency and changes no app behaviour**. The app's
`pubspec.yaml`, `lib/` and `web/index.html` are unchanged. Evidence comes from three sources:
- an isolated, removable spike app (`tool/map_spike/`, removed in P2-M1; source in git history at
  `f5934d1`);
- two dev-only probes (`tool/probe_map.sh` → `docs/probe-output/map-probes.txt`, and
  `tool/route_geometry_probe.dart` → `docs/probe-output/route-geometry.txt`);
- screenshots in `docs/probe-output/map-spike/`.

Observed 2026-10-02/03 (UTC 17:26–18:01 on 2026-10-02). OneMap's terms, basemap docs and attribution snippet
were re-read on 2026-10-03 (02:06–02:08 UTC) for the basemap decision (§4.2). Toolchain: Flutter 3.47.2 /
Dart 3.13.2, Chrome 154.0.8037.95, Pixel_8_Pro AVD.

Constraints this design keeps (guide §2, §14, §17, ADR-001):
- Android + Web;
- frontend only: no backend, proxy or serverless code;
- no credentials of any kind in the client;
- Singapore only;
- the M5 CSP model;
- the map is optional, and the planner must not depend on it.

## 1. Summary and recommendation

| Decision | Recommendation | Why (evidence) |
|---|---|---|
| Renderer | **flutter_map 8.x** (raster tiles), with `latlong2` | Pure Dart. Runs on Android and Web: proven on both in the spike (§3). No JS library, so no extra `script-src` or `worker-src`. BSD-3, actively released (8.3.2 on 2026-08-27). |
| Basemap | **OneMap** `Default` (light) and `Night` (dark) raster tiles, z11–19. **Decision: accepted** (§4.2) | Keyless, `Access-Control-Allow-Origin: *`, official Singapore map. The host `www.onemap.gov.sg` is **already in `connect-src`**, so the basemap needs **no CSP change**. The terms license use but give no service-level agreement and publish no volume limit, so the project sets its own reasonable-use rules (§4.2). |
| Fallback basemap | None automatically. Keep OSM standard tiles as a documented config switch | A second provider adds a host, a policy and an attribution for a rare failure. When tiles fail, the map shows a degraded state; the journey card, which is the real answer, is unaffected. |
| Bus ride geometry | Slice busrouter `routes.min.json`, already an allowed host, between the boarding and alighting stops | 98.5% of stop-to-stop hops and 88% of random rides can be drawn exactly. The rest fall back to straight hop connectors, drawn and labelled as approximate (§5). |
| Walking geometry | **Keep straight-line "est." connectors** (guide §17). No live router by default | None of the keyless routers we tested (§6) had a usage policy we could confidently adopt for app traffic. An opt-in FOSSGIS `routed-foot` experiment is possible later, only on your decision. |
| Architecture | A new `features/map/` that only *reads* the plan; flutter_map imported in one widget | The planner and domain never import map code (guide §17), and the map stays removable (§8). |

**Basemap decision: OneMap is accepted** (§4.2). This comes with three conditions:
- the OneMap logo and attribution are always shown;
- the project keeps its own reasonable-use rules, because OneMap publishes no volume limit;
- the map degrades on its own if tiles are refused.

OneMap gives **no service-level agreement**. Its terms provide the data "as is" and "as available", and SLA (the Singapore Land
Authority) may suspend, restrict, block or start charging at any time. The decision therefore does not
assume that OneMap guarantees any level of third-party app traffic, limited or unlimited.

## 2. Renderer options

| Option | Android | Web | Key | CSP cost on Web | Light/dark | Markers / polylines | Maintenance | Verdict |
|---|---|---|---|---|---|---|---|---|
| **flutter_map 8.3.2** (+ latlong2 0.10.1) | Yes | Yes (CanvasKit/skwasm) | None | Tile host in `connect-src` only. It fetches tiles with `package:http` (`BrowserClient`) and decodes the bytes, so the tile host needs CORS (§7) | Per tile source: swap the URL (OneMap Night) | `MarkerLayer` (any widget), `PolylineLayer` (solid, dashed, dotted) | 8.3.2 published 2026-08-27; releases every 2–4 months; ~42 open issues; BSD-3; Dart ≥3.6, Flutter ≥3.27 | **Recommended** |
| vector_map_tiles 8.0.0 (+ vector_tile_renderer) | Yes | **No web listed** | None (with OpenFreeMap) | — | Style JSON | via flutter_map | Stable 8.0.0 needs flutter_map ^7. For flutter_map 8 there are only betas (9.x, or 10.x on Flutter main + Impeller) | Rejected |
| maplibre_gl 0.27.1 / maplibre 0.3.6 | Yes (native) | Yes (MapLibre GL JS) | None (with OpenFreeMap) | Third-party script (unpkg CDN, or a self-hosted bundle), `worker-src blob:` (or `setWorkerUrl`), `img-src data: blob:`, plus style, glyph and sprite hosts | Vector styles | GeoJSON layers | Active; maplibre_gl has 73 open issues; josxha's maplibre is pre-1.0 with breaking 0.3.0 | Rejected for now. Vector maps look better, but the CSP and loading surface is much larger |
| google_maps_flutter 2.18.2 | Yes | Yes | **API key** (in the page on Web) | `maps.googleapis.com` script | Cloud styling | Yes | Google | Rejected (credential, billing, ToS) |

Sources: the pub.dev package pages and `https://pub.dev/api/packages/<name>`; flutter_map docs
(`docs.fleaflet.dev`, including "Using OpenStreetMap (direct)" and "Caching"); the flutter_map source
(`tile_provider/network/*`); the maplibre_gl getting-started CSP section; the MapLibre GL JS CSP notes.
All were read 2026-10-02/03.

## 3. Compatibility evidence (spike)

`tool/map_spike/` was a ~340-line app (removed in P2-M1, see §10) that used the M3 smoke journey: Raffles Place → VivoCity,
Bus 10 from 03019 OUE Bayfront to 14141 (9 stops). It draws five layers:
- the basemap, switchable at runtime between OneMap Default, OneMap Night, OSM standard, CARTO Positron and
  CARTO Dark Matter;
- the ride slice, from live `routes.min.json`, `services.min.json` and `stops.min.json`;
- the walk from origin to boarding stop, from live FOSSGIS Valhalla (pedestrian);
- origin, destination, boarding and alighting markers;
- a `RichAttributionWidget`.

Its `web/index.html` is **the app's own CSP**, with three spike-only hosts (OSM, CARTO, Valhalla) added to
`connect-src`. `img-src` is left as is.

| Check | Web (release build, static server on 127.0.0.1, CSP active) | Android (release APK, Pixel_8_Pro AVD) |
|---|---|---|
| Build | `flutter build web --release` OK | `flutter build apk --release` OK (46.0 MB) |
| OneMap Default / Night | Rendered, 0 tile errors (`web-onemap-default.jpg`, `web-onemap-night.jpg`) | Rendered, 0 tile errors (`android-onemap-default.jpg`, `android-onemap-night.jpg`); street level sharp at z18 (`android-walk-zoom.jpg`) |
| OSM standard | Rendered (`web-osm.jpg`) | Rendered with flutter_map's `userAgentPackageName` UA (`android-osm.jpg`) |
| CARTO | Grey / watermark tiles | **"API KEY REQUIRED" watermark** on every tile (`android-carto-watermark.jpg`) |
| Ride polyline (busrouter) | 16-point slice along the Bus 10 road path | Same: 16 points; the Dart VM gives the same |
| Walk polyline (Valhalla) | 0.57 km, 33 points, drawn dotted | Same |
| CSP | Headless Chrome console: **no violations** with the tile hosts in `connect-src`. Control page with OneMap moved from `connect-src` to `img-src`: every tile fails ("Fetch API cannot load … violates … connect-src", 78 times) | n/a (no CSP on Android) |
| How tiles load | Resource timing: every tile request is a `fetch` (initiator `fetch`), not an `<img>` | — |

Visual checks on Web used headless Chrome
(`chrome --headless=new --enable-unsafe-swiftshader --screenshot`). The extension's own Chrome tab reported
`visibilityState: hidden`, and its screenshots timed out. Interactions (switching basemaps, double-tap zoom)
were run on Android with `adb shell input tap`.

**A Web-only bug the spike caught.** The usual Google polyline decoder ends with `~(result >> 1)`. Under
dart2js, bitwise operators return unsigned 32-bit values, so `~x` turns every negative delta into about
+2³². Decoded points came out at latitude ≈ 2,147,484 on Web, and the ride slice collapsed to 2 points; the
Dart VM was correct. The Web-safe form is `-(result >> 1) - 1`. P2-M2 must test the decoder **on the Web
platform** (`flutter test --platform chrome`) with negative deltas.

## 4. Tile sources

All probed with `curl` and `Origin: https://example.com` (`docs/probe-output/map-probes.txt`).

| Source | URL template | Key | CORS | Light/dark | Zoom | Policy for app traffic | Attribution | Verdict |
|---|---|---|---|---|---|---|---|---|
| **OneMap** (Singapore Land Authority) | `https://www.onemap.gov.sg/maps/tiles/{Default\|Night\|Grey\|GreyLite\|Original}/{z}/{x}/{y}.png` | None | `*` | Default and Original light, Grey and GreyLite muted, **Night dark** | 11–19 per docs (z10 also served; z20 and tiles outside SG return an empty 200) | Documented for embedding. Terms give no rate limit and no explicit approval for third-party app volume (§4.1). `Cache-Control: max-age=14400` | **Must** show the OneMap logo and "OneMap © contributors \| Singapore Land Authority", linking to onemap.gov.sg and sla.gov.sg | **Primary** |
| OSM standard (OSMF) | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` | None | `*` | Light only | 0–19 | Tile Usage Policy: clear UA (impossible to set on Web; Referer is used), cache ≥ 7 days, no bulk or offline use, no service-level agreement, may be blocked. flutter_map docs warn that its apps were the largest UA in 2025 | "© OpenStreetMap contributors", always visible | Contingency only |
| CARTO basemaps | `https://{a-d}.basemaps.cartocdn.com/{light_all\|dark_all}/{z}/{x}/{y}{r}.png` | **Now required** (terms effective 2026-09-29) | `*` | Positron / Dark Matter | 0–20 | Keyless requests return HTTP 200 with a watermark tile | "© OpenStreetMap contributors © CARTO" | Rejected (key) |
| OpenFreeMap | `https://tiles.openfreemap.org/styles/{liberty\|positron\|bright\|dark}` (vector) | None | `*` | Yes (dark style) | Vector to z14, overzoomed | "No limits"; donation-funded, single operator, no service-level agreement | "OpenFreeMap © OpenMapTiles Data from OpenStreetMap" | Rejected for now: vector only, so it needs MapLibre (§2) |
| Stadia, MapTiler, Thunderforest, Esri | various | Key or domain auth (Stadia on Web) | — | — | — | Free tiers non-commercial; native apps need a key in the bundle | — | Rejected (credential) |

### 4.1 OneMap terms and attribution

- **Docs** (`https://www.onemap.gov.sg/docs/maps/`): basemaps are offered for embedding with Leaflet-style
  URL templates. The docs ask for `minZoom 11`, `maxZoom 19`, and bounds SW (1.144, 103.535) to
  NE (1.494, 104.502).
- **TileJSON** (`…/maps/json/raster/tilejson/2.2.0/Default.json`) gives z11–19 and points at the `Default_HD`
  tiles. On 2026-10-02 the `*_HD` tiles were also 256 px and were served as `Content-Type: image/undefined`.
  The spike used the non-HD styles (`image/png`). Revisit HD in P2-M4.
- **Attribution.** The basemap docs say: "Under our Terms of Use, by using our base map services, you MUST
  include the OneMap logo and attribution". The snippet they provide
  (`https://www.onemap.gov.sg/docs/maps/resources/code-attr.txt`, re-read 2026-10-03; the older
  `docs/maps/code-attr.txt` now returns a "We have moved!" page) is:
  - a 20 × 20 OneMap logo, `https://www.onemap.gov.sg/web-assets/images/logo/om_logo.png` (CORS `*`, same
    allowed host);
  - then "OneMap © contributors | Singapore Land Authority";
  - "OneMap" links to `https://www.onemap.gov.sg/` and "Singapore Land Authority" to
    `https://www.sla.gov.sg/`.

  It must stay visible. flutter_map's `RichAttributionWidget` collapses to an "i" button by default. That
  is fine for the secondary credits, but the OneMap line and logo must be shown persistently.
- **Terms** (`https://www.onemap.gov.sg/legal/termsofuse.html`, re-read 2026-10-03):
  - **Licence.** Clause 3(a) grants a "non-transferable, non-exclusive, royalty-free, revocable licence to
    access, view, download, print or otherwise use the SLA Data and the SLA Material for any usage", subject
    to the terms. Clause 3(b) forbids storing, archiving, reproducing, redistributing and similar uses
    "except as expressly permitted in Clause 3(a)". It also forbids removing or obscuring SLA's copyright
    notices and logos.
  - **No service commitment.** Clause 2 lets SLA:
    - suspend the site or any data "for any period of time without any prior notice";
    - restrict parts of it "to Registered Developers only";
    - deny or restrict access, or block an internet address, without notice.

    The data is provided "as is" and "as available", with no warranty that it will be "available without
    interruption or delay". No charge is made today, but SLA may introduce one.
  - **No published volume limit.** Neither the terms nor the basemap docs give a rate limit, quota,
    reasonable-use figure or caching rule for tiles. This was searched on 2026-10-03.
  - **Implications:**
    - Don't prefetch tiles or cache them in bulk for offline use; rely on the HTTP cache (the browser cache
      on Web, flutter_map's built-in cache on Android, which follows `max-age`).
    - Never hide the logo or attribution.
    - Treat the service as best-effort.
- **Shared-host check.** OneMap search returns 429 after 2–3 calls in about 1.5 s. Tiles come from the same
  host, so one map view's worth of tiles (8 × 5 at z16) was sent in parallel, followed by a search:
  - all 40 tile requests returned 200;
  - the search right afterwards returned 200.
  - Tile traffic at one-view scale did not trip the search limit. The app's search pacing
    (`OneMapRateLimit`) applies only to search, and tiles go through flutter_map's own client.

### 4.2 Decision: OneMap raster tiles are the project basemap

**Accepted.** OneMap `Default` (light) and `Night` (dark) raster tiles, z11–19, are the basemap for P2-M1
onwards. The reasons:
- the terms license viewing and use (§4.1);
- the tiles are documented for embedding;
- they need no key or token;
- they add no CSP origin;
- OneMap is the official national map.

**What the acceptance does not assume:**
- **No service-level agreement, and no traffic guarantee.** OneMap gives no availability commitment, and SLA may suspend,
  restrict, block or charge without notice (§4.1).
- **No unlimited volume.** OneMap publishes no volume limit, and we read that only as "no limit was
  published", never as permission for unlimited third-party app traffic. The project caps its own load
  (below).

**Attribution (required).**
- Show the OneMap logo (20 × 20) and "OneMap © contributors | Singapore Land Authority" whenever tiles are
  on screen, in both light and dark mode.
- Link "OneMap" to `https://www.onemap.gov.sg/` and "Singapore Land Authority" to `https://www.sla.gov.sg/`.
- Never collapse, cover or remove it.
- P2-M1 adds a widget test that asserts this (risk M2).

**Project reasonable-use rules.** These are binding on P2-M1 to P2-M4. Their values go into `MapConfig` and
`docs/assumptions.md` when implemented.
1. **Tiles only for a map the user can see.** No tile is requested before the map is shown, and nothing is
   requested in the background.
2. **Bounded area and zoom.** The camera is constrained to the docs' bounds, SW (1.144, 103.535) to
   NE (1.494, 104.502), and to z11–19, so no tiles outside Singapore and no deep zoom.
3. **No prefetching or bulk download.** No offline packs, warming, tile scraping or redistribution.
4. **Cache what has been fetched.** Use the HTTP cache with OneMap's `max-age`. Cap the Android cache
   (`MapConfig`), and check in P2-M4 that it honours `max-age=14400`.
5. **No automatic refresh, polling or retry loops.** The camera is fitted once per journey, without
   animation. A failed tile shows the "Map tiles unavailable" overlay; there is no app-level retry loop.
6. **Honest identity.** No credentials, proxy or spoofed client. On Android, flutter_map sends its
   package-name `User-Agent`; on Web the browser's own headers go out.
7. **Re-check the terms** at each map milestone (P2-M1 to P2-M4), and record the date and any change in
   `docs/testing.md`.

**If OneMap refuses tiles** (a token requirement, a published limit we would exceed, 429s or a block):
- the map shows its degraded state;
- planning, the journey card and arrivals are unaffected;
- tiles are not retried automatically.

Switching to the documented OSM contingency, or dropping the basemap, is then a new reviewed decision, with
its own CSP host and the OSM tile policy. It is never an automatic fallback, and never a proxy.

## 5. Bus ride geometry from existing busrouter data

`routes.min.json` (289 KB, `ACAO: *`, `max-age=86400`, from `data.busrouter.sg`, already in `connect-src`):
- has one Google-encoded polyline (precision 5) per service direction;
- covers 602 services and 798 directions, matching `services.min.json` 1:1 (406 one-direction, 196
  two-direction);
- contains only geometry, with no stop indices. To draw a ride, the app must match stops to the line.

`tool/route_geometry_probe.dart` (full method in its header; output `docs/probe-output/route-geometry.txt`)
works like this:
- each stop gets every position on its direction's polyline within 60 m;
- a dynamic programme picks the in-order chain matching the most stops with the least offset;
- the line is tried as given, reversed, and doubled. 104 directions (mostly loops whose geometry starts at
  a different stop) match only on the doubled line, and 4 directions are stored reversed.

| Result | Value |
|---|---|
| Directions with every stop matched in order | 600 / 798 (75.2%) |
| Consecutive stop pairs (hops) drawable | 25,634 / 26,025 (**98.5%**) |
| Along-line ÷ straight-line per hop | median 1.02, p95 1.59, p99 2.42 |
| Random rides (1–25 stops, 10 per direction) drawable end to end | 7,036 / 7,980 (**88.2%**) |
| M3 smoke ride, Bus 10 03019 → 14141 | Drawable, 4,426 m along the line (matches the spike) |

Failures are mostly 1–5 stops per direction:
- interchange berths more than 60 m off the road line;
- a few services with stale or mismatched geometry, for example `2B` and `154B`, whose lines cover only
  part of their stop list.

Rules proposed for P2-M2. These are tunables, so they go in `app_config.dart` and `docs/assumptions.md`
when implemented:
1. Draw the exact line for every hop that is matched in order, and where the along-line distance is at most
   3× the straight line.
2. Draw any other hop as a **straight dashed connector between the two real stops**, and mark the ride
   "route shape approximate". This never invents a route: the stops and their order are real data.
   **Your decision:** whether this partial approximation is acceptable, or whether a ride that isn't fully
   matched should show stop markers only.
3. When `routes.min.json` fails to load or parse, show markers only and a "route line unavailable" note.
   Planning and arrivals are unaffected.

## 6. Walking-route geometry (frontend only)

| Provider | Key | CORS | Foot profile | Policy for client/app use | Verdict |
|---|---|---|---|---|---|
| OneMap routing | **Token** | `*` | Yes | 401 without a token | Excluded (credential) |
| OSRM demo `router.project-osrm.org` | None | `*` | **No.** `/foot/` returned a car route: 1,207 m in 124 s | "Reasonable, non-commercial", ≤ 1 req/s, no guarantees | Excluded (wrong profile) |
| FOSSGIS OSRM `routing.openstreetmap.de/routed-foot/` | None | `*` | Yes: 852 m, 686 s for the probe pair | About page: ≤ 1 req/s, valid UA/Referer, attribution plus a "fix the map" link, no heavy use. Requests are logged | **Only candidate.** Off by default (below) |
| FOSSGIS Valhalla `valhalla1.openstreetmap.de` | None | `*` | Yes (pedestrian; used in the spike) | FOSSGIS server policy (secondary source; the German terms page was unreachable) says development and testing only | Excluded for app traffic |
| BRouter `brouter.de` | None | `*` | Hiking/trekking profiles | No published usage policy | Excluded |
| openrouteservice, GraphHopper, Mapbox | Key | — | Yes | — | Excluded (credential) |
| On-device routing (e.g. `geo_route_finder` 1.5.0, pure Dart, reads `.osm.pbf`) | None | n/a | Yes | n/a | Not realistic: uses `dart:io` (no Web), needs a bundled or downloaded SG extract, no adoption |

**Conclusion.** None of the keyless candidates we tested (the OSRM demo, FOSSGIS `routed-foot`, FOSSGIS
Valhalla, BRouter) had a usage policy we could confidently adopt for app traffic:
- the OSRM demo's foot profile returned a car route;
- Valhalla's server policy restricts it to development and testing;
- BRouter publishes no policy;
- `routed-foot`, the closest fit, allows only light use (≤ 1 request per second, no heavy use) and logs
  requests.

This is a finding about these candidates, not a claim about every possible keyless router.

**Recommendation:** keep the current straight-line "est." walking connectors on the map, drawn dashed, as
guide §17 already specifies. FOSSGIS `routed-foot` could be an opt-in experiment in P2-M4, with these
conditions:
- only with your explicit approval of its policy;
- one request per walk leg, sent only when the map is shown;
- session-cached and paced to ≤ 1 request per second;
- straight-line fallback on any failure, and visible attribution.

It would also send the user's exact origin to a third party (requests are logged), which the current app
never does beyond OneMap search text.

## 7. CSP implications

- **Tiles use `connect-src`, not `img-src`.** flutter_map fetches tiles with `BrowserClient` and decodes the
  bytes. This was verified by resource timing and by the control page (§3).
  - The tile host must allow CORS; OneMap does (`*`).
  - `img-src 'self' data: blob:` can stay as it is.
  - No `script-src`, `worker-src` or `style-src` change is needed with flutter_map.
- **Recommended stack: no new origin.**
  - OneMap tiles and the OneMap logo come from `www.onemap.gov.sg`.
  - `routes.min.json` comes from `data.busrouter.sg`.
  - Both hosts are already in `connect-src`.
- **The CSP test still changes.** `test/web/content_security_policy_test.dart` derives the expected origins
  from `app_config.dart`. P2-M1 adds `BasemapEndpoints` (tile templates, logo) and P2-M2 adds
  `BusrouterEndpoints.routes`. Both must be added to that test's provider set; the policy itself stays the
  same.
- **What would add hosts, if chosen later:**
  - OSM contingency: `https://tile.openstreetmap.org`.
  - FOSSGIS walk: `https://routing.openstreetmap.de`.
  - MapLibre: a script origin (or self-hosting), `worker-src blob:`, and style, glyph and sprite hosts.
  - Each is a deliberate, reviewed CSP change.
- **Android** has no CSP. The app already declares `INTERNET`.

## 8. Recommended architecture

```
lib/features/map/
  domain/
    map_scene.dart        // pure: MapScene { markers, lines, bounds } built from
                          //   Origin + Place + JourneyPlan (+ MrtSuggestion); no Flutter import
    ride_geometry.dart    // pure: match stops to a polyline, slice board → alight (§5 rules)
  data/
    route_geometry_repository.dart  // routes.min.json once per session, via JsonHttpClient
    polyline_codec.dart             // Web-safe precision-5 decoder (tested on VM and Chrome)
  presentation/
    journey_map.dart      // the ONLY file that imports flutter_map; takes a MapScene
    basemap.dart          // OneMap Default/Night by brightness; persistent OneMap attribution
lib/core/config/app_config.dart     // BasemapEndpoints, MapConfig (zoom 11–19, SG bounds, tolerances)
```

- **Data flow:** `journeyPlanProvider` (unchanged) → `mapSceneProvider` (watches the plan and the selected
  option; `routeGeometryProvider` is loaded lazily the first time the map is shown) → `JourneyMap`.
  - The planner, the journey card and the arrivals never import `features/map`.
  - Removing the map removes one widget from `home_screen.dart`.
- **Display:**
  - The map sits under the journey card and is collapsible.
  - It is decorative for assistive tech: the journey card's text is the accessible source of truth, so
    the map gets one summary `Semantics` label.
  - Its camera is constrained to SG bounds.
- **Test seams:**
  - a `tileProviderProvider` that tests override with an in-memory blank-tile provider, so widget and
    integration tests never fetch tiles (CLAUDE.md: no live APIs);
  - `routeGeometryRepositoryProvider` with a fixture captured once from the real `routes.min.json`.
- **Dark mode:** the OneMap style follows `Theme.brightness` (Default ↔ Night). Polyline and marker colours
  come from the color scheme, checked for contrast on both basemaps.
- **Caching:**
  - Web: the browser HTTP cache.
  - Android: flutter_map's built-in cache (on by default off-Web since 8.2, 1 GB soft limit). Cap its size
    in `MapConfig`; check in P2-M4 that it honours the tiles' `max-age=14400`.
  - No prefetch or bulk download (OneMap terms; OSM policy if ever used).
- **Failure handling:**
  - Tile errors show a small "Map tiles unavailable" overlay.
  - A geometry failure shows markers only.
  - Neither ever blocks or changes the plan.

## 9. Risks and fallbacks

| # | Risk | Impact | Mitigation / fallback |
|---|---|---|---|
| M1 | OneMap publishes no volume limit and gives no service-level agreement; it may suspend, restrict, block, charge or introduce tokens (as for search) | No basemap | Project reasonable-use rules (§4.2); map is optional; degraded overlay, no automatic retry; switching to the documented OSM contingency is a new reviewed decision (adds one CSP host and the OSM policy); no proxy, ever |
| M2 | OneMap attribution non-compliance (logo collapsed or hidden) | Terms breach | Persistent attribution row with the logo; widget test asserts it is visible in light and dark |
| M3 | busrouter geometry stale or mismatched for some services | Wrong or partial line | Matching with a 60 m tolerance and 3× detour cap; straight connectors marked approximate; markers only if the data is unusable |
| M4 | dart2js bitwise semantics (found in the spike) and other VM/Web differences | Garbage geometry on Web only | Web-safe decoder; decoder tests also run with `--platform chrome`; Web integration test draws a known ride |
| M5 | flutter_map cannot abort superseded tile requests on Web (noted in its source); they still download | Bandwidth, and OneMap load during the camera fit | Fit the camera once without animating; zoom 11–19; no prefetch |
| M6 | flutter_map maintenance or breaking 9.x | Upgrade work | Pin `^8.3`; flutter_map imported in one widget only |
| M7 | Performance on low-end Android (overdraw, large polylines) | Jank | Ride slice only (tens of points), not whole routes; check frame times in P2-M4 |
| M8 | Accessibility: a map is visual-only | Screen-reader users lose nothing only if the text stays complete | Journey card remains the full answer; map has one summary label; no information only on the map |
| M9 | Privacy: tile requests reveal the viewed area to OneMap; a walking router would get exact coordinates | Data exposure | OneMap only (already used for search); walking router off by default (§6) |
| M10 | CARTO-style policy changes (keyless 200 with a watermark) can't be seen as HTTP errors | Silent bad map | Spot-check visually in each milestone's smoke run; not detectable automatically |

## 10. Proposed implementation sequence (one reviewable PR each)

1. **P2-M1 — Map shell and basemap.**
   - Add `flutter_map ^8.3.2` and `latlong2 ^0.10.1`.
   - Add `BasemapEndpoints` and `MapConfig` to `app_config.dart`.
   - Add `features/map` with `JourneyMap` showing origin and destination markers only, OneMap Default/Night
     by theme, and the persistent OneMap attribution with its logo.
   - Camera fitted to both points and constrained to SG.
   - The §4.2 reasonable-use rules: tiles only while the map is shown, bounds and z11–19, no prefetch, no
     retry loop. Record them in `docs/assumptions.md`, and re-check the OneMap terms.
   - Collapsible card under the journey; tile-failure overlay.
   - Tests: fake tile provider seam, light/dark attribution test, CSP test update.
   - Remove `tool/map_spike/` and its `analysis_options.yaml` exclude.
   - Gates as §19, plus live tile smoke on Chrome and Android.
   - **Done in P2-M1**, with these decisions (docs/assumptions.md, map rows; docs/architecture.md):
     - the map is closed by default ("Show map") and stays open for the session;
     - `url_launcher` was added for the attribution links, which open in the external browser;
     - the camera is fitted before the first frame, because flutter_map's `initialCameraFit` let its first
       frame request about 25 tiles at a default camera (seen live on Web);
     - the "tiles unavailable" note sits below the map, so it never covers a marker.
2. **P2-M2 — Bus ride geometry.**
   - `RouteGeometryRepository` (`routes.min.json`, once per session, lazy).
   - Web-safe `polyline_codec` with VM and Chrome tests.
   - `ride_geometry` matching and slicing with the §5 rules, on fixtures captured once from the real payload
     (including a loop, a reversed direction and `2B`-style mismatch cases).
   - Draw the ride line plus boarding and alighting markers; "route shape approximate" or "unavailable"
     states.
   - Tunables go in `docs/assumptions.md`.
3. **P2-M3 — Walk connectors, MRT and option sync.**
   - Straight dashed "est." walk connectors (origin → board, alight → destination).
   - MRT suggestion markers from the existing `mrtSuggestionProvider`.
   - Selecting an option (suggested or alternative) shows that option on the map; a legend.
   - Never shows data the journey card doesn't already show.
4. **P2-M4 — Hardening.**
   - Android tile cache cap.
   - Performance check on the emulator (frame times while panning, the ride drawn).
   - Accessibility semantics, reduced motion (no animated camera).
   - Web drive and Android integration tests with fake tiles; manual live smoke (light, dark, 360 dp, 2×
     text).
   - Decide on HD tiles.
   - Optional, **only if approved**: the FOSSGIS `routed-foot` experiment behind a config flag, with the
     §6 conditions and its own CSP host.

## 11. Decisions before P2-M1

1. **Basemap: decided in P2-M0.** OneMap raster tiles are accepted, with the required attribution, the
   project reasonable-use rules and the refusal handling in §4.2. They come with no service-level agreement and no assumption of
   unlimited traffic.
2. Ride lines: accept straight dashed connectors for unmatched hops, labelled approximate (§5 rule 2), or
   show markers only for those rides?
3. Walking: confirm straight-line "est." connectors. Should the FOSSGIS `routed-foot` experiment stay off
   the roadmap, or be considered in P2-M4?
