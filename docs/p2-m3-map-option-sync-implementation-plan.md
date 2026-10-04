# P2-M3 Walk Connectors, MRT Markers and Option Sync Implementation Plan

> **Status (2026-10-05):** implemented by PR #44 (merged as `2c415e5`). Kept as the historical record: its
> checkboxes are the original execution instructions, not outstanding work.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** the user can pick any displayed direct-bus option in the journey card, and the open map then shows
that option: its boarding and alighting markers, its bus line, and two straight dashed "est." walking
connectors (origin → boarding stop, alighting stop → destination). The map also marks the MRT stations the
journey card already names, nearest to the start and nearest to the destination, and a small legend explains
the two lines. The planner's answer, the journey card's content, the MRT suggestion and the live arrivals stay
exactly as they are.

**Architecture:**

- **One selection, owned by the journey feature.**
  - `optionSelectionProvider` (`lib/features/journey/journey_providers.dart`) holds
    `OptionSelection(plan, index)`.
  - It is tied to the exact `DirectBusOptions` object it was made for, by identity, as arrivals already are.
    Any other plan object falls back to index 0, the planner's suggestion.
  - The journey card writes it; `mapSceneProvider` reads it. The journey feature never imports the map
    feature.
- **Connectors are derived, not stored.** `MapScene.walks` is computed from the scene's own markers, so the
  endpoints are exactly the markers.
- **MRT markers are read, not computed.** `mapSceneProvider` reads the journey feature's existing
  `mrtSuggestionProvider` (`nearOrigin`, `nearDestination`). `buildMapScene` turns each present suggestion
  into one informational marker at the station exit the card's walk estimate uses. The map never looks up
  stations.
- **Everything else is P2-M2, unchanged:** `rideLineProvider`, the all-or-nothing matcher, the
  `line.ride == scene.ride` guard, and the lazy, session-held `routes.min.json`.

**Tech stack:**
- Flutter 3.47.2 / Dart 3.13.2, Riverpod 3, flutter_map 8.3.2.
- Dashed lines use flutter_map's built-in `StrokePattern.dashed` (verified in the 8.3.2 source:
  `lib/src/layer/shared/line_patterns/stroke_pattern.dart`).
- **No new dependencies.**

**Spec / authoritative context:**
- guide v2.1:
  - §9.5: MRT alternative, "the nearest station to the origin, plus the nearest station to the
    destination"; informational only;
  - §17: Phase 2 map, "Markers for origin, destination, recommended stop, and MRT station", "keep
    straight-line 'est.' connectors", and "the planner must not depend on map widgets";
- `docs/map-feasibility.md`:
  - §6: walking-router finding;
  - §8: architecture, `MapScene` built from the plan "(+ MrtSuggestion)";
  - §10: the P2-M3 roadmap;
  - §11 item 3;
- `docs/architecture.md` ("Phase 2 Milestone 1", "Phase 2 Milestone 2");
- `docs/assumptions.md` (the map rows, "Walking estimate", "Journey scope", "MRT stations");
- `docs/p2-m2-bus-geometry-implementation-plan.md`;
- `CLAUDE.md`;
- the code in `lib/features/journey/`, `lib/features/bus_arrival/` and `lib/features/map/`.

Baseline: `main` at `70a74cb` (the P2-M2 merge, PR #42).

**Decision numbers.** D1–D9 in this plan are P2-M3's own. They are not P2-M2's D1–D6 (which
`docs/map-feasibility.md` §10 and `docs/architecture.md` "Phase 2 Milestone 2" cite), and not P2-M0's §5 rules.
The approval of 2026-10-04 used this plan's numbers: D2 (Select / Selected), D5 (no walk-only connector), D6
(legend) and D7 (MRT markers). D7 is the one that changed: the first draft deferred MRT markers; the approved
D7 keeps them in P2-M3. Implementation also applied six review refinements (camera contract wording, a
map-side reset test, an exact F10 line assertion, shared MRT wording, the map-ready fit, this mapping); they
refine tests and wording, not D1–D9.

---

## Global Constraints

- **Front-end only:** no server-side component, no proxy, no credentials or secrets, and no new provider host.
  CSP is unchanged: P2-M3 makes **no new network request** of any kind. The MRT data is the bundled asset the
  card already loads.
- **No walking routing.**
  - Connectors are straight lines between points the app already has: no router, no fallback router, no
    walking geometry.
  - Walking times stay the planner's `WalkEstimate`, shown only in the journey card. The map never computes
    or shows a walking time.
- **MRT stays informational** (guide §9.5): no MRT routing, direction, route geometry or live arrivals, and
  no change to `nearestMrtStation`, `mrtSuggestionProvider` or the MRT asset. The map shows only what the
  card's "MRT alternative" section already shows (the station name), at the exit that suggestion was
  computed to.
- **The planner is authoritative.**
  - The map never plans and never picks an option itself.
  - Changing the selection never re-runs `planDirectBus`, never reloads the bus network, and never reorders
    or relabels the options.
  - Option 1 stays "Suggested".
- **One notion of "selected option",** owned by the journey feature. The map has no selection or MRT state of
  its own.
- **Dependency direction:** `features/map` may import `features/journey`, never the reverse.
  `flutter_map` / `latlong2` stay in `features/map/presentation/`.
- **P2-M2 rules unchanged:**
  - the bus line is all-or-nothing, with no straight stand-in;
  - `routes.min.json` is loaded only after "Show map" with a direct-bus journey, once per session after a
    success;
  - a failure is held, and only the next "Show map" retries it;
  - a geometry problem never changes the journey card.
- **Arrivals unchanged:** selecting never requests, refreshes or invalidates arrivals (D3).
- **OneMap reasonable use unchanged:**
  - the map is closed by default;
  - no tile is requested before "Show map";
  - the camera stays inside OneMap's bounds and z11–19, fitted without animation;
  - no prefetch and no automatic tile retry.
- **Tunables** go in `MapConfig` (`lib/core/config/app_config.dart`) and `docs/assumptions.md`. The only new
  one is `walkConnectorMinMeters = 1`.
- **Tests never call live APIs.** Gates and live checks are logged in `docs/testing.md`. Anything not run is
  logged as **Not run**, with the reason.
- **Out of scope:**
  - walking routing (the FOSSGIS `routed-foot` question stays with P2-M4);
  - a walk-only connector (D5);
  - MRT routing, lines, directions, codes or arrivals;
  - a legend entry for MRT;
  - choosing an option from the map;
  - transfers;
  - live vehicles;
  - re-ranking or reordering options;
  - map-based planning;
  - a general "map leg" framework;
  - the `docs/simplification-plan.md` refactor;
  - any P2-M4 work.

## Review Focus

These five inputs are the most likely to bite a real user. Each one has a test in the task that owns the code.

1. **The user selects an alternative, then changes the destination (or retries the bus search).** The new
   journey must start at its own suggested option. The map must never show the old selection's stops or
   line, and a stale index must never pick a different bus in the new plan. Covered by **Task 1** (identity
   rule) and **Task 4** (widget: VivoCity → ION Orchard → VivoCity).
2. **The destination changes while the MRT suggestion is being recomputed.**
   - Riverpod keeps the previous value while it reloads, so the map would otherwise briefly mark the old
     destination's MRT station.
   - It must show no MRT marker until the new suggestion settles, as the card shows "Finding the nearest
     MRT…".
   - **Task 5**: a held MRT repository test.
3. **The user selects another option while `routes.min.json` is still loading.** Only the newly selected
   ride's line may appear, and there must be one load. **Task 6**: a hold/release test.
4. **Two options share both stops but are different buses** (the fake F10 and F30 both run BSH1 → VIV1).
   The markers don't move, but the line must change. **Task 2** (scene inequality) and **Task 5** (the line
   passes MID1 for F10 and ION1 for F30).
5. **Large text (2×) at 360 dp.** The select control, "Show steps" and the legend wrap without overflow.
   **Task 4** and **Task 6**.

---

## Current-state findings (from the merged code at `70a74cb`)

