# E5 Gate 2: Implementation Plan (one-transfer Bus → Bus)

**Status:** Gate 2 plan-only deliverable, 2026-11-06, for owner review. **No E5 production code exists or is
authorized**; Gate 3 starts only after the owner approves this plan and rules on §12. This PR adds this plan, a
development-only benchmark (`tool/e5_transfer_bench/`, owner ruling F5) and its fixed input
(`test/fixtures/busrouter/snapshot-2026-11-06/`). Nothing under `lib/`, `web/`, `android/` or `pubspec.*` changes.

**Governing documents:** `docs/e5-gate0-discovery-report.md` (Gate 0; the owner's rulings are its §13),
`docs/sg-smart-commute-next-phase-master-plan.md` (gates, §10 testing), `CLAUDE.md`, `docs/assumptions.md`.

**Tags** (as in Gate 0): **[C]** confirmed (read from code or data, or measured, with its source); **[A]** assumption,
not verified; **[P]** proposal, needs approval; **[D]** owner decision already made.

**Gate 1.** No separate Gate 1 report (G0-1 [D]): the Gate 2 measurements (§2) narrow the design (same-stop only, a
fixed detour limit) but do not change it materially.

## 1. Decisions in force [D] and what Gate 2 had to resolve

| Ruling | In force | Resolved here |
|---|---|---|
| A1 | Ordered legs, `WalkLeg` and `BusLeg` only; `planDirectBus`, `BusOption`, `DirectBusOptions` keep their behaviour; no MRT or multimodal classes | Exact types (§4.1) |
| F1 | Bounded one-transfer search, forward order, different services, no loops, no duplicates | Detour limit: **2.5** recommended (§2.2) |
| F2 | Same stop allowed; ≤ 150 m only if the data can tell a plausible walk from a barrier | **Same stop only** recommended (§2.3) |
| F3 | Search only when the planner finds no direct bus; direct results, order, scores, arrivals and map unchanged | Where the search runs (§4.4) and the regression guard (§6, T3) |
| F4 | Waiting excluded and disclosed; no invented headways; no transfer-stop arrivals | Wording (§4.6) |
| F5 | §10.4 budgets provisional; a reproducible Chrome benchmark before implementation | Benchmark kept; measured; **targets kept** (§2.4) |
| F6, F8 | Failure handling and the leg-list card / two-ride map approved in concept | Exact wording, UI and accessibility requirements (§4.6–§4.9) |
| F7 | busrouter data only; no new provider, host, key or dependency | Nothing new is loaded (§4.4) |

## 2. Pre-implementation evidence (benchmark) [C]

### 2.1 Method

- **Tool:** `tool/e5_transfer_bench/` (how to run and check it: its `README.md`). The deterministic results it must
  reproduce are in `tool/e5_transfer_bench/expected_results.txt`.
- **Fixed input:** busrouter `stops.min.json` and `services.min.json` fetched 2026-11-06 12:27 UTC, unmodified, in
  `test/fixtures/busrouter/snapshot-2026-11-06/` with sizes and SHA-256 (`PROVENANCE.md`). 5,209 stops, 604 services,
  801 directions, 26,957 (stop, direction, position) entries: the same counts as Gate 0's fetch.
- **App code:** the app's own parser, `planDirectBus` and E2 `estimateBusMinutes`. The transfer search is a prototype
  of Gate 0 §6 with the F1 rules (`transfer_search.dart`), not the implementation.
- **Pairs:**
  - a seeded sample: seed 20261106, 500 stop pairs at least 1.5 km apart, each end moved 0.0004° in latitude and
    longitude (about 63 m) off its stop. `planDirectBus` found a direct bus for 199 (39.8%) and no direct bus for
    **301**, the pairs every figure below is about;
  - 12 named stop pairs with no direct bus, from interchange to interchange: Toa Payoh → Yishun (10.8 km) up to
    Changi Village → Boon Lay (31.9 km).
- **Platforms:** Dart VM 3.13.2, and Chrome 156 (headless) running the same code compiled by `dart compile js -O4`,
  on the Windows 11 dev PC. **The deterministic output was identical on both** (`diff` empty, every run).
- **Not measured [A]:** a phone, demand-weighted pairs, real travel times (the minutes are E2 estimates with no
  wait).

### 2.2 F1: detour limit 2.0, 2.5 or 3.0

Detour = straight-line metres between consecutive stops of both rides ÷ the straight line from origin to destination.
Same-stop transfers; best journey per pair:

| Limit | Pairs served (of 301) | Detour p50 / p95 / max | Minutes p50 / p95 (no wait) | Straight-line speed p5 / p50 |
|---|---|---|---|---|
| 2.0 | 222 (73.8%) | 1.45 / 1.87 / 1.98 | 84 / 145 | 7.6 / 10.3 km/h |
| **2.5** | **229 (76.1%)** | 1.47 / 2.12 / 2.36 | 84 / 145 | 7.1 / 10.2 km/h |
| 3.0 | 230 (76.4%) | 1.47 / 2.26 / 2.88 | 84 / 146 | 6.7 / 10.2 km/h |
| none | 230 (76.4%) | 1.47 / 2.50 / 4.59 | 86 / 146 | 6.1 / 10.1 km/h |

- **2.0 → 2.5** adds 7 pairs. The 6 the run lists have detours 2.05–2.35, take 80–127 min against 122–215 min on foot, and
  run at 5.4–7.4 km/h in a straight line. Slow, but each is the only bus route found, and the MRT section stays below
  it. Example: 17021 → 57011, Bus 175 (36 stops) then Bus 980 (32 stops), changing at 01112, 12.8 km, 110 min.
- **2.5 → 3.0** adds 1 pair (detour 2.70, 130 min for 14.6 km). **3.0 → none** adds no pair.
- **Without a limit the ranking gets worse, not only the detours.** The median estimate rises from 84 to 86 min: the
  stop-count score prefers some long, few-stop detours (up to 4.59) over a shorter journey.
- **No journey at any limit was slower than walking the whole way.** The named fixtures' same-stop detours are 1.07–1.70,
  so no limit changes them.
- **Recommendation [P]: 2.5, final** (G2-1). It keeps 99.6% of the coverage of 3.0 (229 of 230) and refuses the
  4.59-type detours. 2.0 would drop 7 plausible journeys and return "no route" for them.

### 2.3 F2: same stop only, or a walk of up to 150 m

| Transfer | Pairs served (of 301), limit 2.5 | Notes |
|---|---|---|
| **Same stop** | **229 (76.1%)** | |
| ≤ 150 m | 241 (80.1%) | +12 pairs; in 85 more pairs a walking transfer becomes the best journey |

- **What the data holds [C].** A stop is `[lng, lat, name, road]` (`busrouter_parser.dart`). Nothing says on which side
  of a road a stop is, where crossings, overhead bridges, barriers or expressways are, or whether a path is step-free.
  The app's walk estimate is a straight line × 1.3 and "cannot see overhead bridges, barriers, expressways or rivers"
  (`walking.dart`).
- **What the 12 extra pairs need [C].** 11 of the 12 walks join two stops with the same road name, mostly an
  opposite-side pair: 46499 "Opp Blk 402" → 46491 "Blk 402" (Woodlands Ave 3, 49 m), or 68119 → 68111 at Piccadilly
  Circus/TPE (Jln Kayu, 89 m). Each needs a road crossing that the data cannot confirm. The other one crosses a
  junction: 04179 Bras Basah Rd → 01012 Victoria St, 126 m.
- **The walk also makes the ranking worse [C].** The stop-count score counts a walk only by its minutes, so it prefers a
  walking transfer with fewer stops even when the ride is longer:
  - Bedok Int → Punggol Int: the same-stop best is Bus 69 then Bus 118, 49 min. With the walk it becomes Bus 24 then
    Bus 44, 68 min, through a 97 m walk at 95151 → 95159 and a detour of 1.99.
  - Toa Payoh Int → Yishun Int: 48 min becomes 60 min.
- **Recommendation [P]: same stop only for the first release** (G2-2), as the owner's F2 condition foresees. The data
  cannot tell a plausible walk from a barrier, and the walk would add 12 of 301 pairs (4.0 points) at the cost of
  worse best journeys in others. A later release could add opposite-pair transfers only with a source of crossing
  data, which F7 excludes for now.

### 2.4 F5: performance in Chrome (dart2js)

Five Chrome runs and five VM runs on 2026-11-06 (ranges across runs; prototype search, same stop, limit 2.5, over
the 301 no-direct pairs, 903 timed queries per run):

| Measure | Chrome 156 (dart2js -O4) | Dart VM | §10.4 target |
|---|---|---|---|
| One-transfer search, warm, median | 1.7–2.8 ms | 1.9–2.2 ms | |
| One-transfer search, warm, p95 | **3.8–5.5 ms** | 3.4–3.8 ms | < 50 ms Chrome, < 20 ms VM |
| One-transfer search, warm, max | **10.3–16.5 ms** | 5.0–6.4 ms | < 150 ms Chrome |
| First (cold) search | 9.5–10.4 ms | 20.9–23.9 ms | |
| Transfer index build, once per network | **8.2–12.6 ms** | 22.5–27.2 ms | < 100 ms Chrome |
| `planDirectBus` (today's planner), warm, p95 | 5.8–6.9 ms | 4.5–4.9 ms | |
| Parse (`jsonDecode` + parser), cold | 15.7–20.8 ms | 39.9–47.3 ms | |

- Chrome rounds `performance.now()` to 0.1 ms, so these are 0.1 ms resolution.
- **Every target holds with a wide margin [C]:** 8–9× in Chrome, 5× on the VM. A journey with no direct bus costs today's planner plus the
  search: under about 12 ms p95 in Chrome on this PC.
- **Recommendation [P]: keep the §10.4 targets unchanged** (G2-3), and add one: the first search of a session, index
  build included, under 100 ms in Chrome. The margin is kept on purpose: no phone was measured, and a mid-range
  Android phone's Chrome could be several times slower [A].
- Gate 3 points the benchmark at the real implementation and records the same table.

### 2.5 Ranking among transfer journeys

Under F3 option 1, transfer journeys are ranked only against each other, so a fixed transfer penalty changes nothing
and is dropped (Gate 0 §13). The score is the direct planner's, extended:
`walk to stop + 1.5 × stops on bus 1 + 1.5 × stops on bus 2 + walk from stop` (minutes and stops; no wait).

- **[C]** In 38 of the 201 sample pairs with two or more journeys shown (19%), a lower-ranked journey has a shorter E2
  estimate: by a median of 3 min and at most 35 min.
- **Recommendation [P]: keep the stop-count score** (G2-4). This is the same rule as the direct planner, and E2 stays
  display-only, as its assumptions row requires ("never in the planner score"). Each option shows its own estimate,
  so a rider can compare. The alternative is to rank transfer journeys by E2 minutes. That would make E2 part of
  planning for transfers only, against the E2 rule, with an estimate calibrated on off-peak first and last trips.

### 2.6 Other observations

- **[C]** Several best journeys use express or limited services (`851e`, `97e`, `43e`, `89e`, `174e`). busrouter has no
  operating hours, so neither the direct planner nor E5 can tell that such a bus is not running now. This is an
  existing limit of the direct planner, not new in E5. The card's wording does not claim the bus runs now (§4.6).
- **[C]** Coverage criterion of Gate 0 §10.3 ("at least 45% of no-direct pairs") is exceeded: 76.1%. The Gate 3
  criterion becomes exact (T2.14): the implementation serves exactly the pairs the benchmark does on the pinned input,
  or each difference is explained.

## 3. Scope

**In E5 (first release) [P]:** one transfer, Bus → Bus, at the **same stop**, searched **only** when `planDirectBus`
returns `NoDirectBus`; up to 3 journeys with the direct options' "Suggested" / "Alternatives" / "Select" pattern; per-leg
E2 estimates and a total excluding waiting; two ride lines on the map.

**Not in E5 [D/P]:** transfers when a direct bus exists (F3); walking transfers (§2.3); two or more transfers; MRT legs
or any rail or multimodal class (A1); headways, timetables, operating hours or invented transfer waits (F4); live
arrivals at the transfer stop (F4) and, as proposed, for transfer journeys at all (G2-6); any new host, provider, key
or dependency (F7); routed walking.

## 4. Design [P]

### 4.1 Domain model (A1): `lib/features/journey/domain/journey_leg.dart` (new)

```dart
sealed class JourneyLeg { const JourneyLeg(); }

/// A walk at either end, as the direct planner estimates it.
final class WalkLeg extends JourneyLeg {
  const WalkLeg(this.walk, this.stop, {required this.toStop});
  final WalkEstimate walk;
  final BusStop stop;   // the stop walked to (toStop) or from
  final bool toStop;
}

/// One ride on one service, in one direction: the same fields as BusOption's ride.
final class BusLeg extends JourneyLeg {
  final BusService service;
  final int direction;
  final BusStop board;
  final int boardIndex;  // first occurrence rules as planDirectBus
  final BusStop alight;
  final int stops;       // >= 1
  final String towardName;
  final bool isLoop;
}

/// Walk, bus, bus, walk. The change is at the same stop (bus 1 alights where bus 2 boards).
class TransferJourney {
  factory TransferJourney(WalkLeg toStop, BusLeg first, BusLeg second, WalkLeg fromStop,
      {required double score, required double detourRatio});  // checks the invariants
  final List<JourneyLeg> legs;   // unmodifiable, in travel order
  BusLeg get first; BusLeg get second; BusStop get transferStop;
  final double score; final double detourRatio;
}
```

- **Invariants**, checked in the factory and throwing an `ArgumentError` (the planner never builds a bad one):
  - the legs are walk, bus, bus, walk;
  - `first.alight.code == second.board.code`;
  - the two service numbers differ;
  - each `stops >= 1`;
  - the walks attach to `first.board` and `second.alight`.
- `BusOption`, `DirectBusOptions` and `planDirectBus` are not changed. No `RailLeg` and no transfer `WalkLeg` exist,
  because nothing would use them.
- **New plan variant**, added to the sealed `JourneyPlan` in `direct_bus_planner.dart` (a sealed class's subtypes must
  be in its library; it is the only change to that file):
  `final class OneTransferOptions extends JourneyPlan { journeys (1–3), radiusMeters }`.

### 4.2 Search: `lib/features/journey/domain/transfer_planner.dart` (new)

- `TransferIndex.build(BusNetwork)`: for each stop, its (service, direction, position) entries, plus cumulative
  straight-line metres per direction. Pure.
- `JourneyPlan planOneTransfer(TransferIndex, LatLng origin, LatLng destination, {TransferConfig})` returns
  `OneTransferOptions` or `NoDirectBus(radiusMeters: 800)`. The algorithm is Gate 0 §6 as the prototype implements it,
  without the neighbour grid (same stop only):
  - **Candidates:** stops within 400 m of each end, then once at 800 m if 400 m finds nothing, as `planDirectBus`.
  - **Forward:** from each origin candidate's occurrence `i`, every later stop `k` that is the first occurrence after
    `i` (the direct planner's rule) labels bus 1 at that stop. Only the best label per (stop, service, direction) is
    kept.
  - **Backward:** from each destination candidate's occurrence `j`, every earlier position `m` for which `j` is the
    first occurrence after `m` labels bus 2.
  - **Join:** at each stop holding both labels, every bus-1 × bus-2 pair with different service numbers. Reject it if:
    - bus 2 boards or stops at a stop bus 1 used before the transfer stop (loop rule);
    - the detour is over `TransferConfig.detourLimit` (2.5; a journey at exactly 2.5 is kept).
  - **Ranking:** keep the best journey per (service 1, service 2), then sort by score, total stops, service 1 and
    service 2 in natural order (`compareServiceNumbers`), then the board, transfer and alight stop codes. Return the
    first `TransferConfig.maxOptions` (3).
- **Known limit [C]:** a best label rejected at the join is not replaced by a worse label for the same (stop, service,
  direction). The benchmark measures with this rule. It is recorded in `docs/assumptions.md`.

### 4.3 Config: `lib/core/config/app_config.dart`

Add `abstract final class TransferConfig { detourLimit = 2.5; maxOptions = 3; }`, documented. Also a
`docs/assumptions.md` row: "One-transfer journeys (E5)", with the score, the detour definition, same stop only, the
label limit, and the evidence in §2.

### 4.4 State: `journey_providers.dart`

- `journeyPlanProvider`: after `planDirectBus`, **only if the result is `NoDirectBus`**, await
  `transferIndexProvider.future` and return `planOneTransfer(...)`. Every other result is returned as it is today: the
  same object, with no index built.
- `transferIndexProvider` (new): a `FutureProvider<TransferIndex>` built from `busNetworkProvider.future`, once per
  session and only on the first `NoDirectBus`. The busrouter data is the same, so no request, host or CSP change is
  added (F7).
- A walk-only journey still never loads bus data. A bus data failure is the existing `StaticDataUnavailable`, shown
  with the existing Retry.
- **Selection:** `OptionSelection` and `selectedOptionIndex` accept a `OneTransferOptions` too (the plan stays held by
  identity, so a selection never carries over to a new journey). For a direct plan the behaviour is unchanged.

### 4.5 Arrivals

`journeyArrivalsProvider` already returns null for any plan that is not `DirectBusOptions` (`bus_arrival_providers.dart`).
**Proposed: no change**, so a transfer journey requests no live arrival at all (G2-6) and the arrivals code is
untouched (F3, F4).

### 4.6 Journey card wording (F4, F6, F8)

A new `_Plan` case, `OneTransferOptions`. It reuses `_Option`'s layout: summary, then steps, "Suggested" then
"Alternatives" with collapsible steps and "Select". Exact texts [P], kept as `JourneyCard` constants so tests use them:

| Where | Text |
|---|---|
| Title above the options | `No direct bus` (the existing title) |
| Line under it | `These routes change buses once, at the same stop.` |
| Option summary | `Bus 88, then Bus 851e` (each service in its badge) |
| Trip line (when both rides have an estimate) | `About 50 min · excl. waiting for both buses` |
| Trip semantics | `Estimated trip, about 50 minutes, not including waiting for either bus` |
| Step 1 | `~3 min walk (est.) to Bus Stop 52009 — Toa Payoh Int` (today's wording) |
| Step 2 | `Bus 88 toward <towardName> · 12 stops` + the E2 ride detail `· ~20 min ride (est.)` |
| Step 3 | `Change at Bus Stop 54011 — <name>: board Bus 851e at the same stop. Waiting time not included.` |
| Step 4 | `Bus 851e toward <towardName> · 10 stops` + ride detail |
| Step 5 | `Alight at 59009 — Yishun Int` |
| Step 6 | `~2 min walk (est.) to destination` |
| Under the options, instead of the arrivals footer | `Live arrivals are shown for direct buses only.` |
| No direct bus and no one-change route (F6) | Title `No bus route found`; text `No single bus, and no two buses changing at the same stop, connect stops within 800 m of both ends. See the MRT option below.` |

- **Total.** The total is the walks plus each ride rounded up as E2 rounds, then rounded up to a multiple of 5 (E2's
  rule). It is shown only when both rides have an estimate. When a ride's estimate is omitted, that ride shows its
  stops only and no total is shown. Nothing is invented.
- **Unchanged:** loading (`Finding a direct bus…`), the bus data error and its Retry, the walk-only and no-stop texts,
  and the notes `estimateNote` and `tripEstimateNote` (the latter already says "They exclude waiting").

### 4.7 Map (F8)

- **`MapScene`:**
  - keeps `ride` (bus 1, or a direct ride) and adds `secondRide` (bus 2), both `MapRide`s built by the existing
    `_rideOf` logic per leg;
  - adds a marker kind `transfer` at the change stop, labelled `Change at <name> (<code>)`;
  - keeps the markers in journey order: origin, boarding, transfer, alighting, destination, then MRT;
  - keeps the walk connectors origin → boarding and alighting → destination (no transfer walk, since the change is at
    the same stop);
  - includes both rides' stops in the camera bounds.
- **Lines.** Each ride is matched on its own with the existing all-or-nothing `matchRide`. A ride that does not match
  shows its stops and the note `The bus route line for Bus <n> isn't available. Its stops are shown.`; the other ride
  is still drawn. Bus 2 is drawn in `colorScheme.tertiary`, and the legend lists `Bus 88` then `Bus 851e` in ride order.
  The transfer marker and the order in the legend tell the rides apart without relying on colour.
- **Loading.** `routes.min.json` is still loaded once, only by an open map, now for a direct or a transfer journey.
  `MapExpanded.show` retries a held failure for either. A direct-bus scene is unchanged: `secondRide` is null and no
  transfer marker exists.

### 4.8 Accessibility and UI requirements (F8)

- **Semantics.** Each step is one semantics node in travel order. The change step reads as its full text. The trip
  line uses the semantics text of §4.6. The map's transfer marker has its label.
- **Focus (E7/E8).**
  - "Select" and "Show steps" hand focus on exactly as they do for direct options.
  - No new control removes itself without a landing.
  - Keyboard traversal follows the visual order.
  - Every new control shows the focus ring in traditional highlight mode.
- **Layout.** No overflow at 360 px wide with 2× text. All five palettes in light and dark (ten themes) render with
  colours only from `colorScheme`, and no `Colors.*` is used.
- **Touch.** Targets of at least 48 dp, as the existing option controls.

### 4.9 Failure handling (F6)

| Case | What the user sees |
|---|---|
| Bus data fails to load | Today's error and "Retry finding a bus" (unchanged) |
| No direct bus and no one-change route | The `No bus route found` text of §4.6, then the MRT section |
| An end has no stop within 800 m | Today's `No bus stop within 800 m of your …` (no search) |
| A ride's estimate is omitted | That ride shows stops only; no total |
| A ride's line cannot be matched | That ride's stops and its note; the other line drawn |
| Route geometry fails | Today's map note and no lines; held, retried by the next "Show map" |

## 5. Files (implementation PR only; none change in this plan PR)

| File | Change |
|---|---|
| `lib/features/journey/domain/journey_leg.dart` | New: §4.1 |
| `lib/features/journey/domain/transfer_planner.dart` | New: §4.2 |
| `lib/features/journey/domain/direct_bus_planner.dart` | Add the `OneTransferOptions` variant only |
| `lib/features/journey/domain/option_selection.dart`, `journey_providers.dart` | §4.4 |
| `lib/features/journey/domain/journey_estimate.dart` | A transfer-journey estimate from the two legs (E2's functions reused) |
| `lib/features/journey/presentation/journey_card.dart` (+ a `transfer_option.dart` if it keeps the card readable) | §4.6 |
| `lib/features/map/domain/map_scene.dart`, `map_providers.dart`, `presentation/journey_map.dart` | §4.7 |
| `lib/core/config/app_config.dart` | `TransferConfig` |
| `integration_test/fakes/` | A fake network with a no-direct pair that has a one-change journey |
| `test/…` | §6 |
| `tool/e5_transfer_bench/` | Point it at `planOneTransfer`; re-record |
| `.github/workflows/flutter-test.yml` | Add the pure-Dart planner test to the Chrome step |
| `docs/assumptions.md`, `docs/architecture.md` (ADR E5-1), `docs/testing.md`, `CLAUDE.md`, `README.md` | Records |

Not touched: `bus_arrival/`, `web/index.html` (no CSP change), `pubspec.*`, the origin, destination, environment
and appearance features.

## 6. Test-first sequence (each RED commit pushed alone and seen failing in CI, as in E2, E7 and E8)

**T1. Legs** (`test/features/journey/journey_leg_test.dart`):
- T1.1 the legs are in walk, bus, bus, walk order;
- T1.2 the same service on both rides is rejected;
- T1.3 a transfer-stop mismatch is rejected;
- T1.4 a ride of 0 stops is rejected;
- T1.5 walks attached to the wrong stop are rejected.

**T2. Planner**: synthetic networks (`transfer_planner_test.dart`, pure Dart, also run on Chrome in CI), plus the
snapshot (`transfer_planner_snapshot_test.dart`, VM only):
- T2.1 a same-stop transfer is found, with its legs, score and detour;
- T2.2 forward only: bus 2 passes the change stop after the destination stop → none;
- T2.3 only the direction that serves the order is used;
- T2.4 the same service number in the other direction → rejected;
- T2.5 loop rule: bus 2 returns to a stop of bus 1 → rejected; a valid journey through the same stops in order is kept;
- T2.6 detour: 2.49 and 2.5 kept, 2.51 rejected;
- T2.7 duplicates: two change stops for the same (service 1, service 2) → one journey, the better one;
- T2.8 tie-breaks in the §4.2 order, each one decisive in its own fixture;
- T2.9 400 m, then 800 m only if 400 m finds nothing;
- T2.10 repeated stops and loops follow `planDirectBus`'s first-occurrence rule;
- T2.11 at most 3 journeys;
- T2.12 no journey → `NoDirectBus(800)`;
- T2.13 deterministic: the same input twice gives equal output, and the order of the services map does not matter;
- T2.14 snapshot: the 12 named fixtures give the journeys in `expected_results.txt`; the seeded sample serves
  exactly 229 of 301;
- T2.15 snapshot: every journey obeys T1 and the F1 rules (a property check over the sample).

**T3. Providers** (`journey_providers_test.dart`):
- T3.1 a direct pair returns `planDirectBus`'s result, and the transfer index is never built (spy repository);
- T3.2 regression: 50 pinned direct pairs from the snapshot give, through the provider, plans equal to
  `planDirectBus` (options, order, scores) with no index built;
- T3.3 a no-direct pair → `OneTransferOptions`; the index is built once across two journeys;
- T3.4 neither → `NoDirectBus`;
- T3.5 walk-only still never loads bus data;
- T3.6 a bus data failure is unchanged;
- T3.7 the bus network is loaded once, and no other request is made.

**T4. Selection:**
- T4.1 a transfer selection is honoured only for the identical plan object;
- T4.2 an out-of-range index is ignored;
- T4.3 the direct selection tests are unchanged.

**T5. Card** (widget tests):
- T5.1 the steps in order, with the §4.6 texts;
- T5.2 per-leg estimates and the total; an omitted ride estimate → no total;
- T5.3 no arrival request, and the "direct buses only" line;
- T5.4 the `No bus route found` text;
- T5.5 Select and Show steps focus hand-on (E8);
- T5.6 semantics order and labels;
- T5.7 360 px at 2× text, no overflow;
- T5.8 ten themes;
- T5.9 keyboard traversal and focus ring (E7).

**T6. Map:**
- T6.1 a transfer scene: markers, both rides, bounds;
- T6.2 direct scenes equal their pre-E5 values (the existing tests, plus a whole-`MapScene` equality on a fixture);
- T6.3 one ride unmatched → its note, the other line drawn;
- T6.4 geometry loads once, only when the map is open, for a transfer journey too; the retry rule;
- T6.5 the legend and the transfer marker's semantics;
- T6.6 the palette-change invariants are extended to a transfer journey.

**T7. Integration** (Android and Web, fakes only): a no-direct journey shows the transfer card, then the map with two
rides.

**T8. Benchmark:** `tool/e5_transfer_bench` runs `planOneTransfer`. Its same-stop rows equal `expected_results.txt`
(or each difference is explained), and its timings are recorded against §2.4.

## 7. Mutation checks (each a throwaway `mut/e5-<id>` branch from a GREEN head, pushed alone, CI run recorded)

| ID | Mutation | Must fail |
|---|---|---|
| M1 | Drop the forward-order check | T2.2 |
| M2 | Allow the same service on both rides | T2.4, T1.2 |
| M3 | Drop the loop rule | T2.5 |
| M4 | `>=` for `>` in the detour check, then no check at all | T2.6 |
| M5 | Drop the per-pair dedup | T2.7 |
| M6 | Swap two tie-breaks | T2.8 |
| M7 | Search transfers even when a direct bus exists | T3.1, T3.2 |
| M8 | Show "excl. waiting" without "for both buses", or show a total with a ride omitted | T5.2 |
| M9 | Draw nothing when one ride is unmatched | T6.3 |

## 8. Verification (each result recorded in `docs/testing.md`; anything not run is logged **Not run**, with why)

1. `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test` (counts), `flutter build web`,
   `flutter build apk --debug`.
2. Integration on Android (emulator) and Web (chromedriver, profile, one file per run).
3. CI green on the PR head, with the counts and the Chrome step.
4. The benchmark, VM and Chrome, three runs each: results equal to `expected_results.txt`, timings against §2.4.
5. A Web live check of a release build with live busrouter data: one named fixture, its card and its map.
6. Not expected to run: TalkBack or a screen reader, and a physical phone. They are logged **Not run** unless they are
   actually done.
7. An independent review against this plan and pre-E5 `main`.

## 9. Commit boundaries (branch `feat/e5-one-transfer`, only after this plan is approved and merged)

1. `test(e5): leg invariants` (RED) → `feat(e5): ordered journey legs` (GREEN)
2. `test(e5): one-transfer planner rules` (RED) → `feat(e5): one-transfer planner` (GREEN)
3. `test(e5): snapshot fixtures and benchmark parity` → GREEN
4. `test(e5): transfers only without a direct bus` (RED) → `feat(e5): plan transfers when no direct bus` (GREEN)
5. `test(e5): transfer journey card` (RED) → `feat(e5): leg-list journey card` (GREEN)
6. `test(e5): two-ride map` (RED) → `feat(e5): map a transfer journey` (GREEN)
7. `test(e5): integration` → GREEN; `ci: run the transfer planner on Chrome`
8. Mutation runs (not merged), then `docs(e5): run log, assumptions, ADR, CLAUDE.md`

## 10. Rollback

E5 is merged as one merge commit. Rollback is `git revert -m 1 <merge>` through a PR. Nothing is stored on the device,
and there is no data migration, new host or new dependency, so nothing else needs undoing. The snapshot fixture and
the benchmark can stay.

## 11. Risks and stop conditions

| Risk | Tag | Mitigation or stop |
|---|---|---|
| A direct-bus result changes | C (F3 requires none) | T3.2 and T6.2. **Stop** if any direct pair differs |
| The card grows too complex at 2× text | A | T5.7. Stop and report if the leg list cannot fit without dropping information |
| Phone performance is far below the PC | A | Targets kept with an 8–9× margin in Chrome. Measure on Android if a device is available; otherwise Not run |
| Express or limited services shown when not running | C (existing limit) | Wording claims no operating time; recorded in `assumptions.md` |
| busrouter data drifts | C | A dated snapshot; the live check uses live data; the parser's validation is unchanged |
| New findings change the design | A | Stop and report (a Gate 1 report then, G0-1) |

## 12. Decisions requiring owner approval

| ID | Decision | Recommendation |
|---|---|---|
| G2-0 | Approve this plan as the Gate 3 scope | Approve |
| G2-1 | Final detour limit (F1) | **2.5** (§2.2) |
| G2-2 | Transfer walk for the first release (F2) | **Same stop only** (§2.3) |
| G2-3 | Performance targets (F5) | Keep §10.4 unchanged, plus a cold first search under 100 ms in Chrome (§2.4) |
| G2-4 | Ranking among transfer journeys | The stop-count score, as the direct planner; E2 stays display-only (§2.5) |
| G2-5 | How many transfer journeys | Up to 3, with the direct options' Select pattern and map sync |
| G2-6 | Live arrivals for a transfer journey's first boarding stop | Not in E5: no arrival request for transfer journeys; the card says so (§4.5) |
| G2-7 | Wording (F6) and the UI and accessibility requirements (F8) | Approve §4.6–§4.9 |
| G2-8 | Keep the benchmark (`tool/e5_transfer_bench/`) and the full busrouter snapshot (574 KB, data © LTA via busrouter, in this public repository) | Keep both: they make the measurements repeatable. Otherwise the snapshot is fetched per run and checked by hash, and repeatability ends when busrouter updates |
| G2-9 | This PR carries the benchmark code and snapshot besides the plan, so it is not strictly docs-only | Accept as F5's required benchmark; or split it into its own PR |

## 13. Out of scope

Everything §3 excludes, issue #82 and the repository secret, and every gate after E5 (master plan §11: rail and
multimodal feasibility each need separate approval).
