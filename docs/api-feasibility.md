# API Feasibility — Milestone 0

**Run date:** 2026-10-01 (SGT). **Constraint:** strictly front-end-only. There is no backend or proxy, and
the client ships no confidential credentials.

Raw evidence (committed):

| File | What |
|---|---|
| `docs/probe-output/flutter-doctor.txt` | `flutter doctor -v` environment check (step 1) |
| `docs/probe-output/curl-probes.txt` | `bash tool/probe_apis.sh` — status, CORS headers, payload heads |
| `docs/probe-output/flutter-web-chrome.txt` | `flutter run -d chrome -t tool/api_probe_app.dart` — real browser (CORS enforced) |
| `docs/probe-output/flutter-android-emulator.txt` | same probe app on the Android emulator |
| `docs/probe-output/place-search-eval.txt` / `.json` | `dart run tool/place_search_eval.dart` — 51-query place-search evaluation |

Re-run any of them with the commands above. None needs credentials.

------------------------------------------------------------------------

## 1. Provider matrix (verified)

| Capability | Provider | Auth | curl (CORS header) | Flutter Web (Chrome) | Android | Refresh / limits | Licence / terms | Selected |
|---|---|---|---|---|---|---|---|---|
| 2-hr forecast | data.gov.sg v2 real-time | None | 200, `ACAO: *` | 200 | 200 | Anonymous: **6 calls / 10 s** (per v2 real-time limit) → 429 | Singapore Open Data Licence | **Yes** |
| UV | data.gov.sg | None | 200, `ACAO: *` | 200 | 200 | as above; hourly, daytime | SODL | **Yes** |
| 1-hr PM2.5 | data.gov.sg | None | 200, `ACAO: *` | 200 | 200 | as above; hourly | SODL | **Yes** |
| 24-hr PSI | data.gov.sg (`psi_twenty_four_hourly`) | None | 200, `ACAO: *` | 200 | 200 | as above; hourly | SODL | **Yes** |
| Bus stops | busrouter `stops.min.json` | None | 200, `ACAO: *` (317 KB) | 200 | 200 | static | community project (cheeaun) over LTA data; no SLA | **Yes** |
| Bus services / stop order | busrouter `services.min.json` | None | 200, `ACAO: *` (255 KB) | 200 | 200 | static | as above | **Yes** |
| Live bus arrival | ArriveLah | None | 200, `ACAO: *` | 200 | 200 | near-real-time | community project; no SLA | **Yes** |
| Place search | OneMap elastic search (tokenless) | Docs say token; **works without one** today (response carries `"error": "Authentication token missing…"`) | 200, `ACAO: *` | 200 | 200 | unknown | SLA OneMap terms | **Yes — primary, at risk** |
| Place search (fallback candidate) | Photon (komoot public) | None | 200, `ACAO: *` | 200 | 200 | "be fair — extensive usage will be throttled", no availability guarantee | ODbL (OSM) | Candidate (not built in M1) |
| Place search / reverse (fallback candidate) | Nominatim (OSMF public) | None | 200, `ACAO: *` | 200 | 200 | **≤ 1 req/s; client-side autocomplete forbidden**; identify app via Referer/User-Agent | ODbL; attribution required | Candidate (submit-only) |
| MRT stations / exits | data.gov.sg LTA MRT Station Exit GeoJSON | None | poll-download 201 → signed S3 URL | n/a (build-time asset) | n/a | static | SODL | **Yes, as bundled asset** (generation deferred to M3) |
| Walking / PT routing | OneMap routing | Token | **401** | not tested | not tested | — | — | **No** (needs credential) |
| Bus (official) | LTA DataMall v3 | AccountKey | preflight **403** | **`Failed to fetch` (CORS)** | reachable natively (404 without key); not used | — | — | **No** (Phase 1) |

## 2. Findings that change or confirm the design

1. **All Phase 1 sources work keyless from a real browser.** Confirmed in Chrome. LTA DataMall fails CORS
   exactly as predicted, which confirms that an AccountKey would not make it usable from Flutter Web.
2. **data.gov.sg anonymous rate limit: 6 real-time calls per 10 s**
   (guide.data.gov.sg → API Rate Limits; exceeding it returns 429). The dashboard makes 4 calls at launch, so
   it fits. Refresh must be **debounced and session-cached**: never refetch per widget, and never all four
   datasets in a tight loop. Handle `ApiRateLimited`. An optional (non-secret, public) API key raises the
   limit to 12/10 s, but it is **not required and not planned**.