| # | Question | Finding |
|---|---|---|
| 1 | Where is the shown option chosen? | In two places, both hard-coded to the planner's first option. `JourneyCard._Plan` renders `direct.options.first` as "Suggested" (`journey_card.dart:115`); the others are "Alternatives". `buildMapScene` picks `options.first` (`map_scene.dart:115–117`). There is no shared notion of a shown option. |
| 2 | Can the user select an alternative? | **No.** Alternatives are collapsible (`_Option.collapsible`, "Show steps") and keyed by `board.code-service`. Nothing selects them. |
| 3 | Where should selection live? | In the journey feature, beside `journeyPlanProvider` (D1). The map already imports `journey_providers.dart`; no file under `lib/features/journey` or `lib/features/bus_arrival` imports `features/map` (checked). |
| 4 | How are arrivals tied to options? | `journeyArrivalsProvider` waits for the plan and, for a `DirectBusOptions`, requests **every displayed option's boarding stop** once, through `BusArrivalCache` (15 s TTL, in-flight dedup, failures not cached). The result is `JourneyArrivals(plan, checkedAt, byStop)`. `arrivalsFor(plan)` shows it only for the identical plan. Each `OptionArrivals` reads `byStop[option.board.code]` and filters to its own service. Arrivals are already loaded and shown for every option. |
| 5 | Reuse, load or refresh arrivals on a selection change? | **Reuse; nothing is loaded or refreshed** (D3). A selection change touches neither the plan nor `journeyArrivalsProvider`. |
| 6 | Selection while the map is closed? | It is journey state, so it changes the card ("Selected" moves) and nothing else. The closed map builds nothing: no tile and no `routes.min.json` (`rideLineProvider` is watched only by the open map). "Show map" then opens on the selected option. |
| 7 | Option change while geometry loads? | `rideLineProvider` watches `mapSceneProvider.select((s) => s?.ride)`. A new selection gives a new `MapRide`, so it recomputes against the **same** kept-alive `routeGeometryProvider` load, with no second request. When the load completes, `matchRide` runs for the selected ride only. |
| 8 | Is the P2-M2 stale-ride guard reusable unchanged? | **Yes.** A `RideLineDrawn` is drawn only when `line.ride == widget.scene.ride`, and a gap note appears only for the scene's own ride. `MapRide` equality covers service, source direction, `boardIndex`, stops and `leadingStops`. The planner keeps one option per service, so two options never have equal rides. |
| 9 | Extend `MapScene`, or a separate type? | Extend `MapScene` minimally: a derived `walks` getter (a small pure-Dart `MapWalk(from, to)`), an `isAlternative` flag, and two marker kinds for MRT. No leg framework. |
| 10 | Connectors and the bounds or camera? | Connectors don't change the bounds: a straight segment lies inside the box of its endpoints, and both are markers. MRT markers are markers, so the existing "bounds hold every marker" rule includes them (D7). The camera already refits once, without animation, whenever `widget.scene` changes (`JourneyMap.didUpdateWidget`). |
| 11 | Walk-only connector? | **None (D5, frozen).** |
| 12 | Accessibility? | The map is `ExcludeSemantics` with one summary label; the journey card is the accessible answer. Connectors and MRT pins are visual. The summary names the shown option, says walks are straight-line estimates, and names the marked MRT stations with the card's own wording (D9). The select control is a real button with a spoken label and a selected state (D2). |
| 13 | What does P2-M3 supersede? | See "Documentation superseded". |
| 14 | What MRT data exists? | `mrtSuggestionProvider` (journey feature): `FutureProvider<({MrtSuggestion? nearOrigin, MrtSuggestion? nearDestination})?>`, null until both ends exist, recomputed when either end changes. `MrtSuggestion` = `station` (`MrtStation`: name, exits), `nearestExit` (`MrtExit`: code, position), `walk`. The station has **no position of its own**; the suggestion's position is `nearestExit.position`. The card shows "Nearest MRT: <name> — <walk>" and "Near your destination: <name> — <walk>", or "none within about 1.5 km". There is **no single "recommended" MRT** in the model, only the two sides. |

---

## Decisions (frozen 2026-10-04)

### D1. Selection state: journey-owned and bound to the plan object

```dart
// lib/features/journey/domain/option_selection.dart (pure Dart)
class OptionSelection {
  const OptionSelection(this.plan, this.index);
  final DirectBusOptions plan;
  final int index;
}

int selectedOptionIndex(OptionSelection? selection, DirectBusOptions plan) => ...;
```

- `selectedOptionIndex` returns `selection.index` only if `identical(selection.plan, plan)` and the index is
  in range; otherwise **0**.
- **Consequences:**
  - A new journey always starts at the planner's suggestion.
  - A stale index can never select a different bus in a new plan.
  - There is no listener and no reset side effect.
  - Re-picking the same origin or destination doesn't re-plan (`journeyPlanProvider` selects on positions),
    so the selection is kept.
- `OptionSelectionController.build()` returns `null` and **never watches** `journeyPlanProvider`, so
  selecting can never start or re-run planning. It is not auto-disposed, so the selection survives
  "Hide map" / "Show map".

### D2. Selection UI: "Select" / "Selected" in the journey card (APPROVED)

- **Only for a `DirectBusOptions` with 2 or more options:**
  - each option gets a select control under its steps, in a `Wrap` beside "Show steps" (alternatives);
  - the selected option shows a non-interactive "Selected" mark (check icon and text) instead of the button;
  - with one option, nothing is added.
