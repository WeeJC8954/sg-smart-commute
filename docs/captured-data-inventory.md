# Captured External-Data Inventory (owner decision 2026-11-07)

**Status:** inventory, 2026-11-07, for owner review. This document changes no file. The redaction it recommends is
done in a separate PR (branch `chore/redact-probe-output`). It does not contact any third party. It is not legal
advice: a conclusion that depends on reading terms is tagged **[A]**.

**Tags:** **[C]** confirmed (read from the files, the sources or Git, or measured); **[A]** assumption or reading not
verified; **[P]** proposal, needs approval.

**Related:** `docs/busrouter-fixture-licensing-audit.md` (A-1 to A-3), `docs/arrivelah-onemap-fixture-licensing-audit.md`
(A-4), `docs/runtime-data-rights-assessment.md` (A-5), `docs/onemap-runtime-assessment.md` (A-5d). This inventory
reuses their licence readings and does not re-read the terms.

## 1. Summary

- **[C]** The tree still holds captured provider data in four places outside the folders already handled:
  - response-body heads in three probe outputs (`curl-probes.txt`, `map-probes.txt`, `walking-routers-p2m4.txt`);
  - 51 rows of live search results in `docs/probe-output/place-search-eval.json`;
  - the NEA test fixtures (`test/fixtures/*.json`);
  - the MRT asset (`assets/mrt_stations.json`).
