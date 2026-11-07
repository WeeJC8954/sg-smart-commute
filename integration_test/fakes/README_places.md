# Fake places (synthetic)

`fake_place_search_repository.dart` answers place searches in widget and integration tests from hand-made `Place`
values. Until 2026-11-07 five of them reused real OneMap records (names, addresses, postcodes and coordinates of
VivoCity, ION Orchard, Our Tampines Hub and Bishan MRT CC15/NS17). The owner decided on 2026-11-07 to replace them
with synthetic places, as A-1 and A-4 did for fixtures (`test/fixtures/onemap/README.md`). Nothing here is copied from
OneMap or any other source:
- names end in "(fake)"; roads are "FAKE WALK", "FAKE TURN", "FAKE LANE", "FAKE ROAD";
- postcodes are six digits in sectors that do not exist in Singapore: `009902` (keeps the leading-zero case) and
  `9908xx` / `990904`;
- positions are round numbers, chosen so the fake bus network gives the same journeys and the same estimated minutes
  as before. Bus stops and MRT exits are placed from the place positions in code (`_near`, `_offset` in
  `fake_bus_network.dart`), so the coupling is explicit.

| Place (query → result) | Replaces | Position | What the tests rely on |
|---|---|---|---|
| `Bay Mall` → `BAY MALL (fake)`, postcode `009902` | VivoCity | 1.3000, 103.7750 | Main journey from the GPS fix: F20 (suggested), F10, F30 to stop BAY1 40 m away; rides 31 / 32 / 30 min, totals 35; G1 / G2 in the E2 tests 29 / 77 min; nearest MRT `FAKE BAY MRT STATION` 116 m; postcode search with a leading zero |
| `City Tower` → `CITY TOWER (fake)`, `990802` | ION Orchard | 1.3200, 103.8100 | F30 from BSH1 to CTY1, 1 stop, 17 min; nearest MRT `FAKE CITY MRT STATION`; no direct bus from East Hub |
| `East Hub` → `EAST HUB (fake)`, `990803` | Our Tampines Hub | 1.3650, 103.9250 | Manual origin: nearest fake forecast area "Tampines" (3.0 km) and the east region, so "Tampines area"; only EST1 within 800 m (F40 to MID1), so no bus to City Tower; nearest MRT `FAKE EAST MRT STATION` 512 m |
| `North MRT` → `NORTH MRT STATION (FN1) (fake)` and `(FN2) (fake)`, `990811` / `990812` | Bishan MRT CC15 / NS17 | 1.3515, 103.8480 / 1.3505, 103.8490 | Two results for one query (the second picked), typed as stations; within 300 m of the fix (96 m and 65 m), so walk-only as a destination; from FN2, F30 at BSH1 to City Tower |

Kept as they were, with the reason:
- the fake GPS fix (1.3508, 103.8485, `bishan` in the tests), stops BSH1 / BSH2 and the fake `BISHAN MRT STATION`:
  hand-picked test values, not OneMap records. The station's exit was the NS17 record's exact position; it moved to
  1.3512, 103.8481 (63 m from the fix). FN1 and FN2 are 96 m and 124 m from the real records because they must stay
  within walking distance of the fix;
- the fake environment (`fake_environment_repository.dart`): NEA area names and label positions, data.gov.sg data under
  the Singapore Open Data Licence (like the NEA fixtures);
- MID1 / MID2 keep their names but moved (1.3200, 103.8300 and 1.3100, 103.7900), so the ride lengths stay inside the
  same whole-minute windows. With the mall as an origin the nearest forecast area is now "Jurong East" (was "Bishan");
  no test checks it.

Test-local places were made synthetic too: `904 FAKE ROAD 4 SINGAPORE 990904 (fake)` (the block search, typed
`Blk 904 Fake Road 4`, replaces a real HDB address and postcode), `ISLAND JETTY (fake)` (1.4000, 103.9700: no stop
within 800 m, 5.9 km from the nearest fake exit) and `PARK EDGE (fake)` (walk-only, 214 m from the fix).

## Impact assessment (2026-11-07)

Readers of the fake (via `buildTestApp` or by import), with what they rely on:

| Reader | Relies on |
|---|---|
| `test/features/places/place_search_widget_test.dart` | Exact names, queries, the address subtitle, the postcode search, the two-result station query and its postcodes, the block search, `From:` / `To:` labels |
| `place_search_session_test.dart`, `place_search_config_test.dart` | Normalised query keys (held and released in order); a 4-character query under a 5-character minimum |
| `test/app/accessibility_test.dart`, `focus_continuity_test.dart`, `focus_ring_app_test.dart`, `focus_mode_invariants_test.dart`, `home_screen_test.dart`, `about_dialog_test.dart`, `test/features/appearance/palette_change_invariants_test.dart` | Names and queries only; at 360 × 780 dp and 2× text the mall's result must stay on screen (a longer name such as `FAKE BAY MALL (fake)` wrapped and pushed it off, so the names have no `FAKE` prefix) |
| `test/widget_test.dart`, `integration_test/fallback_path_test.dart` | East Hub as origin: "Tampines area" and the east readings; no bus to City Tower; the MRT alternative |
| `test/features/journey/journey_widget_test.dart` | Journeys, stop names (`toward Bay Mall (fake)`, `Alight at CTY1 — …`), walk minutes from positions, nearest MRT at both ends, walk-only, no stop nearby, "no MRT within" distances |
| `journey_estimate_widget_test.dart`, `journey_estimate_invariants_test.dart` | Ride and total minutes, which follow the stop-to-stop distances |
| `test/features/bus_arrival/arrivals_widget_test.dart`, `journey_arrivals_test.dart`, `option_selection_test.dart` | Boarding stops BSH1 / BSH2, the plan for each destination |
| `test/features/map/journey_map_card_test.dart`, `map_scene_test.dart`, `fake_route_geometry_test.dart` | Markers, the ride's stops and line (straight through stop positions), walk connectors, MRT markers and labels, camera bounds holding the ride |
| `integration_test/happy_path_test.dart` | The main journey end to end (not run on this PC) |
| `tool/map_performance_probe.dart` | Query and result of the main journey (dev probe) |

Not readers of the fake, so unchanged: `origin_controller_test.dart` (its own points), `place_query_test.dart` (query
strings only), `mrt_test.dart` (the bundled SODL asset), `geo_test.dart` and `environment_locator_test.dart` (points
against the real NEA payloads), the "Vivo" typed in `palette_app_test.dart` and `motion_test.dart` (no result read),
the search hint in `lib/`, and the live probes in `tool/` (they query real APIs by design).