- **Spoken labels:**
  - the button is "Select Bus F10" (`semanticsLabel`; as with "Show steps for Bus N", #25);
  - the mark is `Semantics(selected: true, label: 'Bus F20 selected')`.
- **Keys:** `select-option-<service>` and `selected-option-<service>`. The service is unique within a plan.
- **What does not change:**
  - "Suggested" stays on the planner's first option, and the order never changes;
  - selecting does not expand or collapse steps, **does not open the map**, and does not scroll.

### D3. Arrivals: no change

- Selecting never calls `ref.invalidate(journeyArrivalsProvider)` and never touches `BusArrivalCache`.
- Every option's ETAs are already shown under it, and the selected option's own Retry row stays as it is.
- The map shows no ETAs. "Refresh arrivals" keeps the selection, because the plan object is identical.
- Pinned by tests: `FakeBusArrivalRepository.totalCalls` is unchanged by selecting, and the
  `JourneyArrivals` object is `identical` before and after.

### D4. Walking connectors: straight, dashed, derived from the markers

- **Drawn only for the shown direct-bus option:** origin → boarding stop, and alighting stop → destination.
  None while the plan loads or has failed, and none for walk-only, no-direct-bus or no-nearby-stop answers.
- **Endpoints are the marker positions,** read from `MapScene.markers`. They are exactly the points the card's
  `WalkEstimate`s were computed between; the estimates and the planner result are untouched.
- **A connector is omitted when its endpoints are under `MapConfig.walkConnectorMinMeters` (1 m) apart.**
- **Independent of the bus line:** connectors are drawn whether the line is drawn, unmatched, loading or
  failed.
- **Style (approved):**
  - walk: `StrokePattern.dashed(segments: [10, 8])`, 3 px, in `colorScheme.tertiary` (the origin and
    destination pin colour), with a 1 px `colorScheme.surface` border;
  - bus: the existing solid 5 px `primary` line with its 2 px border;
  - pattern, width and colour all differ, so they never rely on colour alone.
- **Layer order:** tiles → connectors (key `map-walk-connectors`) → bus line → markers.
- **No text on the map** for walks.

### D5. Walk-only journeys: no connector (APPROVED)

The map keeps marking the two ends (and the MRT markers, D7) for a walk-only journey; no line joins them.

### D6. Legend (APPROVED)

- Below the map, above the notes, key `map-legend`, in a `Wrap` so it reflows at large text.
- Exactly two possible entries:
  - "Bus <service> route" with a solid swatch, only while the line is drawn;
  - "Walk (straight-line estimate)" with a dashed swatch, only while there are connectors.
- No legend when neither applies. Plain text, readable by screen readers.
- **No MRT entry:** the approved legend lists exactly these two. The MRT pin carries a train icon and a
  tooltip, and the summary names it (D9).

### D7. MRT markers: in P2-M3 (CHANGED from the first draft; approved)

**Which markers:**
- **Both sides, each only when present:** `nearOrigin` → kind `mrtNearOrigin`; `nearDestination` → kind
  `mrtNearDestination`.
- This follows the spec exactly: `map-feasibility.md` §10 ("MRT suggestion markers from the existing
  `mrtSuggestionProvider`"), guide §9.5 ("the nearest station to the origin, plus the nearest station to the
  destination"), and the card, which shows both lines.
- The domain model has no single "recommended" MRT, so none is invented.

**Position:**
- `MrtSuggestion.nearestExit.position`, the point the card's estimate was computed to.
- A station has no position of its own in the model, and no centroid or other exit is used.

**Label (tooltip and summary):**
- The card's own wording, without the walk time: `Nearest MRT: <station name>` and
  `Near your destination: <station name>`.
- No exit code, line, code or direction, since the card shows none.

**Source:**
- `mapSceneProvider` reads `mrtSuggestionProvider` with the same settled rule as the plan: while it is
  loading or has failed, **no MRT marker** (never the previous journey's).
- The card's MRT section stays the place for the error and its Retry. The map shows no MRT note.
- The provider and the asset load are the card's; the map adds no load, because both watch the same provider.

**Independent of the plan:** MRT markers appear for every answer (direct bus, walk-only, no direct bus, no
nearby stop) and while the plan is still loading, exactly as the card's MRT section does.

**Bounds and camera:**
- MRT markers are markers, so `MapScene.bounds` includes them, keeping the P2-M1 rule "bounds hold every
  marker" and its camera test ("every marker is in view").
- The added extent is at most `JourneyConfig.mrtMaxDistanceMeters` (1.5 km) from an end.
- When the MRT suggestion settles after the plan, the scene changes, so the camera refits once without
  animation (the existing `didUpdateWidget` rule).

**Layering:**
- In the `MarkerLayer`: MRT pins first (bottom), then the ends (40 px), then the stops (30 px, top).
- A journey pin is never hidden under an MRT pin; for example, when the destination is the station itself,
  its exit is metres away.

**Pin:** 30 px, the `_MarkerPin` style (surface fill, coloured border), `Icons.train` in
`colorScheme.secondary`, distinct from the bus stops (`Icons.directions_bus` / `Icons.logout` in `primary`).

**Same station on both sides** (a short trip): two markers, one per suggestion, possibly at the same exit.
They are drawn as given and not merged; merging would need new wording the card doesn't have.

**Not added:** MRT routing, direction, route geometry, lines or codes, live arrivals, and any change to the
MRT recommendation logic.

### D8. Camera

- No new rule: `JourneyMap.didUpdateWidget` already refits once, without animation, when the scene changes.
- Scene changes now include a selection change and the MRT suggestion settling.
- The fitted box includes the selected ride's stops (P2-M2 D5) and the MRT markers (D7).
- The camera is still not refitted when the bus line arrives, because the scene doesn't change then.

### D9. Map summary (screen readers)

One summary, built in this order:
1. `Map of the suggested journey: from …` (option 1, or no bus) or `Map of an alternative journey: from …`,
   followed by `, bus N from <boarding> to <alighting>` when there is a bus, then `, to <destination>.`
2. When there are connectors: ` Walks are drawn as straight lines, estimates only.`
3. For each present MRT marker: ` Nearest MRT: <name>.` / ` Near your destination: <name>.`
4. ` The journey details are listed above.`

---

## Data flow

```text
originController ─┐
destinationCtrl ──┼─▶ journeyPlanProvider (planDirectBus) ──▶ JourneyCard: options + "Select"
busNetworkProvider┘          │                                  └─▶ optionSelectionProvider.select(plan, i)
                             ├─▶ journeyArrivalsProvider (all boarding stops; unchanged; not watched by selection)
                             │
mrtRepository ─▶ mrtSuggestionProvider (unchanged) ─▶ JourneyCard: "MRT alternative"
                             │                │
                             ▼                ▼
                     mapSceneProvider (settled plan, settled MRT, selectedOptionIndex(selection, plan))
                       buildMapScene → markers (ends, selected stops, MRT), ride, walks (derived), isAlternative
                             │
                             ├─▶ rideLineProvider (autoDispose; open map only) ─▶ routeGeometryProvider (session)
                             ▼
                     JourneyMap: connectors → ride line (if line.ride == scene.ride) → markers (MRT, ends, stops);
                     legend; refit on scene change
```

The journey card never reads anything from the map. The map reads the plan, the selection and the MRT
suggestion, and writes none of them.

## Failure and degraded-state behaviour

| Situation | Card | Map |
|---|---|---|
| Direct bus, line drawn | Options; the selected one marked | Markers, the selected line, both connectors, MRT markers, legend (bus + walk) |
| Direct bus, line unmatched, malformed or missing | Unchanged | Markers and connectors; the P2-M2 note; legend (walk only) |
| Direct bus, `routes.min.json` failed | Unchanged | Markers and connectors; the P2-M2 note; the next "Show map" retries |
| Selection changed while the load is pending | "Selected" moves at once | Markers, connectors and camera follow at once; the line for the selected ride only; 1 load |
| One option only | No select control | P2-M2, plus connectors and MRT |
| Walk-only | Unchanged | Two ends and MRT markers; no connector (D5); no legend |
| No direct bus / no nearby stop | Unchanged | Two ends and MRT markers; no connectors; no legend |
| Plan loading or failed | Busy / error with Retry | Two ends, plus MRT markers if MRT has settled; no connectors |
| MRT loading or failed | "Finding the nearest MRT…" / error with Retry | No MRT markers, no note; everything else as above |
| No MRT station within 1.5 km of a side | "none within about 1.5 km" | No marker for that side |
| Endpoint less than 1 m from its stop | Unchanged | That connector omitted; the other drawn |
| Tiles failed | Unchanged | P2-M1 tiles note; markers, connectors and line still drawn |
| New journey after selecting an alternative | Starts at "Suggested" | The new plan's option 1, and the new MRT once settled |
| Arrivals refresh, failure or retry | Unchanged; selection kept | Unaffected |

---

## File-by-file change list

| File | Change |
|---|---|
| `lib/features/journey/domain/option_selection.dart` | **New.** `OptionSelection`, `selectedOptionIndex`. Pure Dart. |
| `lib/features/journey/journey_providers.dart` | `optionSelectionProvider` and `OptionSelectionController.select(plan, index)`. |
| `lib/features/journey/presentation/journey_card.dart` | `JourneyCard` watches the selection. `_Plan` and `_Option` gain `selected` / `onSelect`. New `_SelectControl`. |
| `lib/features/map/domain/map_scene.dart` | `MapMarkerKind.mrtNearOrigin` / `mrtNearDestination`; `MapWalk`; `MapScene.walks` (getter) and `isAlternative`; `buildMapScene(selectedIndex:, mrt:)`; the summary (D9); "suggested" → "shown" in docs and names. |
| `lib/features/map/map_providers.dart` | `mapSceneProvider` watches `optionSelectionProvider` and `mrtSuggestionProvider` (both settled), and passes them on. Doc comment updated. |
| `lib/features/map/presentation/journey_map.dart` | Dashed connector `PolylineLayer`; MRT pins (icon, colour, layer order); legend; legend text constants. |
| `lib/core/config/app_config.dart` | `MapConfig.walkConnectorMinMeters = 1`. |
| `test/features/journey/option_selection_test.dart` | **New.** D1 tests, pure and container. |
| `test/features/journey/journey_widget_test.dart` | Select control, arrival invariance, reset, refresh, semantics, 2× text. |
| `test/features/map/map_scene_test.dart` | Selected option, walks, MRT markers, summary, bounds; the two existing summary strings updated. |
| `test/features/map/journey_map_card_test.dart` | Option sync, connectors, legend, MRT pins (layering, held MRT, failure), hold/release, closed map; the summary regex and the layer-order test made key-based. |
| `integration_test/happy_path_test.dart` | Connectors and MRT pins; select F10 → boarding moves; one geometry load; no extra arrival calls. |
| `integration_test/fallback_path_test.dart` | On the no-direct-bus journey: open the map → ends and both MRT pins, no stops, connectors, legend or line, no geometry load → hide the map. |
| `docs/…`, `CLAUDE.md` | See "Documentation updates". |

No changes to:
- the planner, `mrt.dart`, `mrt_asset_repository.dart`, `mrtSuggestionProvider` or the `bus_arrival` code;
- the parsers, `ride_geometry.dart`, `route_geometry.dart` or the shared fakes;
- `web/index.html` or the CSP test.

## Interfaces

```dart
// lib/features/journey/domain/option_selection.dart
import 'direct_bus_planner.dart';

/// The user's choice among one plan's direct-bus options (P2-M3). It belongs
/// to the exact plan object it was made for: any other plan (a new journey,
/// a retried bus search) starts again at the planner's first option.
class OptionSelection {
  const OptionSelection(this.plan, this.index);
  final DirectBusOptions plan;
  final int index;
}

/// The option to show for [plan]: [selection]'s index if it was made for this
/// exact plan and is in range, else 0 (the planner's suggestion).
int selectedOptionIndex(OptionSelection? selection, DirectBusOptions plan) =>
    selection != null &&
        identical(selection.plan, plan) &&
        selection.index >= 0 &&
        selection.index < plan.options.length
    ? selection.index
    : 0;
```

```dart
// lib/features/journey/journey_providers.dart (added)
/// Which displayed direct-bus option the user selected (P2-M3). Journey state:
/// the card writes it, the map reads it. It never watches the plan, so
/// selecting never re-plans; it is tied to the plan object instead
/// ([selectedOptionIndex]).
final optionSelectionProvider =
    NotifierProvider<OptionSelectionController, OptionSelection?>(
      OptionSelectionController.new,
    );

class OptionSelectionController extends Notifier<OptionSelection?> {
  @override
  OptionSelection? build() => null;

  void select(DirectBusOptions plan, int index) {
    if (index < 0 || index >= plan.options.length) return;
    state = OptionSelection(plan, index);
  }
}
```

```dart
// lib/features/map/domain/map_scene.dart (added / changed)
enum MapMarkerKind {
  origin, boarding, alighting, destination,
  mrtNearOrigin,       // P2-M3: the card's "Nearest MRT"
  mrtNearDestination,  // P2-M3: the card's "Near your destination"
}

/// A straight walking connector between two journey points. An estimate, not
/// a route: the map has no walking geometry (guide §17).
class MapWalk {
  const MapWalk(this.from, this.to);
  final LatLng from;
  final LatLng to;
  // == and hashCode on the two LatLngs (LatLng has value equality).
}

class MapScene {
  const MapScene(this.markers, {this.serviceNumber, this.ride, this.isAlternative = false});

  /// Journey order (origin, boarding, alighting, destination; the two stops
  /// only with a bus), then the MRT markers that are present.
  final List<MapMarker> markers;
  final bool isAlternative; // the shown option is not the planner's first

  /// origin → boarding and alighting → destination when the scene has a bus;
  /// a connector shorter than MapConfig.walkConnectorMinMeters is left out.
  List<MapWalk> get walks;
  // bounds: unchanged code (every marker, MRT included, + ride stops).
  // summary: D9. == / hashCode: add isAlternative.
}

MapScene buildMapScene({
  required LatLng origin,
  required String originLabel,
  required LatLng destination,
  required String destinationLabel,
  JourneyPlan? plan,
  int selectedIndex = 0,                                               // new; out of range → 0
  ({MrtSuggestion? nearOrigin, MrtSuggestion? nearDestination})? mrt, // new; settled value or null
  Map<String, BusStop>? stops,
});
```

```dart
// lib/core/config/app_config.dart, MapConfig (added)
/// A walking connector shorter than this is not drawn (its two ends are the
/// same place, e.g. a destination at the stop itself).
static const double walkConnectorMinMeters = 1;
```

---

## Tasks (test-first; one commit each)

### Task 1: Selection state (journey domain + provider)

**Files:**
- Create: `lib/features/journey/domain/option_selection.dart`
- Modify: `lib/features/journey/journey_providers.dart`
- Test: `test/features/journey/option_selection_test.dart`

**Interfaces:** Produces `OptionSelection`, `selectedOptionIndex`, `optionSelectionProvider` and
`OptionSelectionController.select`, exactly as in "Interfaces".

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/features/journey/domain/direct_bus_planner.dart';
import 'package:sg_smart_commute/features/journey/domain/option_selection.dart';
import 'package:sg_smart_commute/features/journey/journey_providers.dart';

import '../../../integration_test/fakes/fake_bus_network.dart';
import '../../../integration_test/fakes/fake_place_search_repository.dart';

const bishan = LatLng(1.3508, 103.8485);

DirectBusOptions vivoPlan() =>
    planDirectBus(fakeBusNetwork(), bishan, vivoCity.position) as DirectBusOptions;

void main() {
  test('no selection → the planner\'s first option', () {
    expect(selectedOptionIndex(null, vivoPlan()), 0);
  });

  test('a selection applies only to the exact plan object it was made for', () {
    final a = vivoPlan(), b = vivoPlan(); // equal content, different objects
    final s = OptionSelection(a, 2);
    expect(selectedOptionIndex(s, a), 2);
    expect(selectedOptionIndex(s, b), 0);
  });

  test('an out-of-range index → 0', () {
    final a = vivoPlan();
    expect(selectedOptionIndex(OptionSelection(a, 3), a), 0);
    expect(selectedOptionIndex(OptionSelection(a, -1), a), 0);
  });

  test('select() stores the choice; an out-of-range select is ignored', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final a = vivoPlan();
    c.read(optionSelectionProvider.notifier).select(a, 1);
    expect(selectedOptionIndex(c.read(optionSelectionProvider), a), 1);
    c.read(optionSelectionProvider.notifier).select(a, 5);
    expect(c.read(optionSelectionProvider)!.index, 1);
  });

  test('selecting never creates or reads the plan provider', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(optionSelectionProvider.notifier).select(vivoPlan(), 1);
    expect(c.exists(journeyPlanProvider), isFalse);
  });
}
```

- [ ] **Step 2: Run them and see them fail.**
  `flutter test test/features/journey/option_selection_test.dart`. They fail to compile
  (`option_selection.dart` is missing).
- [ ] **Step 3: Implement** `option_selection.dart` and the provider exactly as in "Interfaces".
- [ ] **Step 4: Run them and see them pass.**
- [ ] **Step 5: Mutation checks** (revert each one):
  - drop `identical(selection.plan, plan)`: the exact-plan test fails;
  - make `build()` read `journeyPlanProvider`: the "never creates" test fails.
- [ ] **Step 6: Commit:** `feat(journey): option selection tied to the plan object`.

### Task 2: The scene shows the selected option, with derived walking connectors (pure)

**Files:**
- Modify: `lib/features/map/domain/map_scene.dart`
- Modify: `lib/core/config/app_config.dart`
- Test: `test/features/map/map_scene_test.dart`

**Interfaces:**
- Consumes: `DirectBusOptions` and `BusOption`.
- Produces: `MapWalk`, `MapScene.walks`, `MapScene.isAlternative`, and `buildMapScene(selectedIndex:)`.

- [ ] **Step 1: Write the failing tests** (`network`, `bishan`, `sceneTo` and `kinds` exist; extend `sceneTo`
  with `int selectedIndex = 0` and pass it through):

```dart
group('the selected option (P2-M3)', () {
  final stops = network.stops;
  final plan = planDirectBus(network, bishan, vivoCity.position) as DirectBusOptions;
  // F20 BSH2→VIV1 (suggested), F10 BSH1→VIV1, F30 BSH1→VIV1.
  MapScene at(int i) => sceneTo(vivoCity.position, plan: plan, stops: stops, selectedIndex: i);
  LatLng pos(MapScene s, MapMarkerKind k) => s.markers.firstWhere((m) => m.kind == k).position;

  test('index 0 is the suggestion; index 1 shows F10 everywhere', () {
    expect(at(0).serviceNumber, 'F20');
    expect(at(0).isAlternative, isFalse);
    final s1 = at(1);
    expect(s1.serviceNumber, 'F10');
    expect(s1.isAlternative, isTrue);
    expect(pos(s1, MapMarkerKind.boarding), stops['BSH1']!.position);
    expect(pos(s1, MapMarkerKind.alighting), stops['VIV1']!.position);
    expect(s1.ride!.service, 'F10');
    expect(s1.ride!.boardIndex, plan.options[1].boardIndex);
  });

  test('two options with the same stops are different scenes (F10 vs F30)', () {
    expect(pos(at(1), MapMarkerKind.boarding), pos(at(2), MapMarkerKind.boarding));
    expect(pos(at(1), MapMarkerKind.alighting), pos(at(2), MapMarkerKind.alighting));
    expect(at(1).ride, isNot(at(2).ride));
    expect(at(1), isNot(at(2)));
  });

  test('an out-of-range index shows the suggestion', () {
    expect(at(9).serviceNumber, 'F20');
    expect(at(9).isAlternative, isFalse);
  });

  test('walks: origin → boarding and alighting → destination, exactly the markers', () {
    expect(at(1).walks, [
      MapWalk(bishan, stops['BSH1']!.position),
      MapWalk(stops['VIV1']!.position, vivoCity.position),
    ]);
  });

  test('no walks without a bus: loading, walk-only, no direct bus, no stops', () {
    for (final p in <JourneyPlan?>[
      null,
      WalkOnly(WalkEstimate.between(bishan, bishan)),
      const NoDirectBus(radiusMeters: 800),
      const NoNearbyStops(JourneyEnd.origin, radiusMeters: 800),
    ]) {
      expect(sceneTo(vivoCity.position, plan: p, stops: stops).walks, isEmpty, reason: '$p');
    }
  });

  test('a connector under walkConnectorMinMeters is left out, the other kept', () {
    final o = plan.options.first;
    final atStop = buildMapScene(
      origin: o.board.position, // the origin is the boarding stop itself
      originLabel: 'Here',
      destination: vivoCity.position,
      destinationLabel: 'Destination',
      plan: plan,
      stops: stops,
    );
    expect(atStop.walks, [MapWalk(o.alight.position, vivoCity.position)]);
  });

  test('summary: an alternative says so, and walks are called estimates', () {
    expect(
      at(1).summary,
      'Map of an alternative journey: from Current location, bus F10 from '
      'Bishan Int (fake) (BSH1) to VivoCity (fake) (VIV1), to Destination. '
      'Walks are drawn as straight lines, estimates only. '
      'The journey details are listed above.',
    );
  });
});
```

  Update the existing summary expectation with a bus (it gains the walking clause); the one without a bus is
  unchanged.
- [ ] **Step 2: Run the tests and see them fail.** `flutter test test/features/map/map_scene_test.dart`
- [ ] **Step 3: Implement**
  - `selectedIndex` in `buildMapScene`: the shown option is
    `options[selectedIndex >= 0 && selectedIndex < options.length ? selectedIndex : 0]`, and `isAlternative`
    is `shown != null && !identical(shown, options.first)`.
  - `MapWalk` with value equality.
  - The `walks` getter: find the markers by kind. With no boarding marker, return `[]`. Otherwise return
    the two pairs filtered by `haversineMeters(from, to) >= MapConfig.walkConnectorMinMeters`.
  - `MapConfig.walkConnectorMinMeters`, the summary per D9 (steps 1, 2 and 4), and `isAlternative` in
    `==` and `hashCode`.
  - Rename local `suggested` to `shown`, and update the doc comments.
- [ ] **Step 4: Run the tests and see them pass.**
- [ ] **Step 5: Mutation checks:**
  - always `first`: the F10 tests fail;
  - boarding → origin: the exact-endpoint test fails;
  - no minimum-length filter: the "left out" test fails.
- [ ] **Step 6: Commit:** `feat(map): the scene shows the selected option, with straight walk connectors`.

### Task 3: MRT markers in the scene (pure)

**Files:**
- Modify: `lib/features/map/domain/map_scene.dart`
- Test: `test/features/map/map_scene_test.dart`

**Interfaces:**
- Consumes: `MrtSuggestion` and `nearestMrtStation` (`features/journey/domain/mrt.dart`, unchanged), and
  `fakeMrtStations` (`integration_test/fakes/fake_bus_network.dart`).
- Produces: `MapMarkerKind.mrtNearOrigin` / `mrtNearDestination` and `buildMapScene(mrt:)`.

- [ ] **Step 1: Write the failing tests** (extend `sceneTo` with an optional `mrt` and pass it through):

```dart
group('MRT markers (P2-M3)', () {
  // The card's own suggestions, from the unchanged journey function.
  final nearO = nearestMrtStation(fakeMrtStations, bishan)!;            // BISHAN MRT STATION
  final nearD = nearestMrtStation(fakeMrtStations, vivoCity.position)!; // HARBOURFRONT MRT STATION
  final both = (nearOrigin: nearO, nearDestination: nearD);
  MapMarker? mrt(MapScene s, MapMarkerKind k) =>
      s.markers.where((m) => m.kind == k).firstOrNull;

  test('one marker per present suggestion, at its nearest exit, with the card\'s wording', () {
    final s = sceneTo(vivoCity.position, mrt: both);
    expect(mrt(s, MapMarkerKind.mrtNearOrigin)!.position, nearO.nearestExit.position);
    expect(mrt(s, MapMarkerKind.mrtNearOrigin)!.label, 'Nearest MRT: BISHAN MRT STATION');
    expect(mrt(s, MapMarkerKind.mrtNearDestination)!.position, nearD.nearestExit.position);
    expect(mrt(s, MapMarkerKind.mrtNearDestination)!.label,
        'Near your destination: HARBOURFRONT MRT STATION');
  });

  test('a side with no station within the limit has no marker', () {
    final s = sceneTo(vivoCity.position, mrt: (nearOrigin: nearO, nearDestination: null));
    expect(mrt(s, MapMarkerKind.mrtNearOrigin), isNotNull);
    expect(mrt(s, MapMarkerKind.mrtNearDestination), isNull);
    expect(sceneTo(vivoCity.position).markers.where((m) =>
        m.kind == MapMarkerKind.mrtNearOrigin || m.kind == MapMarkerKind.mrtNearDestination), isEmpty);
  });

  test('MRT markers come after the journey markers and never change them', () {
    final plan = planDirectBus(network, bishan, vivoCity.position);
    final withMrt = sceneTo(vivoCity.position, plan: plan, stops: network.stops, mrt: both);
    final without = sceneTo(vivoCity.position, plan: plan, stops: network.stops);
    expect(kinds(withMrt), [...kinds(without), MapMarkerKind.mrtNearOrigin, MapMarkerKind.mrtNearDestination]);
    expect(withMrt.ride, without.ride);
    expect(withMrt.walks, without.walks); // connectors never go to an MRT
  });

  test('present for every answer, independent of the plan', () {
    for (final p in <JourneyPlan?>[null, const NoDirectBus(radiusMeters: 800),
        WalkOnly(WalkEstimate.between(bishan, bishan))]) {
      expect(mrt(sceneTo(vivoCity.position, plan: p, mrt: both), MapMarkerKind.mrtNearOrigin),
          isNotNull, reason: '$p');
    }
  });

  test('bounds hold the MRT markers', () {
    final b = sceneTo(vivoCity.position, mrt: both).bounds;
    for (final p in [nearO.nearestExit.position, nearD.nearestExit.position]) {
      expect(p.latitude, inInclusiveRange(b.southWest.latitude, b.northEast.latitude));
      expect(p.longitude, inInclusiveRange(b.southWest.longitude, b.northEast.longitude));
    }
  });

  test('summary names the marked stations with the card\'s wording', () {
    expect(sceneTo(vivoCity.position, mrt: both).summary,
        'Map of the suggested journey: from Current location, to Destination. '
        'Nearest MRT: BISHAN MRT STATION. '
        'Near your destination: HARBOURFRONT MRT STATION. '
        'The journey details are listed above.');
  });

  test('scenes that differ only in MRT are not equal', () {
    expect(sceneTo(vivoCity.position, mrt: both), isNot(sceneTo(vivoCity.position)));
  });
});
```

- [ ] **Step 2: Run the tests and see them fail.**
- [ ] **Step 3: Implement**
  - Add the two kinds.
  - In `buildMapScene`, after the destination marker:
    `if (mrt?.nearOrigin case final s?) MapMarker(MapMarkerKind.mrtNearOrigin, s.nearestExit.position, 'Nearest MRT: ${s.station.name}')`,
    and the same for `nearDestination` with `'Near your destination: …'`.
  - The summary's MRT clause (D9 step 3), read from those markers' labels.
  - `bounds` and `==` need no code change (markers already cover both).
  - Fix any `switch` over `MapMarkerKind` that is now non-exhaustive. `_MarkerPin` (Task 6) is one; for this
    commit give it a temporary `Icons.train` arm, so the build stays green.
- [ ] **Step 4: Run the tests and see them pass,** then the whole `map_scene_test.dart`.
- [ ] **Step 5: Mutation checks:**
  - position from `station.exits.first` instead of `nearestExit`: the position test fails. In the fake,
    each station has one exit, so the test uses a fake station with two exits:
    `MrtStation(name: 'TWO EXIT MRT STATION', exits: [far, near])`;
  - MRT markers inserted before the destination: the order test fails.
- [ ] **Step 6: Commit:** `feat(map): MRT suggestion markers in the scene`.

### Task 4: Select an option in the journey card

**Files:**
- Modify: `lib/features/journey/presentation/journey_card.dart`
- Test: `test/features/journey/journey_widget_test.dart`

**Interfaces:**
- Consumes: `optionSelectionProvider`, `selectedOptionIndex`.
- Produces: the keys `select-option-<service>` and `selected-option-<service>`.

- [ ] **Step 1: Write the failing tests** (`pumpApp`, `searchAndPick`, `inKey`, `destinationField`,
  `arrivals` and `bus` exist; add `select(tester, service)`, which scrolls to and taps `select-option-$service`
  and pumps twice):

```dart
group('selecting an option (P2-M3)', () {
  testWidgets('the suggestion is selected first; one control per other option', (tester) async {
    await pumpApp(tester, app());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    expect(find.byKey(const Key('selected-option-F20')), findsOneWidget);
    expect(find.byKey(const Key('select-option-F10')), findsOneWidget);
    expect(find.byKey(const Key('select-option-F30')), findsOneWidget);
    expect(find.byKey(const Key('select-option-F20')), findsNothing);
  });

  testWidgets('select F10, then back to F20; "Suggested" and order never change', (tester) async {
    await pumpApp(tester, app());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await select(tester, 'F10');
    expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
    expect(find.byKey(const Key('select-option-F20')), findsOneWidget);
    expect(inKey('journey-suggested', 'Take Bus F20 toward VivoCity (fake)'), findsOneWidget);
    expect(inKey('journey-alternative-1', 'Take Bus F10 toward VivoCity (fake)'), findsOneWidget);
    await select(tester, 'F20');
    expect(find.byKey(const Key('selected-option-F20')), findsOneWidget);
  });

  testWidgets('selecting never re-plans, reloads buses or touches arrivals', (tester) async {
    await pumpApp(tester, app());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await tester.pump();
    final c = ProviderScope.containerOf(tester.element(find.byKey(const Key('journey-card'))));
    final plan = c.read(journeyPlanProvider).value;
    final journeyArrivals = c.read(journeyArrivalsProvider).value;
    final calls = arrivals.totalCalls;
    await select(tester, 'F10');
    await select(tester, 'F30');
    expect(identical(c.read(journeyPlanProvider).value, plan), isTrue);
    expect(identical(c.read(journeyArrivalsProvider).value, journeyArrivals), isTrue);
    expect(arrivals.totalCalls, calls);
    expect(bus.loads, 1);
  });

  testWidgets('a new journey starts at its suggestion (no stale index)', (tester) async {
    await pumpApp(tester, app());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await select(tester, 'F10');
    await tester.tap(find.byKey(const Key('change-destination')));
    await tester.pump();
    await searchAndPick(tester, destinationField, 'ION Orchard', 'ION ORCHARD'); // one option
    expect(find.byKey(const Key('select-option-F30')), findsNothing);
    expect(find.byKey(const Key('selected-option-F30')), findsNothing);
    await tester.tap(find.byKey(const Key('change-destination')));
    await tester.pump();
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY'); // a new plan object
    expect(find.byKey(const Key('selected-option-F20')), findsOneWidget);
  });

  testWidgets('"Refresh arrivals" keeps the selection', (tester) async {
    await pumpApp(tester, app());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await select(tester, 'F10');
    await tester.tap(find.byKey(const Key('arrivals-refresh')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
  });

  testWidgets('spoken labels name the bus; the mark is selected', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, app());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    expect(find.bySemanticsLabel('Select Bus F10'), findsOneWidget);
    expect(tester.getSemantics(find.byKey(const Key('selected-option-F20'))),
        matchesSemantics(label: 'Bus F20 selected', isSelected: true));
    handle.dispose();
  });

  testWidgets('2× text at 360 dp: no overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, app());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    expect(tester.takeException(), isNull);
  });
});
```

  (`matchesSemantics` may need the exact flags the implementation produces; the requirement is "names the
  bus" and "is selected".)
- [ ] **Step 2: Run the tests and see them fail.**
- [ ] **Step 3: Implement**
  - `JourneyCard.build`: `final selection = ref.watch(optionSelectionProvider);`, then pass `selection` and
    `onSelect: (plan, i) => ref.read(optionSelectionProvider.notifier).select(plan, i)` to `_Plan`.
  - `_Plan` (`DirectBusOptions` branch): `final shown = selectedOptionIndex(selection, direct);`. Each
    `_Option` gets `selected: i == shown` and, only when `direct.options.length > 1`,
    `onSelect: () => onSelect(direct, i)`.
  - `_Option`: a bottom `Wrap(spacing: 8, children: [if (onSelect != null) _SelectControl(...), if (collapsible) <the existing Show steps button>])`.
  - `_SelectControl`:
    - not selected: `OutlinedButton(key: Key('select-option-$n'), onPressed: onSelect, child: Text('Select', semanticsLabel: 'Select Bus $n'))`;
    - selected: `Semantics(key: Key('selected-option-$n'), selected: true, label: 'Bus $n selected', excludeSemantics: true, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle, size: 18), SizedBox(width: 4), Text('Selected')]))`.
  - `JourneyCard` doc comment: the selected option is the one the map shows.
- [ ] **Step 4: Run** these tests, the whole `journey_widget_test.dart` and `arrivals_widget_test.dart`.
- [ ] **Step 5: Mutation checks:**
  - `onSelect` also invalidates `journeyArrivalsProvider`: the "never touches arrivals" test fails;
  - `shown = selection?.index ?? 0` (no identity): the "new journey" test fails.
- [ ] **Step 6: Commit:** `feat(journey): select a direct-bus option in the journey card`.

### Task 5: The map follows the selection and the MRT suggestion (providers)

**Files:**
- Modify: `lib/features/map/map_providers.dart`
- Test: `test/features/map/journey_map_card_test.dart`

**Interfaces:**
- Consumes: `optionSelectionProvider`, `selectedOptionIndex`, `mrtSuggestionProvider`, and
  `buildMapScene(selectedIndex:, mrt:)`.

- [ ] **Step 1: Write the failing tests** (`group('option sync and MRT (P2-M3)')`; helpers:
  - `pointOf(tester, kind)` reads the keyed marker's point from the `MarkerLayer` as a `LatLng`;
  - `ridePoints(tester)` reads the `map-ride-line` points;
  - `selectOption(tester, s)` scrolls to and taps `select-option-$s`, then pumps twice):

```dart
LatLng pointOf(WidgetTester t, String kind) {
  final m = t.widget<MarkerLayer>(find.byType(MarkerLayer)).markers
      .firstWhere((m) => m.key == Key('map-marker-$kind'));
  return LatLng(m.point.latitude, m.point.longitude);
}