3. **OneMap tokenless search scored best among the tested providers (OneMap, Photon, Nominatim) on this
   51-query test set.** See §4. This is not a general guarantee. The response explicitly says a token is
   missing, so this access can be withdrawn at any time. Keep it behind `PlaceSearchRepository`.
4. **OSM providers (Photon / Nominatim) are viable fallbacks** for postal codes, malls, universities,
   landmarks and streets. They are **weak on HDB block addresses** (§4.3).
5. **busrouter / ArriveLah** returned the expected schemas: stops `[lng, lat, name, road]` (note the **lng
   first** order); services `routes` = per-direction ordered stop lists; ArriveLah ISO `+08:00` times with
   `duration_ms`, `load`, `feature`, `type`.

## 3. Android verification

**All selected providers returned HTTP 200 from a debug APK on the Pixel 8 Pro emulator**
(`docs/probe-output/flutter-android-emulator.txt`). The first request took ~13 s (cold network on a freshly
booted emulator). Later requests took 0.3–0.7 s, and Photon ~3.8 s. Android does not enforce CORS, so this
run confirms reachability and TLS. LTA DataMall is reachable natively (404 without a key), but it is not
used.

Tooling note: on the warm emulator, `flutter run`'s launch step hung (adb timeout, black screen). A cold boot
(`emulator -avd Pixel_8_Pro -no-snapshot-load`) plus `adb install` / `am start` worked. `flutter run` itself
is not required for any acceptance criterion. Re-check it in Milestone 1.

INTERNET permission (resolved in the M0 review cleanup): Flutter's templates declared
`<uses-permission android:name="android.permission.INTERNET"/>` only in
`android/app/src/debug/AndroidManifest.xml` and `android/app/src/profile/AndroidManifest.xml`. The main
(release) `android/app/src/main/AndroidManifest.xml` did not declare it, so the M0 debug APK run above does not
prove release networking. The same line is now declared in `android/app/src/main/AndroidManifest.xml`.
`flutter build apk --release` passes and the merged release manifest contains the permission. A release APK
has not been run on a device or emulator yet (Milestone 1).

## 4. Place-search feasibility (largest remaining risk)

### 4.1 Method

- 51 queries in 9 categories: postal codes (9), HDB addresses (5, incl. abbreviated `St`/`Ave`/`Blk`), streets
  (5), malls (6), universities (6), landmarks/POIs (7), less prominent neighbourhood places (8), type-ahead
  prefixes (4), negative (`000000`).
- Providers: OneMap tokenless, Photon (`bbox` = SG), Nominatim (`countrycodes=sg`). Nominatim was throttled
  to ≤ 1 req/s with an identifying User-Agent, and was **not** sent prefix queries (its policy forbids
  autocomplete).
- Automatic rule: the first hit inside the SG bounding box whose name/address contains an expected keyword
  (whole word). Postal-code and HDB-block queries require **exact postcode equality**. Then **manual
  adjudication** of every disagreement (§4.3). The automatic scorer alone over-credits street-level hits.

### 4.2 Results (automatic scorer, top-1 / top-3 of n)

| Category | OneMap | Photon | Nominatim |
|---|---|---|---|
| Postal code (exact) | 9/9 · 9/9 | 9/9 · 9/9 | 9/9 · 9/9 |
| HDB address (exact postcode) | 4/5 · 4/5 | 2/5 · 2/5 | 2/5 · 2/5 |
| Street | 5/5 | 5/5 | 5/5 |
| Mall | 6/6 | 6/6 | 6/6 |
| University | 6/6 | 4/6 · 5/6 | 6/6 |
| Landmark / POI | 6/7 · 6/7 | 6/7 · 6/7 | 6/7 · 6/7 |
| Neighbourhood | 6/8 · 7/8 (auto) | 8/8 | 7/8 |
| Type-ahead prefix | 4/4 | 4/4 | n/a (policy) |
| Negative `000000` | correct (none) | correct | correct |
| Median latency (this run) | 77 ms | 1,393 ms | 15 ms (likely edge-cached) |

### 4.3 Manual adjudication