- **[C]** Out of scope here: `test/fixtures/onemap/` and `test/fixtures/arrivelah/` (replaced by synthetic data in PRs #98 and #99, both merged 2026-11-07),
  and `integration_test/fakes/fake_place_search_repository.dart` (another change; listed in §3.4 only).
- **[P]** Redact the probe bodies and remove the evaluation JSON: nothing reads them. Make
  `tool/place_search_eval.dart`, which writes its JSON into `docs/` by default, write to `build/`. Done in the
  `chore/redact-probe-output` PR. The two probe scripts already print to the terminal since PR #95 (A-5c).
- **[C]** The NEA fixtures and the MRT asset are data.gov.sg datasets under the Singapore Open Data Licence (SODL).
  The licence permits copying and distribution with a notice and a link. Tests and the app need them, so they stay.
  Neither carries the licence link; the NEA fixtures carry no notice at all. §5 proposes how to add both.
- **[C]** No test fixture needs replacing beyond #98 and #99: every other test datum is hand-written, synthetic or
  SODL data. So no `test/synthetic-*-fixtures` PR is opened.
- **Owner decisions** (§6): the SODL notices, two sets of screenshots that show live provider data, the E5 benchmark's
  `expected_results.txt`, and Git history.

## 2. Method [C]

Searched on `main` at `bbd9329` (2026-11-07); the tool headers and attribution rows re-checked at `8a3e8d3`, after
PRs #95 (A-5c) and #94 (A-5b):
- every file under `docs/probe-output/` (including `map-spike/`), `test/fixtures/`, `assets/`, `integration_test/fakes/`,
  `tool/` and `docs/images/`, read or viewed;
- `test/`, `integration_test/`, `lib/` and `tool/` for provider field names (`SEARCHVAL`, `visit_number`,
  `duration_ms`, `area_metadata`, `regionMetadata`, `osm_id`, `origin_code`), coordinates with four or more decimals,
  quoted five-digit codes and string literals of 40 or more characters (encoded polylines);
- `docs/*.md` for pasted bodies (`{"`, `SEARCHVAL`, `"services"`, `"lat":`) and for every citation of `probe-output`;
- provenance: `git log --diff-filter=A` per path; consumers: `grep` in `lib/`, `test/`, `integration_test/`, `tool/` and
  `docs/`.

## 3. Inventory

**Licence classes** (from the audits named above):

| Class | Source | Reading |
|---|---|---|
| **SODL** | data.gov.sg datasets (NEA, LTA MRT exits); LTA DataMall datasets | Copying and distribution permitted, with "a conspicuous notice acknowledging the source" and "a link to the most recent version of this Licence" (A-4 audit §3) |
| **LTA-web** | busrouter data scraped from lta.gov.sg | Redistribution not established; LTA's terms ask for written permission (busrouter audit §4) |
| **ArriveLah** | DataMall arrivals relayed by an unlicensed proxy | Not established (A-4 audit §4) |
| **OneMap** | SLA search results, tiles | Storing, distributing or publishing not shown to be permitted (A-4 audit §3, clause 3(b)) |
| **ODbL** | OSM data via Photon, Nominatim, OSRM, Valhalla, BRouter, OpenFreeMap; OSM tiles | Use permitted with attribution; share-alike for derived databases [A: not re-read; a 200-character body head is likely an insubstantial extract] |
| **Derived** | Counts, timings, byte sizes, distances, match indices computed by this project | No record copied [A] |
| **Project** | Written for this project: synthetic data, query lists, labels | No third-party content [C] |

### 3.1 `docs/probe-output/`

| Path | Bytes | Added | Written by | Consumers | Content | Class | Recommendation |
|---|---|---|---|---|---|---|---|
| `curl-probes.txt` | 7,238 | `d3d0706`, 2026-10-01 | `bash tool/probe_apis.sh` (its usage line redirected into `docs/` until PR #95) | `docs/api-feasibility.md` (evidence table); `docs/lta-clarification-request-draft.md` (with `map-probes.txt`, for the busrouter body heads) | Status lines, CORS headers, byte counts **and a 220-character head of each body**: data.gov.sg forecast, UV, PM2.5 and PSI records; busrouter stops, services and a route polyline; ArriveLah arrivals; OneMap results; Photon and Nominatim results (OSM ids, names, addresses); a data.gov.sg signed-URL response; DataMall and OneMap error texts | SODL, LTA-web, ArriveLah, OneMap, ODbL | **Redact** every body; keep status, headers and bytes [P] |
| `map-probes.txt` | 6,932 | `67fec7b`, 2026-10-03 | `bash tool/probe_map.sh` (same) | `docs/map-feasibility.md` §1, §4; `docs/testing.md` run log; `docs/p2-m4-map-hardening-implementation-plan.md` | Tile probes (`<binary>`, no data) plus 200-character bodies: OpenFreeMap style and TileJSON, busrouter `routes.min.json`, OSRM, FOSSGIS OSRM, Valhalla and BRouter routes (geometry), OneMap search, OneMap routing error | ODbL, LTA-web, OneMap | **Redact** each non-binary body; keep the rest [P] |
| `walking-routers-p2m4.txt` | 2,510 | `055a6dd`, 2026-10-04 | The inline script of `docs/p2-m4-map-hardening-implementation-plan.md` Task 1 | `docs/map-feasibility.md` §6.1; `docs/testing.md`; the P2-M4 plan | One FOSSGIS OSRM body (route geometry), then headers, a terms-page hash and a clause check (short quotes of the FOSSGIS terms) | ODbL; clause quotes are short | **Redact** the body; keep the clause check, which records the decision's evidence [P] |
| `route-geometry.txt` | 578 | `67fec7b`, 2026-10-03 | `dart run tool/route_geometry_probe.dart` (stdout) | `docs/map-feasibility.md` §5; `docs/testing.md` | Counts and percentages of a matcher run, one ride (Bus 10, 03019 → 14141, 4,426 m) | Derived | **Keep** (busrouter audit §2 reached the same reading) |
| `place-search-eval.json` | 118,294 | `d3d0706`, 2026-10-01 | `dart run tool/place_search_eval.dart`, which writes it to `docs/probe-output/` by default | `docs/api-feasibility.md` (evidence table) only; no code reads it | 51 queries, and for each provider the top results: name, address, postcode, latitude, longitude, plus OneMap's token message | OneMap, ODbL | **Remove**; point the tool at `build/` [P] |
| `place-search-eval.txt` | 6,137 | `d3d0706`, 2026-10-01 | The same tool's terminal output | `docs/api-feasibility.md` | Per query (written for this project): category, query, the 0-based match index per provider, the distance in metres from the OneMap hit; then the summary table | Project, Derived | **Keep**: it holds no name, address or coordinate from a provider [A] |
| `flutter-doctor.txt`, `flutter-web-chrome.txt`, `flutter-android-emulator.txt` | 2,513; 914; 1,038 | `519f265`, `d3d0706`, 2026-10-01 | `flutter doctor -v`; `tool/api_probe_app.dart` (prints status, bytes, ms) | `docs/api-feasibility.md` | Environment; status, byte counts and timings | Derived | **Keep** |
| `map-spike/*.jpg` (8 files) | 469,690 in all | `6dc0fd3`, 2026-10-03 | Screenshots of the removed `tool/map_spike` | `docs/map-feasibility.md` §1; `docs/testing.md` (P2-M0 rows and the probe section) | Rendered OneMap Default and Night tiles, OSM tiles (attribution collapsed to an icon), CARTO watermark tiles, a busrouter ride line and a Valhalla walk | OneMap, ODbL, LTA-web | **Owner decision C-3** (§6) |

### 3.2 `test/fixtures/`

| Path | Bytes | Added | Written by | Consumers | Content | Class | Recommendation |
|---|---|---|---|---|---|---|---|
| `two-hr-forecast.json`, `uv.json`, `pm25.json`, `psi.json` | 5,917; 775; 623; 1,453 | `226a115`, 2026-10-01 | `curl`, once per dataset (`docs/testing.md`, 2026-10-01 M1 row) | `test/features/environment/nea_parsers_test.dart`, `environment_locator_test.dart`, `test/core/retry_after_provider_test.dart` | Unmodified data.gov.sg real-time responses of 2026-10-01: 47 forecast areas, regions, readings, timestamps | SODL | **Keep** (tests need real payloads, CLAUDE.md "NEA parser tests"); **add the SODL notice** (§5, C-1) [P] |
| `busrouter/synthetic_busrouter.dart`, `README.md` | — | PR #92 (A-1) | Hand-made | Three busrouter test files | Synthetic (`F` codes, "(fake)" names) | Project | **Keep** |
| `onemap/synthetic_onemap.dart`, `README.md` | — | PR #98 (A-4b) | Hand-made | The OneMap test files | Synthetic search responses | Project | **Keep** |
| `arrivelah/synthetic_arrivelah.dart`, `README.md` | — | PR #99 (A-4a, A-4c) | Hand-made | The ArriveLah test files | Synthetic arrival responses | Project | **Keep** |

### 3.3 `assets/`

| Path | Bytes | Added | Written by | Consumers | Content | Class | Recommendation |
|---|---|---|---|---|---|---|---|
| `mrt_stations.json` | 66,947 | `2ca8c9f`, 2026-10-02 | `dart run tool/build_mrt_asset.dart` | `lib/core/config/app_config.dart` (`mrtStationsAsset`), `lib/features/journey/data/mrt_asset.dart`, `test/features/journey/mrt_test.dart`, `tool/journey_smoke.dart` | 613 LTA exits grouped into 188 stations; a `source` block (dataset, ID, publisher, "Singapore Open Data Licence v1.0", retrieval date); seven code-only mappings whose evidence quotes a OneMap label and a distance | SODL; the evidence strings are short OneMap labels (station names) and derived distances [A] | **Keep** (the app needs it); **add the licence link** (§5, C-2) [P] |

### 3.4 `integration_test/fakes/`

| Path | Content | Class | Recommendation |
|---|---|---|---|
| `fake_place_search_repository.dart` (3,220 B, `d53bf31`, 2026-10-02; imported by 21 files in `test/` and `integration_test/`) | Five places with real names, full OneMap-style addresses, postcodes and coordinates rounded to four decimals (VivoCity, ION Orchard, Our Tampines Hub, two Bishan MRT entries) | OneMap-like records [A: their source was not traced; the address strings match OneMap's format] | **Handled by another change**; inventoried only. Replace with synthetic places [P] |
| `fake_environment_repository.dart` (3,148 B, `d53bf31`) | Invented readings and forecasts; the five NEA region label locations (`1.41803, 103.82`, …) as in `pm25.json`, and three forecast-area positions equal to (Bishan, Jurong East) or close to (Tampines) the label locations in `two-hr-forecast.json` | SODL (positions); Project (values) | **Keep**; cover by the same notice as the NEA fixtures (C-1) [P] |
| `fake_bus_network.dart` (3,973 B) | Synthetic stops (codes like `BSH1`, names "(fake)"), four real MRT station names with rounded positions | Project; station names are public facts [A] | **Keep** |
| `fake_bus_arrival_repository.dart`, `fake_route_geometry.dart`, `fake_map.dart`, `fake_location_service.dart`, `fake_palette_store.dart`, `test_app.dart` | Synthetic arrivals ("ArriveLah (fake)"), a test polyline encoder, map and storage fakes | Project | **Keep** |

### 3.5 `tool/`

| Path | Embedded or written data | Class | Recommendation |
|---|---|---|---|
| `probe_apis.sh`, `probe_map.sh` | Print body heads to the terminal. Since PR #95 (A-5c) the usage lines no longer redirect into `docs/`, and the headers say to run them only with the owner's approval and never commit the output | — | **No action** |
| `place_search_eval.dart` | Writes `docs/probe-output/place-search-eval.json` by default; embeds the 51-query list with expected keywords and postcodes (project-written) | Project | **Write to `build/probe-output/`** and say so in its header [P] |
| `route_geometry_probe.dart`, `api_probe_app.dart`, `journey_smoke.dart` | stdout only; one ride; status lines; 12 place pairs as OneMap query, name and postcode (public names) | Project, Derived | **Keep** |
| `map_performance_probe.dart` | One position (Bishan); writes `build/` | Project | **Keep** |
| `build_mrt_asset.dart` | Downloads the SODL dataset and writes the asset (§3.3) | SODL | **Keep**; C-2 would add the link here |
| `e5_transfer_bench/expected_results.txt` (22,693 B, `9141fde`, 2026-11-06) | The benchmark's deterministic output: counts, percentages, 5-digit stop codes, service numbers, stop counts, road names (DataMall, SODL), the named pairs' labels | Derived; stop codes and service numbers come from lta.gov.sg via busrouter (LTA-web) as identifiers, not records [A] | **Owner decision C-5** |
| `e5_transfer_bench/bench.dart` | `namedFixtures`: 12 labelled pairs of interchange stop codes | Project labels; LTA-web identifiers [A] | **Keep** (with C-5) |
| `e5_transfer_bench/*.min.json` | Never committed; `.gitignore` refuses them | — | No action |
| `icon/` | The app art | Project | **Keep** |

### 3.6 `lib/`, `test/` inline data and `docs/` text

| Where | What | Class | Recommendation |
|---|---|---|---|
| `lib/features/journey/data/mrt_grouping.dart` | Seven code → station-name mappings with OneMap evidence strings (label and distance) | Public names; Derived [A] | **Keep** |
| `lib/core/config/` (`JourneyConfig`) | Two E2 constants derived offline from DataMall BusRoutes (`docs/data-sources.md`) | Derived (SODL source) | **Keep** |
| `test/**` outside `test/fixtures/` | Hand-written positions and codes (e.g. `'00123'`, `F` codes, rounded MRT exits in `mrt_test.dart`); Google's documented example polyline in `polyline_codec_test.dart` | Project; identifiers [A] | **Keep** |
| `docs/data-sources.md`, `docs/testing.md`, `docs/assumptions.md`, `docs/api-feasibility.md`, `docs/architecture.md` | Response schemas (field names), short error messages, aggregate observations (e.g. "141 buses sampled"), a few stop codes and service numbers | Derived; short functional text [A] | **Keep** |
| `docs/e5-gate2-implementation-plan.md`, `docs/testing.md` E5 rows | A few benchmark journeys (service numbers, stop codes, stop counts) | Derived [A] | **Keep** (with C-5) |
| `docs/images/*.png` (3 files, 1,148,408 B, `34a1309`, 2026-10-05; README "Screenshots") | Replaced (C-4, §9): demonstration screenshots over synthetic data and synthetic tiles | Project-made | **Done** (C-4) |

## 4. Actions in the redaction PR [P]

Branch `chore/redact-probe-output`, for review:
- In the three probe outputs, each non-binary, non-empty `body:` line becomes
  `body: [redacted 2026-11-07: captured <provider> data, see docs/captured-data-inventory.md]`. Status lines, CORS and
  cache headers, byte counts, timings and the clause check stay.
- `docs/probe-output/place-search-eval.json` is removed, and `.gitignore` refuses a new copy there.
- `tool/place_search_eval.dart` writes `build/probe-output/place-search-eval.json` (git-ignored), and its header says
  the raw results are captured provider records. No download is added.
- `docs/api-feasibility.md`, `docs/map-feasibility.md` and the probe section of `docs/testing.md` say what was redacted
  and removed.
- History is not rewritten: the original bodies stay in `main`'s history (as for A-2).

## 5. Meeting the SODL notice condition [P]

The A-4 audit quotes the licence: it requires "a conspicuous notice acknowledging the source of the datasets" with "a
link to the most recent version of this Licence" [C, from that audit]. What the tree has [C]:
- **NEA fixtures:** no notice. JSON has no comments, and nothing next to the files names the source.
- **`fake_environment_repository.dart`:** no notice for the copied positions.
- **MRT asset:** a `source` block naming the dataset, publisher and "Singapore Open Data Licence v1.0", but no link.
- **README and the app's footer:** since PR #94 (A-5b), the footer has a notice for arrival times with a link to the
  licence (`openDataLicenceUri`), and the README links it in the arrivals credit. The NEA and MRT credits on the same
  footer name the licence without their own link.

Proposal:
1. **C-1:** add `test/fixtures/NOTICE.md` (Markdown, which the folder's JSON-refusing rules do not block) naming the
   four data.gov.sg datasets, the retrieval date (2026-10-01) and the licence link
   `https://data.gov.sg/open-data-licence`, and add one comment line with the same notice to
   `fake_environment_repository.dart`. A suggested form, following the arrivals notice of A-5b (`arrivalsLicenceNotice` in
   `lib/core/config/app_config.dart`) [A: data.gov.sg's own suggested wording not re-read in this inventory]: "Contains information from the 2-hour Weather Forecast,
   UV Index, PM2.5 and PSI datasets accessed on 1 October 2026 from data.gov.sg, which is made available under the
   terms of the Singapore Open Data Licence version 1.0, https://data.gov.sg/open-data-licence".
2. **C-2:** add a `licenceUrl` field to the asset's `source` block through `tool/build_mrt_asset.dart` and rebuild the
   asset offline from the same input (`--input … --retrieved 2026-10-01`), so the data does not change; extend the
   asset test in `mrt_test.dart` to expect it.
3. **C-6 (outside this approval, noted only):** whether the one licence link in the footer (A-5b, for arrivals) also
   serves the NEA and MRT credits, or each needs its own notice in the A-5b form. This touches `lib/` and belongs to the
   runtime assessments, not to this inventory.

## 6. Decisions requiring owner approval

| ID | Decision | Recommendation |
|---|---|---|
| C-1 | Add the SODL notice for the NEA fixtures and the fake environment positions (§5) | Approve, as a small docs-and-comment PR |
| C-2 | Add the licence link to the MRT asset through its generator (§5) | Approve, in its own PR with the asset test |
| C-3 | `docs/probe-output/map-spike/*.jpg`: keep, or remove the OneMap and CARTO screenshots (OneMap clause 3(b) names "publicly display" and "reproduce"), or all eight | Remove the OneMap and CARTO ones, keeping the run-log text that describes them; keep the OSM ones only if the attribution question is settled (collapsed to an icon in the spike) |
| C-4 | `docs/images/*.png` (README screenshots with live OneMap tiles, LTA stop names, ArriveLah times) | Owner's call: they show the product. If they stay, the README's attribution line names the providers. New screenshots over the fake providers would drop the LTA and ArriveLah data, but the map tiles would still be OneMap's |
| C-5 | `tool/e5_transfer_bench/expected_results.txt`: keep (derived output with LTA stop codes and service numbers as identifiers), or reduce it to counts | Keep: it is the benchmark's check, it holds no stop names from lta.gov.sg (its README says so), and identifiers are not records [A] |
| C-6 | Give the NEA and MRT credits in the app footer a notice and link in the A-5b form, or rely on the arrivals link | Consider with the runtime assessments (A-5, A-5b) |
| C-7 | History: the redacted bodies and the removed JSON stay in `main`'s history (since `d3d0706`, `67fec7b` and `055a6dd`) | Leave it as it is, as recommended for A-2 |

## 7. Owner decisions, 2026-11-07

- **C-1 approved.** The NEA fixtures' notice is `test/fixtures/NOTICE.md` (source, retrieval date, the Singapore Open
  Data Licence v1.0 and its link); `fake_environment_repository.dart` carries the same notice in a comment. The notice
  names only the NEA data and says that no other test data is under that licence.
- **C-2 approved, with a change to §5 item 2:** the asset's runtime schema is not changed. The licence link and notice
  are in `docs/data-sources.md` (the MRT asset's licence row) and in `tool/build_mrt_asset.dart`'s header; the asset's
  existing `source` block already names the dataset, publisher, licence and retrieval date.
- **C-3 approved conditionally**, **C-4 and C-5 for further review**, **C-6 approved** (source-specific notices),
  **C-7 deferred** (no history rewrite; exposure stays documented in §6). Each is handled in its own change.

## 8. C-3 done (owner approval 2026-11-07, conditional)

The eight `docs/probe-output/map-spike/*.jpg` were reviewed against the condition "publication rights cannot be
established and not needed for active tests":
- **Rights not established for any of them.** Five show OneMap tiles (OneMap Terms of Use 3(b) names "publicly
  display", "reproduce" and "publish"). One shows CARTO watermark tiles (CARTO's terms not read). The two OSM ones also
  draw a busrouter ride line (LTA-web geometry, redistribution not established), and their OSM attribution is collapsed
  to an icon. **[A]** for the OSM tiles' own licence (not re-read).
- **Not needed by any test:** only `docs/map-feasibility.md`, `docs/testing.md` and this inventory cite them.

So all eight were removed from the tree. `docs/map-feasibility.md` now describes what each showed, in original text.
They remain in Git history (`6dc0fd3`; C-7, no rewrite).

## 9. C-4 done (owner approval 2026-11-08)

The three `docs/images/*.png` (live OneMap tiles, busrouter stop names, ArriveLah times, NEA readings) were replaced by
screenshots of the app over synthetic data, made by `integration_test/demo/readme_screenshots.dart` (a generator run
with `flutter drive`, not a test; no `lib/` change):
- places, stops, services, arrival times and the ride line are the integration tests' fakes; the generator renames the
  origin side's stops and MRT station (the shared fakes still say Bishan) to "North … (fake)";
- the map tiles are an invented street grid drawn by the generator; no OneMap tile or logo is fetched or shown (the
  logo is the fakes' transparent image);
- the Conditions card, whose area names come from NEA data, is kept out of frame;
- each image has a "DEMONSTRATION DATA" strip, and the README says the map's attribution line and the arrivals credit
  are the app's standard credits and describe no real data there.

Same names, sizes 824 × 1830 as before. The old images remain in Git history (`34a1309`; C-7, no rewrite).