List<LatLng> ridePoints(WidgetTester t) => [
  for (final p in t.widget<PolylineLayer>(find.byKey(const Key('map-ride-line'))).polylines.single.points)
    LatLng(p.latitude, p.longitude),
];

bool near(LatLng a, LatLng b) =>
    (a.latitude - b.latitude).abs() < 1e-4 && (a.longitude - b.longitude).abs() < 1e-4;

Future<void> selectOption(WidgetTester t, String service) async {
  // Not scrollToAndTap: widget tests import only the fakes from integration_test/.
  final button = find.byKey(Key('select-option-$service'));
  await t.ensureVisible(button);
  await t.pump();
  await t.tap(button);
  await t.pump();
  await t.pump();
}

testWidgets('selecting F10 moves the boarding marker and redraws the line; one load', (tester) async {
  await pumpApp(tester, app());
  await pickDestination(tester, 'VivoCity', 'VIVOCITY');
  await openMap(tester);
  await tester.pump();
  final s = fakeBusNetwork().stops;
  expect(pointOf(tester, 'boarding'), s['BSH2']!.position);
  await selectOption(tester, 'F10');
  expect(pointOf(tester, 'boarding'), s['BSH1']!.position);
  expect(ridePoints(tester).any((p) => near(p, s['MID1']!.position)), isTrue); // F10 via MID1
  expect(geometry.loads, 1);
});