| Query | Observation | Verdict |
|---|---|---|
| `123 Ang Mo Kio Avenue 6`, `345 Yishun Avenue 11` | Photon/Nominatim return the **street**, not the block (0.3–1.6 km off) | OSM **fails** HDB block resolution; OneMap exact |
| `Blk 123 Ang Mo Kio Ave 6` | OneMap and Nominatim return nothing; Photon returns unrelated blocks | Normalise input: strip `Blk`/`Block` before querying |
| `201 Tampines St 21` | All three exact, within 9 m | Abbreviations `St`/`Ave` OK |
| Postal codes | All exact. OneMap gives building names; Photon/Nominatim give a postcode centroid labelled with the area only. Distance to OneMap 0–535 m (largest on campuses/hospital) | All usable; OneMap most descriptive |
| `NUS` | OneMap: NUS RVRC (on campus) ✓. Nominatim: NUS main ✓. **Photon: NUS High School** (wrong place, ~1.2 km) | Photon weak on acronyms |
| `NTU` | **Photon top-1 = NTUC Centre (Marina)**, NTU at #2 | Photon weak on acronyms |
| `Bishan MRT` | OneMap ✓ (with `(NS17)` / `(CC15)` codes). Photon/Nominatim: nothing | OSM needs `Bishan Station` / normalisation; OneMap also supplies station codes |
| `Sembawang Park` | **OneMap's "SEMBAWANG PARK" = 443 Sembawang Road, ~3.8 km from the actual park**; OSM correct | OneMap ranking/entity error |
| `Pasir Ris Park` | OneMap ranks "Pasir Ris Beach Park" entries first; the exact name is at #6 | OneMap ranking weak for parks |
| `Toa Payoh Lorong 1` | Nominatim returns other Lorongs | Nominatim weak on Lorong ordering |
| `Singapore General Hospital` | OneMap top-1 = "SGH BLK 4 (TAXI STAND)" (on campus) | Acceptable, but the label is noisy |
| Photon numeric postcode queries | Fuzzy: an earlier probe for `640512` returned `640517` | **Exact-match filter is mandatory** |

### 4.4 Conclusion and recommendation

- **Feasible front-end-only.** For Milestone 2, **OneMap tokenless scored best among the tested providers
  (OneMap, Photon, Nominatim) on this 51-query test set**. It was the only one of the three that resolved
  HDB blocks and MRT station codes reliably in these queries. This is not a general guarantee for other
  queries or providers.
- **Operational risk:** tokenless access is undocumented. The response carries `"error": "Authentication
  token missing…"`, so OneMap can withdraw it at any time without notice.
- Its weaknesses (park ranking, noisy sub-entity labels) are tolerable because §8.3 of the guide already
  requires the user to **choose** from a list. Results show address + postcode for disambiguation.
- **Fallback:** if OneMap starts enforcing tokens, Photon (type-ahead) + Nominatim (submit/reverse) together
  cover postal codes, malls, universities, landmarks and streets. They **degrade HDB block search to
  street-level** and are weak on acronyms. The user-facing mitigation: prompt for the postal code (which
  OSM resolves exactly) when a block search returns street-level results.
- Per guide v2.1 §0.1 item 6, **do not build the composite fallback in Milestone 2.** Build
  `PlaceSearchRepository` with a OneMap adapter, a query normaliser (strip `Blk`/`Block`, trim, collapse
  whitespace) and the exact-postcode rule. Add OSM adapters only when a demonstrated need arises (OneMap
  failure detected by the health rule: 401/403, or `error` with empty `results`).

## 5. Optional local DataMall reference check (not part of the app)

DataMall is **excluded** from the app. If you want to compare official LTA data against
busrouter/ArriveLah on your own machine, use a key held only in your local environment. Never commit it,
log it, or put it in any build:

```bash
# Set in your own shell only (do not commit, do not add to any file in this repo)
export LTA_ACCOUNT_KEY=...   # PowerShell: $env:LTA_ACCOUNT_KEY = '...'
curl -s -H "AccountKey: $LTA_ACCOUNT_KEY" -H "accept: application/json" \
  "https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival?BusStopCode=09048" | head -c 400
```

Compare the services and ETAs against `https://arrivelah2.busrouter.sg/?id=09048`. This check was **not
run** in Milestone 0, and it is not required for any milestone.