testWidgets('F10 → F30: same stops, different line (via ION1)', (tester) async {
  // select F10, then F30: the boarding point is unchanged; the line passes ION1, not MID1; loads == 1
});

testWidgets('select while the map is closed: no tile, no geometry; opening shows the selection', (tester) async {
  await pumpApp(tester, app());
  await pickDestination(tester, 'VivoCity', 'VIVOCITY');
  await selectOption(tester, 'F10');
  expect(geometry.loads, 0);
  expect(tiles.requested, isEmpty);
  await openMap(tester);
  await tester.pump();
  expect(pointOf(tester, 'boarding'), fakeBusNetwork().stops['BSH1']!.position);
  expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
  expect(geometry.loads, 1);
});

testWidgets('the selection survives Hide map / Show map; no second load', (tester) async {
  // select F10, open, hide, open: boarding is BSH1; geometry.loads == 1
});

testWidgets('the camera fits the selected option and the MRT markers', (tester) async {
  // open, select F10; every MarkerLayer marker (MRT included) and every scene ride stop is inside
  // MapCamera.of(...).visibleBounds (the existing camera test's pattern)
});

testWidgets('both MRT markers, with the card\'s wording as tooltips', (tester) async {
  await pumpApp(tester, app());
  await pickDestination(tester, 'VivoCity', 'VIVOCITY');
  await openMap(tester);
  expect(marker('mrtNearOrigin'), findsOneWidget);
  expect(marker('mrtNearDestination'), findsOneWidget);
  expect(find.byTooltip('Nearest MRT: BISHAN MRT STATION'), findsOneWidget);
  expect(find.byTooltip('Near your destination: HARBOURFRONT MRT STATION'), findsOneWidget);
});

testWidgets('while the MRT suggestion reloads for a new journey, no MRT marker (never the old one)', (tester) async {
  final mrt = HeldMrtRepository(); // test-local, below
  await pumpApp(tester, app(mrt: mrt));
  await pickDestination(tester, 'VivoCity', 'VIVOCITY');
  await openMap(tester);
  expect(marker('mrtNearOrigin'), findsNothing); // loading
  mrt.gates.last.complete(fakeMrtStations);
  await tester.pump();
  await tester.pump();
  expect(find.byTooltip('Near your destination: HARBOURFRONT MRT STATION'), findsOneWidget);

  await tester.tap(find.byKey(const Key('change-destination')));
  await tester.pump();
  await pickDestination(tester, 'ION Orchard', 'ION ORCHARD'); // re-runs the MRT suggestion
  expect(find.byTooltip('Near your destination: HARBOURFRONT MRT STATION'), findsNothing);
  expect(marker('mrtNearOrigin'), findsNothing); // the settled rule: nothing while loading
  mrt.gates.last.complete(fakeMrtStations);
  await tester.pump();
  await tester.pump();
  expect(find.byTooltip('Near your destination: ORCHARD MRT STATION'), findsOneWidget);
});

testWidgets('MRT failure: no MRT marker and no map note; the rest is unaffected', (tester) async {
  await pumpApp(tester, app(mrt: fakeMrtRepository(fail: true)));
  await pickDestination(tester, 'VivoCity', 'VIVOCITY');
  await openMap(tester);
  expect(marker('mrtNearOrigin'), findsNothing);
  expect(marker('boarding'), findsOneWidget);
  expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
});
```

```dart
/// Each stations() call waits on its own gate (the real repository caches a
/// success, which would make the reload instant and hide a stale frame).
class HeldMrtRepository extends MrtAssetRepository {
  HeldMrtRepository() : super(load: () async => '');
  final gates = <Completer<List<MrtStation>>>[];
  @override
  Future<List<MrtStation>> stations() {
    final gate = Completer<List<MrtStation>>();
    gates.add(gate);
    return gate.future;
  }
}
```

  (Give `app()` in this test file an optional `MrtAssetRepository? mrt` parameter, passed to
  `buildTestApp(mrt: mrt ?? fakeMrtRepository())`.)
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement** in `mapSceneProvider`:

```dart
final selection = ref.watch(optionSelectionProvider);
final mrt = ref.watch(mrtSuggestionProvider);
...
return buildMapScene(
  ...,
  plan: current,
  selectedIndex: current is DirectBusOptions ? selectedOptionIndex(selection, current) : 0,
  // Like the plan: nothing while loading or failed, so a previous journey's
  // stations are never shown. The card shows the error and its Retry.
  mrt: mrt.isLoading || mrt.hasError ? null : mrt.value,
  stops: stops,
);
```

  Update the doc comment. `rideLineProvider` and `MapExpanded.show` need no change.
- [ ] **Step 4: Run them and see them pass,** then the whole `journey_map_card_test.dart`.
- [ ] **Step 5: Mutation checks:**
  - always `selectedIndex: 0`: the F10 tests fail;
  - `mrt: mrt.value` (no settled rule): the reload test fails, because HARBOURFRONT stays visible while
    loading.
- [ ] **Step 6: Commit:** `feat(map): the map follows the selected option and marks the MRT suggestions`.

### Task 6: Draw the connectors, the MRT pins and the legend

**Files:**
- Modify: `lib/features/map/presentation/journey_map.dart`
- Test: `test/features/map/journey_map_card_test.dart`

**Interfaces:**
- Consumes: `MapScene.walks` and the MRT marker kinds.
- Produces:
  - the keys `map-walk-connectors` and `map-legend`;
  - `map-marker-mrtNearOrigin` / `map-marker-mrtNearDestination` (from `kind.name`, as today);
  - `JourneyMap.walkLegend` and `JourneyMap.busLegend(String service)`.

- [ ] **Step 1: Write the failing tests:**

```dart
testWidgets('two dashed connectors whose ends are exactly the markers', (tester) async {
  await pumpApp(tester, app());
  await pickDestination(tester, 'VivoCity', 'VIVOCITY');
  await openMap(tester);
  await tester.pump();
  final layer = tester.widget<PolylineLayer>(find.byKey(const Key('map-walk-connectors')));
  expect(layer.polylines, hasLength(2));
  final at = {for (final m in tester.widget<MarkerLayer>(find.byType(MarkerLayer)).markers) m.key: m.point};
  expect(layer.polylines[0].points, [at[const Key('map-marker-origin')], at[const Key('map-marker-boarding')]]);
  expect(layer.polylines[1].points, [at[const Key('map-marker-alighting')], at[const Key('map-marker-destination')]]);
  for (final p in layer.polylines) {
    expect(p.pattern, isNot(const StrokePattern.solid()));
  }
  expect(tester.widget<PolylineLayer>(find.byKey(const Key('map-ride-line'))).polylines.single.pattern,
      const StrokePattern.solid());
});

testWidgets('layer order: connectors, ride line, markers; in the markers: MRT, ends, stops', (tester) async {
  // FlutterMap.children: index(map-walk-connectors) < index(map-ride-line) < index(MarkerLayer).
  // MarkerLayer.markers keys in order: the mrt* kinds first, then origin/destination, then boarding/alighting.
});

testWidgets('connectors follow the selection (F10: origin → BSH1)', (tester) async { /* ... */ });

testWidgets('connectors, markers and MRT stay when the ride line is unavailable', (tester) async {
  geometry.failure = const StaticDataUnavailable(StaticDataset.busRouteGeometry);
  // open: map-walk-connectors has 2 polylines; map-ride-line absent; map-ride-unavailable shown;
  // both MRT markers present; the legend has the walk entry and no bus entry
});

testWidgets('selecting while the line loads: the new ride only, never the old', (tester) async {
  geometry.hold();
  await pumpApp(tester, app());
  await pickDestination(tester, 'VivoCity', 'VIVOCITY');
  await openMap(tester);
  expect(find.byKey(const Key('map-ride-line')), findsNothing);
  expect(find.byKey(const Key('map-walk-connectors')), findsOneWidget); // needs no data
  await selectOption(tester, 'F10');
  geometry.release();
  await tester.pump();
  await tester.pump();
  final pts = tester.widget<PolylineLayer>(find.byKey(const Key('map-ride-line'))).polylines.single.points;
  expect(pts.first.latitude, closeTo(fakeBusNetwork().stops['BSH1']!.position.latitude, 1e-4)); // not BSH2
  expect(geometry.loads, 1);
});

testWidgets('walk-only and no direct bus: ends and MRT, no connectors, no legend', (tester) async {
  // Bishan MRT (walk-only): map-walk-connectors and map-legend absent; MRT markers present.
  // A journey with no direct bus (as in the fallback path): the same.
});

testWidgets('legend entries; dark mode; 2× text at 360 dp without overflow', (tester) async {
  // light: find.text('Bus F20 route') and find.text(JourneyMap.walkLegend) inside map-legend;
  //   no MRT text inside map-legend
  // dark (platformBrightnessTestValue = Brightness.dark): same entries, no exception
  // 2× text at 360 dp: tester.takeException() is null
});
```

  Also make the existing layer-order test key-based (`map-ride-line` before the `MarkerLayer`), and update the
  summary regex in the existing summary test.
- [ ] **Step 2: Run them and see them fail.**
- [ ] **Step 3: Implement**
  - **Connectors:** before the ride layer,
    `if (widget.scene.walks.isNotEmpty) PolylineLayer(key: const Key('map-walk-connectors'), polylines: [for (final w in widget.scene.walks) Polyline(points: [_toMap(w.from), _toMap(w.to)], strokeWidth: 3, pattern: const StrokePattern.dashed(segments: [10, 8]), color: theme.colorScheme.tertiary, borderStrokeWidth: 1, borderColor: theme.colorScheme.surface)])`.
  - **Markers:**
    - order `[...mrt kinds, ...ends, ...stops]`, where `_isMrt(kind)` is the two new kinds;
    - size 40 for the ends and 30 otherwise;
    - `_MarkerPin` arms: `mrtNearOrigin` / `mrtNearDestination` → `(Icons.train, scheme.secondary)`,
      replacing the Task 3 placeholder.
  - **Legend:** below the map's `SizedBox`, before the notes, when `drawn != null || walks.isNotEmpty`:
    `Padding(key: const Key('map-legend'), …, child: Wrap(spacing: 16, runSpacing: 4, children: [if (drawn != null) _LegendEntry(solid, busLegend(service)), if (walks.isNotEmpty) _LegendEntry(dashed, walkLegend)]))`.
  - **`_LegendEntry`:** a 24 × 4 swatch in the line's colour (solid: one `ColoredBox`; dashed: three 5 px
    boxes with 3 px gaps), then `bodySmall` text.
  - **Constants:** `static const String walkLegend = 'Walk (straight-line estimate)';` and
    `static String busLegend(String service) => 'Bus $service route';`.
- [ ] **Step 4: Run them and see them pass,** then the full `test/features/map/` suite.
- [ ] **Step 5: Mutation checks:**
  - a solid connector: the dashed test fails;
  - drop the `line.ride == widget.scene.ride` guard: the hold/release test fails;
  - connectors only when `drawn != null`: the "unavailable" test fails;
  - MRT pins after the stops: the layer-order test fails.
- [ ] **Step 6: Commit:** `feat(map): dashed walk connectors, MRT pins and a legend`.

### Task 7: Integration paths and documentation

**Files:**
- `integration_test/happy_path_test.dart`
- `integration_test/fallback_path_test.dart`
- `docs/assumptions.md`
- `docs/architecture.md`
- `docs/map-feasibility.md`
- `CLAUDE.md`
- `docs/testing.md`

- [ ] **Step 1: Happy path.**
  - Keep `final geometry = FakeRouteGeometryRepository();` and pass it as `routeGeometry:`.
  - After the existing `map-ride-line` checks:
    1. Expect `map-walk-connectors`, `map-marker-mrtNearOrigin` and `map-marker-mrtNearDestination`.
    2. Note `arrivals.totalCalls`.
    3. `scrollToAndTap` on `select-option-F10`, then pump.
    4. `pumpUntilFound` the `map-ride-line`.
    5. Expect the boarding marker at BSH1, `geometry.loads == 1`, and `arrivals.totalCalls` unchanged.
- [ ] **Step 2: Fallback path.**
  - Keep `final geometry = FakeRouteGeometryRepository();` and pass it.
  - After the existing "No direct bus" and MRT text checks:
    1. `scrollToAndTap` on `show-map`.
    2. `pumpUntilFound` on `map-marker-mrtNearOrigin`.
    3. Expect `map-marker-mrtNearDestination`, origin and destination.
    4. Expect no boarding marker, no `map-walk-connectors`, no `map-legend`, no `map-ride-line`, and
       `geometry.loads == 0`.
  - Then `scrollToAndTap` on `hide-map`, so the rest of the test runs as before.
- [ ] **Step 3: Run them.**
  - Android: `flutter test integration_test -d <emulator>`.
  - Web: each of the three targets with
    `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/<file> -d web-server --browser-name=chrome --profile`.
  - Count CSP violations in the browser log; expect 0.
- [ ] **Step 4: Documentation** (next section).
- [ ] **Step 5: Commit** in two commits: `test(integration): option sync, connectors and MRT markers` and
  `docs(p2-m3): option selection, walk connectors, MRT markers, legend`.

### Task 8: Final verification and PR

- [ ] Run all the gates and live checks below on the final head, and log every result in `docs/testing.md`.
- [ ] Commit the log (`docs(testing): P2-M3 gates and live checks`), push the feature branch, and open the PR
  against `main`. **Do not merge.**

---

## Documentation updates (Task 7)

**Documentation superseded or changed:**

- **`docs/assumptions.md`**
  - **"Journey map (P2-M1)":**
    - "the **suggested** option's boarding and alighting stops" becomes "the **selected** option's (the
      suggestion until the user selects another)";
    - "while the plan is loading or has failed, only the two ends" becomes "the two ends (plus the MRT
      markers once the MRT suggestion has settled)";
    - "Walk-only, no-direct-bus and no-nearby-stop answers mark the two ends" gains "and the MRT markers".
  - **"Map camera":** "fitted to the markers and the suggested ride's stops … once per journey" becomes "…
    the selected ride's stops (and the MRT markers) … once per scene change: journey, option selection, or
    the MRT suggestion settling".
  - **"Bus ride line (P2-M2)":** "The suggested option's ride" becomes "The selected option's ride".
  - **"Route geometry load (P2-M2)":** add "selecting another option never reloads it".
  - **New row "Journey option selection (P2-M3)":** D1–D3.
  - **New row "Walking connectors and legend (P2-M3)":** D4–D6, with `walkConnectorMinMeters = 1`.
  - **New row "MRT markers (P2-M3)":** D7. Both sides from `mrtSuggestionProvider`, at the nearest exit,
    labelled with the card's wording, nothing while loading or failed, in the bounds, drawn under the
    journey pins, informational only.
- **`docs/architecture.md`:** a new "Phase 2 Milestone 3" section (files, data flow, the dependency
  direction, the settled-value rule for the plan and the MRT, and "Not in P2-M3"). The P2-M2 section's
  "Not in P2-M2: … option sync" stays as history.
- **`docs/map-feasibility.md`:**
  - §10 P2-M3: mark it done as specified (connectors, MRT markers, option sync, legend);
  - §11 item 3: walking decided (straight-line "est." connectors, P2-M3); `routed-foot` stays a P2-M4
    question.
- **`CLAUDE.md`:**
  - the Map paragraph's "suggested option" becomes the "selected option";
  - add `optionSelectionProvider` (journey-owned, plan-identity bound), the connectors (derived from the
    markers, dashed, no router), and the MRT markers (read from `mrtSuggestionProvider`, settled values
    only);
  - test seams are unchanged.
- **`docs/testing.md`:**
  - run-log rows for the implementation evidence, gates and live checks;
  - the Integration-tests section, where the happy and fallback paths' descriptions list their steps.
- **Code comments:** the "suggested" wording in `map_scene.dart` and `map_providers.dart` (Tasks 2 and 5).

## Quality gates (Task 8; all must actually pass)

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
flutter test integration_test -d <android-emulator>
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_boot_test.dart     -d web-server --browser-name=chrome --profile
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/happy_path_test.dart   -d web-server --browser-name=chrome --profile
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/fallback_path_test.dart -d web-server --browser-name=chrome --profile
```

- **`flutter test --platform chrome`: Not run.** The known flutter_tools Windows path bugs (logged
  2026-10-03) apply. P2-M3 adds no Web-specific arithmetic.
- **Before serving for the live checks,** rebuild with `flutter build web --release`: `flutter drive` leaves a
  test build in `build/web`.

## Live checks (real APIs; log in `docs/testing.md`)

**Web** (release build, served locally):
1. Bishan → VivoCity, or any trip with at least 2 options. Open the map. Check:
   - the suggested line, two dashed connectors, and the legend ("Bus N route", "Walk (straight-line
     estimate)");
   - MRT pins near the start and the destination, whose tooltips match the card's "MRT alternative" names.
2. Select an alternative. The boarding and alighting markers, the line and the connectors move to it, and
   the camera refits once.
3. In DevTools → Network:
   - exactly one `routes.min.json` for the session;
   - **no** ArriveLah request on selecting;
   - no OneMap tile before "Show map";
   - no request at all for the MRT pins.
4. Select while the map is hidden, then "Show map": it opens on the selection.
5. Change the destination:
   - the card is back at "Suggested", and the map shows the new suggestion;
   - the destination-side MRT pin changes to the station the card now names.
6. A walk-only trip (e.g. to Bishan MRT) and a no-direct-bus trip: the ends and MRT pins only, no
   connectors, no legend.
7. Dark mode (Night tiles): connectors, line and pins readable. 2× text at 360 dp: no overflow; the legend
   wraps.

**Android** (emulator, set an SG location): steps 1, 2, 4, 5, 6 and 7, plus TalkBack on the select control
("Select Bus N", "Bus N selected").

## Commit boundaries (summary)

| Task | Commit |
|---|---|
| 1 | `feat(journey): option selection tied to the plan object` |
| 2 | `feat(map): the scene shows the selected option, with straight walk connectors` |
| 3 | `feat(map): MRT suggestion markers in the scene` |
| 4 | `feat(journey): select a direct-bus option in the journey card` |
| 5 | `feat(map): the map follows the selected option and marks the MRT suggestions` |
| 6 | `feat(map): dashed walk connectors, MRT pins and a legend` |
| 7 | `test(integration): option sync, connectors and MRT markers`; `docs(p2-m3): …` |
| 8 | `docs(testing): P2-M3 gates and live checks` |

## Required-test coverage map

| Requirement | Test (task) |
|---|---|
| Suggested selected initially | T1 "no selection → 0"; T4 "selected first" |
| Select alternative #2 → journey and map consistent | T4 select F10; T5 boarding and line |
| Switch back to #1 | T4 "then back to F20" |
| Markers after a change | T2 F10 markers; T5 boarding |
| Bus line after a change | T5 via MID1; T5 F10 → F30 via ION1 |
| Connectors after a change | T2 exact endpoints; T6 "follow the selection" |
| Old line never attached to the new option | T6 hold/release; the existing P2-M2 stale-ride test |
| Change while geometry loads | T6 hold/release |
| One successful `routes.min.json` load | T5 and T6 `geometry.loads == 1`; T7 integration |
| Geometry unavailable → connectors, markers, MRT fine | T6 "stay when unavailable" |
| Connector endpoints exact | T2 (domain); T6 (drawn = markers) |
| Walk-only / no direct bus / no stops | T2 "no walks"; T3 "every answer"; T6; T7 fallback path |
| No planner recomputation | T1 "never creates the plan provider"; T4 identical plan, `bus.loads` |
| Arrivals on a change | T4 identical `JourneyArrivals`, `totalCalls`, "Refresh keeps"; T7 `totalCalls` |
| Map closed, select, then open | T5 |
| Camera bounds for the selection and MRT | T2/T3 bounds; T5 visible bounds |
| MRT: which, where, label | T3 (domain); T5 tooltips |
| MRT: never stale, failure-safe | T5 held repository; T5 failure |
| MRT: layering | T6 layer order |
| MRT: summary / accessibility | T3 summary |
| Android/Web happy and fallback paths | T7 |
| Accessibility (select control) | T4 semantics, 2× text; T6 legend at 2× |

## Risks and ambiguities

1. **Identity-based reset.** Any re-plan resets the selection to "Suggested", including "Retry finding a
   bus" and an origin change. This is intended and documented.
2. **MRT markers widen the fitted view** by up to 1.5 km beyond an end. This follows from the existing
   "bounds hold every marker" rule, and it keeps the existing camera test valid.
3. **The same station on both sides:** two pins at the same exit, drawn as given and not merged (D7).
4. **Dashed lines with a border.** flutter_map draws the border dashed too. The look on Night tiles has to
   be checked live.
5. **Summary text changes:** two existing tests change their expected strings, deliberately.
6. **Fake geometry is straight through the stops,** so the tests prove which ride is drawn, not road
   realism. Real lines are covered by the live check.
7. **`journey_card.dart` and `journey_map.dart` each grow a little** (one small private widget each).
   Splitting them is out of scope.

## Simplification note

The design needs no generalized map-leg framework: two derived straight segments, an index tied to the plan
object, and two more marker kinds read from an existing provider. If a smaller PR is ever wanted, option
sync (Tasks 1, 2, 4, 5) and the visuals (Tasks 3, 6) can ship separately. As planned, they ship together.

## Self-review notes (2026-10-04, against `main` at `70a74cb`)

- **Re-checked against the code:**
  - `journey_card.dart` (`options.first` at :115, the `_Option` structure);
  - `map_scene.dart` (`options.first` at :116, `bounds` over all markers, the summary built by kind);
  - `map_providers.dart` (`mapSceneProvider`'s settled-plan rule, `rideLineProvider`'s ride select,
    `MapExpanded.show`);
  - `journey_map.dart` (the `line.ride == scene.ride` guard, `didUpdateWidget` refit, marker ordering by
    `_isEnd`, keys from `kind.name`);
  - `bus_arrival_providers.dart` (all boarding stops, `arrivalsFor` identity);
  - `mrt.dart` and `journey_providers.dart` (`mrtSuggestionProvider` record type, `nearestExit`);
  - `MrtAssetRepository` (caches a success, so a test-local subclass holds each call);
  - `test_app.dart` (`mrt:` parameter; no generic overrides needed);
  - `fake_bus_network.dart` (F20/F10/F30 to VivoCity, `fakeMrtStations`);
  - the existing map tests, which find markers by key, not by count, so the new MRT markers don't break
    them.
- **Spec check for MRT:** §10 says "markers" (plural) from `mrtSuggestionProvider`; guide §9.5 says the
  nearest station to each end; the card shows both. Hence both sides, and no invented "recommended" one.
- **Scope check:** nothing beyond the frozen D1–D9.
  - no MRT legend entry, no MRT codes or lines;
  - no walk-only connector;
  - no router;
  - no new dependency;
  - no new network request;
  - no change to the planner, the arrival or the MRT logic.
