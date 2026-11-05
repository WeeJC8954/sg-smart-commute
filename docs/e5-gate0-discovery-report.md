# E5 Gate 0: Discovery and Feasibility Report (one-transfer Bus → Bus)

**Status:** Gate 0 deliverable for owner review, 2026-11-05. Discovery only: it adds no production code, test,
dependency, data file or implementation branch. Nothing here is approved. Every "Proposed" item needs an owner
decision (§11).

**Governing documents:** `docs/sg-smart-commute-next-phase-master-plan.md` (the roadmap; this is its Gate 0, with the
Gate 1 analysis the owner asked for), `CLAUDE.md`, `docs/architecture.md`, `docs/assumptions.md`,
`docs/data-sources.md`. The historical E5 report and E6 addendum are still unavailable. This report does not
reconstruct them and gives E6 no meaning; what it says about them comes only from the citations in the E2 plan
(§2.4).

Each item is tagged in the margin:

| Tag | Meaning |
|---|---|
| **[C]** | Confirmed: read from the code or data, or measured, with its source |
| **[A]** | Assumption, not verified |
| **[P]** | Proposal, needs approval |

## 1. Summary

- **Feasible within the hard constraints [C].** A one-transfer search needs no new provider, host, key or file. It
  runs on the busrouter `stops.min.json` and `services.min.json` the app already loads, and it is fast.
  - Dart VM: median 0.4–0.9 ms per query and at most 6.6 ms over 500 random pairs (§5).
  - The index has 26,957 stop entries and is built in about 15 ms.
- **Useful [C].** In a sample of 500 random stop pairs at least 1.5 km apart, the current planner found a direct bus
  for 38.6%. One transfer would serve another **47.8–49.2%**, depending on the transfer walk. That leaves 12–14% with
  neither; about half of those have an end with fewer than 4 services within 800 m.
- **The main design risk is ranking, not the search [C].** With no transfer penalty, the best transfer scored better
  than the best direct bus in 169 of 193 pairs that had both. The present score (`walk + walk + 1.5 × stops`) has no
  waiting time, and **no keyless headway data exists** (§4.3). So mixing transfers with direct buses would often
  demote the direct bus.
- **Recommendations [P]:**
  - The ordered-leg model as a small sealed type, introduced only where needed; the direct planner and its types
    stay as they are (§7).
  - Phase 1 of E5 searches transfers **only when there is no direct bus** (§8.1).
  - Same-stop transfers first, with a bounded nearby-stop walk as a decision (§8.2).
  - The waiting time is shown as **not included**, never estimated (§8.4).

## 2. Verified baseline [C]

| Item | Value |
|---|---|
| `main` | `67ebe20` (merge of PR #88, E8 close-out); E8 code merge `d58971d` (PR #87) |
| CI on `main` | Run 42039761075 succeeded: `flutter test` 959 passed, Chrome step 32 passed (workflow `.github/workflows/flutter-test.yml`) |
| Working tree | Clean, `main` equal to `origin/main` (at the start of Gate 0) |
| Open issues | #82 only (the repository secret; untouched). #80 and #81 were closed by the PR #87 merge |
| Open PRs | None before this report's PR |
| Toolchain | Flutter 3.47.2 / Dart 3.13.2 (by full path, `CLAUDE.md`) |

### 2.1 Where E5 would touch the code (repository map)

| Area | Files | Role today |
|---|---|---|
| Data | `features/journey/data/busrouter_parser.dart`, `busrouter_repository.dart` | Parses stops `[lng, lat, name, road]` and services (1–2 ordered directions). Drops unknown stop codes and directions under 2 stops; keeps `sourceDirections` |
| Model | `features/journey/domain/bus_network.dart` | `BusStop`, `BusService` (`directions`, `sourceDirectionOf`), `BusNetwork` |
| Planner | `features/journey/domain/direct_bus_planner.dart` | Pure `planDirectBus`. Sealed `JourneyPlan` = `WalkOnly`, `DirectBusOptions`, `NoNearbyStops`, `NoDirectBus`. `BusOption` (service, direction, board, `boardIndex`, alight, `stops`, two walks, score, `towardName`, `isLoop`) |
| Estimates | `domain/walking.dart` (`WalkEstimate`), `domain/journey_estimate.dart` (E2 `estimateBusMinutes(network, service:, direction:, boardIndex:, stopCount:)`: already per leg, ADR E2-5) | Walk and ride estimates |
| State | `journey_providers.dart` | `journeyPlanProvider` (plans on origin/destination change), `busNetworkProvider` (once per session), `optionSelectionProvider` (tied to the plan object) |
| UI | `presentation/journey_card.dart` (664 lines) | Suggested option, alternatives, Select, steps, E2 estimate, MRT section |
| Arrivals | `features/bus_arrival/bus_arrival_providers.dart`, `presentation/option_arrivals.dart` | One ArriveLah request per displayed **boarding** stop through `BusArrivalCache` (15 s TTL) |
| Map | `features/map/domain/map_scene.dart`, `ride_geometry.dart`, `map_providers.dart` | `MapScene` with **one** `MapRide`, walk connectors and markers; `matchRide` all-or-nothing on `routes.min.json` |

`BusOption` and `DirectBusOptions` are used in 6–8 files (planner, estimate, journey card, arrivals ×2, map scene, map
providers, option selection). That is the blast radius of any change to those types.

## 3. Scope recap (master plan §5)

```text
Origin → walk → Bus A → transfer (same stop, or a short walk) → Bus B → walk → Destination
```

Direct options keep working. The scope excludes MRT legs, two or more transfers, timetables, routed walking and any
new provider.

## 4. Data assessment

### 4.1 Static network [C] (fetched 2026-11-05 13:57 UTC)

| File | Size | Headers | Content |
|---|---|---|---|
| `stops.min.json` | 317,298 B | HTTP 200, CORS `*`, `max-age=86400`, `application/json` | 5,209 stops |
| `services.min.json` | 256,632 B | the same | 604 services, 801 directions; 33.7 stops per direction on average, at most 105; 26,957 (stop, direction, position) entries |
| `routes.min.json` | 290,074 B | the same | Geometry per direction (map only, lazy) |

- **Already loaded [C].** All three are under the 4 MiB response cap, the host is already in the CSP `connect-src`,
  and they need no key.
- **Order but no times [C].** The services give ordered stops per direction. They have no timetable, headway or
  travel times.
- **Licence [C].** Unchanged: `docs/data-sources.md` ("© LTA" via busrouter; re-check before any wider release).

### 4.2 Live arrivals [C]

- **What ArriveLah gives.** It gives arrivals at a stop for every service there: next, next2 and next3, with times
  (`docs/data-sources.md`). For a transfer, the second leg's bus at the transfer stop is in the future: "now" at the
  transfer stop is not when the rider gets there.
- **Request count.** Each displayed transfer option adds at most one stop to request: its transfer stop. ArriveLah is
  not data.gov.sg, so the 6-per-10-s limit does not apply to it. It has no SLA.

### 4.3 Waiting time and headways [C]

- **busrouter has no frequency field.** `https://data.busrouter.sg/v1/raw/bus-services.json` (81,353 B, CORS `*`) holds
  only `number`, `type`, `kmlFile`, `routeFile` per service. `raw/bus-services.datamall.json` is a 404.
- **DataMall needs a key.** LTA DataMall Bus Services carries the frequencies but needs an AccountKey, so it is out
  of scope (`CLAUDE.md`, ADR-001).
- **Conclusion.** There is **no keyless source of scheduled headways.** A waiting time could only come from live
  ArriveLah ETAs, or not be shown at all (§8.4).

### 4.4 E2 reuse [C]

`estimateBusMinutes` takes exactly one leg's fields, so each bus leg can be estimated with no E2 change. The E2
calibration (off-peak, first and last trips) and its error bands apply per leg (the "Estimated trip time (E2)" row of
`docs/assumptions.md`). A total over two legs adds the error of both legs and **leaves out the transfer wait**.

## 5. Measurements [C]

**Method.**
- A throwaway Dart program outside the repository, deleted after the run and never committed. It read the files of
  §4.1 and mirrored the parser's drops and the direct planner's matching (first occurrence after the boarding
  index, loops, the 400 m then 800 m radius).
- It ran a one-transfer search (§6) on 500 seeded random pairs of stops at least 1.5 km apart. Each end was moved
  about 66 m off its stop, as a user would stand.
- Dart VM (JIT), Windows 11 dev PC. **Not dart2js or Chrome, and not a phone (§10).**

| Transfer walk | Direct found | No direct, 1 transfer | Neither | Search time (median / p95 / max) | Most labels / joins |
|---|---|---|---|---|---|
| Same stop only | 38.6% | 47.8% | 13.6% | 0.45 / 1.6 / 6.4 ms | 8,023 / 1,657 |
| ≤ 150 m | 38.6% | 49.0% | 12.4% | 0.75 / 2.4 / 4.1 ms | 8,023 / 4,753 |
| ≤ 250 m | 38.6% | 49.2% | 12.2% | 0.94 / 2.9 / 6.6 ms | 8,023 / 6,896 |

Other results:
- **Loading.** The JSON parse took 64–71 ms; building the stop index and a 250 m grid took 14–15 ms.
- **Ranking (same-stop transfers, 193 pairs with both a direct bus and a transfer).** The best direct score minus the
  best transfer score, with no transfer penalty, was:

  | p10 | p25 | median | p75 | p90 |
  |---|---|---|---|---|
  | 0.0 | 3.0 | 6.5 | 16.5 | 33.0 |

  A penalty of about 10 would still let a transfer win in roughly a third of these pairs. [A] This is read from the
  distribution and was not run with a penalty.
- **Detour.** The two rides' straight-line distance between consecutive stops, against the straight line from origin
  to destination: median 1.37, p95 2.58, max 8.0 (up to 8.4 with a 250 m transfer walk). So a detour limit is needed (F1/F3).
- **"Neither."** 61–68 pairs. In 27–29 of them, an end had fewer than 4 services within 800 m. The rest may need two
  transfers or MRT. [A] Not analysed further.

**Caveats.**
- **The pairs are random, not weighted by demand [A].** Real trips (HDB towns to the centre and interchanges) may
  differ.
- **The score is a proxy [C].** It is `walk + 1.5 × stops`, not minutes. E2 minutes per leg were computed only for the
  detour ratio.

## 6. Routing approach (proposal) [P]

Use a bounded two-sided join, not a general graph search. With at most one transfer, Dijkstra or A* over all stops
adds nothing (master plan §7: do not assume them).

```text
index once per network: stop code -> [(direction, position)]; grid of stops (~250 m cells)
O = candidate stops near origin (400 m, then 800 m as today); D = the same near destination
forward:  for each o in O, each (dir, i) at o, each k > i (first occurrence, as the direct planner):
            keep best legA[stop r[k]][dir] = walk(o) + 1.5 x (k - i)
backward: for each d in D, each (dir, j) at d, each m < j with r[j] the first occurrence after m:
            keep best legB[stop r[m]][dir] = walk(d) + 1.5 x (j - m)
join:     for each stop x with legA, each stop y within the transfer walk of x (y = x if same-stop only),
            each legA at x and legB at y with service(A) != service(B):
            score = A + B + transferWalk(x, y) + transferPenalty
            reject by the detour, loop and duplicate rules (F1)
          keep the best per (service A, service B); return the top N, deterministic tie-breaks as today
```

- **Cost [C].** About |O|·(stops after boarding) + |D|·(stops before alighting) labels, then a join over the shared
  stops. That measured as at most about 8k labels and 7k joins (§5).
- **Memory [C].** About 27k index entries plus the grid. The network already in memory dominates.
- **Determinism [P].** Pure function, fixed tie-breaks: score, total stops, then service numbers in natural order
  (`compareServiceNumbers`), then stop codes.

## 7. Architecture: ordered legs vs an adapter

| | (A) Ordered-leg model in E5 | (B) Adapter around the direct types |
|---|---|---|
| Shape | Sealed `JourneyLeg` = `WalkLeg`, `BusLeg(service, direction, boardIndex, stopCount, board, alight)`; `TransferJourney(legs)` with invariants (ordered, one transfer, bus legs valid) | `TransferOption(first: BusOption, second: BusOption, transfer)` reusing `BusOption` twice |
| Direct buses | **Unchanged.** `BusOption` and `DirectBusOptions` stay; a new plan variant carries transfer journeys | Unchanged |
| Future MRT and multimodal | Add a `RailLeg` later with no rework of the transfer UI or map | Needs a rewrite to more than two legs or other modes |
| Cost now | A new sealed type, a plan variant, a leg-list UI, a map with N rides | Less now. `BusOption` carries per-option fields (score, both walks) that are wrong for a leg |
| Risk | It could grow into unused rail abstraction, so keep it to Walk and Bus legs only | Two bus legs that each own an origin and destination walk; the walks and scores would mislead |

**Recommendation [P]: (A), limited to the legs E5 uses** (`WalkLeg`, `BusLeg`, and a transfer as a walk leg, possibly of
0 m). Do not migrate `BusOption` in E5. A direct option could be shown as a one-bus leg list later, if the owner wants
that. This matches the E6-addendum direction that the E2 plan cites, without depending on the lost text.

## 8. Compatibility and UX (proposals) [P]

### 8.1 When transfers are searched

- **Option 1 (recommended).** Search only when the plan would be `NoDirectBus`, or when `NoNearbyStops` falls on
  neither side. Direct results, ranking, selection, arrivals and map are then **byte-for-byte unchanged** for every
  journey with a direct bus. This is checkable with the existing tests plus a pinned fixture comparison.
- **Option 2.** Always search, and show "With one change" under the direct options. This needs a ranking decision
  (F3) and changes what users see on today's direct journeys.

### 8.2 Transfer walk (F2)

- Same-stop transfers serve 47.8%; up to 250 m serves 49.2% (+1.4 points).
- A walk between stops crosses roads, which the straight-line estimate cannot see.
- **[P]** Start same-stop only, plus opposite-pair stops if the owner wants (a bounded radius such as 150 m, shown as
  an estimate).

### 8.3 Ranking (F3)

- **[P]** Score = `walk1 + 1.5 × stops1 + transferWalk + transferPenalty + 1.5 × stops2 + walk2`.
- The transfer penalty is a fixed number standing in for the unknown wait. It is set from the §5 distribution and
  recorded in `docs/assumptions.md`.
- Reject a journey whose ride-to-straight-line ratio is above a limit (proposal: 2.5, about p95). Also reject the same
  service on both legs, and a second leg that returns to a stop the first leg used.
- Keep the best per (A, B) pair, and show at most 3.

### 8.4 Waiting time (F4)

- **[P] Exclude it, and say so** ("Waiting time not included").
- The leg estimates may be shown, using E2, each rounded as E2 does. A total, if shown, is labelled as excluding
  waiting at both stops.
- Live arrivals: the first leg's boarding stop as today. The transfer stop's live ETAs could be shown as "Bus B at the
  transfer stop now", clearly not "when you arrive"; or not shown in E5.
- No fabricated connection time.

### 8.5 Other areas

- **UI and map (F8).** A transfer card lists the legs in order: walk, Bus A (board → alight, stops), the transfer
  instruction, Bus B, walk. The map draws two ride lines with the same all-or-nothing `matchRide` per leg, plus the
  walk connectors and the transfer point. `MapScene` gains a list of rides (one today).
- **What must hold.** Ten themes, E7/E8 focus rules (a control that removes itself hands focus on), semantics, touch,
  360 px with 2× text.
- **Failure modes (F6).** These are as today:
  - no bus data: the existing error and Retry;
  - no route: "No direct bus or one-change route found";
  - a missing arrival: "No live arrival available";
  - geometry that does not match: markers and a note, per leg.

## 9. Risks

| Risk | Tag | Mitigation |
|---|---|---|
| Transfers demote good direct buses | C (measured) | Option 1 of §8.1, or a penalty with a regression fixture |
| A long detour or loop looks "best" | C (max ratio 8) | Detour limit, the loop and duplicate rules, fixtures |
| Web (dart2js) slower than the VM | A | Gate 1 benchmark in Chrome; the budget in §10 |
| No headways, so the trip time is optimistic | C | Exclude the wait and label it (§8.4) |
| Busrouter schema or data drift | C (no SLA) | The existing parser validation; a fixture from today's files |
| The card and map grow complex (a11y, 2× text) | A | One leg-list widget; E7/E8 rules; 360 px tests |
| Scope creep to MRT or two transfers | A | Sealed legs limited to Walk/Bus; master plan gates 5–6 |

## 10. Proposed measurable acceptance criteria [P]

1. **Correctness on fixtures:**
   - every bus leg rides forward in its direction, with `boardIndex < alightIndex` (first occurrence, loops as the
     direct planner);
   - the two services differ;
   - the transfer is at the same stop, or within the approved walk;
   - no journey is over the detour limit;
   - no duplicate (A, B) pair.
2. **Unchanged direct buses** (option 1 of §8.1). For a pinned set of at least 50 origin/destination fixtures with a
   direct bus, the plan, the order of options, the scores, the arrivals requests and the map scene are identical to
   pre-E5 `main`. All existing tests pass.
3. **Coverage.** On a pinned data snapshot and a pinned random sample, transfers are found for at least 45% of pairs
   with no direct bus. The run is reported with the counts, not just the threshold.
4. **Performance budget:**
   - the one-transfer search under 50 ms p95 and 150 ms max in **Chrome (dart2js)**, and under 20 ms p95 on the Dart
     VM;
   - the index built once per network in under 100 ms in Chrome;
   - the measurements recorded with their device.

   **[A]** These are proposals derived from the VM figures (§5) with a margin for dart2js, and are not yet measured
   there.
5. **No new host or request on load.** The CSP is unchanged. ArriveLah requests are at most one per displayed stop
   that needs them, through the cache.
6. **Honest times.** Each leg's estimate comes from E2; any total says that waiting is excluded; nothing is invented
   when a leg estimate is omitted.
7. **Accessibility and UI.** Ten themes, 2× text at 360 px, keyboard focus (E7/E8), semantics of the leg order, and
   the map's two rides all pass, by widget tests and a Web live check. Hardware and screen-reader checks are logged as
   Not run when not done.
8. **Evidence.** Test first per task, with mutation checks on the critical rules (direction, order, detour, same
   service, penalty, unchanged direct buses). The run log is in `docs/testing.md`.

## 11. Decisions requiring owner approval

| ID | Decision | Recommendation |
|---|---|---|
| G0-1 | Accept this Gate 0 report and move to the Gate 2 plan-only PR (the analysis usually done at Gate 1 is in §5–§8), or ask for a separate Gate 1 report first | Move to Gate 2 after the decisions below, with the Chrome benchmark as Gate 2's first task |
| F1 | Transfer discovery: the same-stop join plus the rules in §8.3 (different services, forward order, no return, detour limit) | Approve. Detour limit 2.5 (a proposal, tuned on fixtures) |
| F2 | Transfer walk: same stop only, or ≤ 150 m (or ≤ 250 m) | Same stop plus ≤ 150 m, shown as an estimate. Or same stop only for a smaller E5 |
| F3 | Ranking and when to search: option 1 of §8.1 (only when no direct bus) or option 2 (always; needs a penalty value) | Option 1. If option 2: a fixed penalty set from the measured gaps and recorded in `assumptions.md` |
| F4 | Waiting time: exclude and label, approximate from live ETAs, or show the transfer stop's live ETAs as "now" | Exclude and label. No transfer-stop live ETAs in E5 |
| F5 | Performance budget of §10.4 | Approve as the Gate 2 target, measured in Chrome |
| F6 | Failure texts of §8.5 | Approve. Exact wording in the plan |
| F7 | No new data or host: busrouter files only | Approve |
| F8 | UI: a leg-list card and two ride lines on the map | Approve the shape; details in the Gate 2 plan |
| A1 | Architecture: (A) ordered legs, limited to Walk and Bus legs, with `BusOption` unchanged | Approve (A) |

## 12. Not done in Gate 0

- No production code, test, branch for implementation, dependency or data file.
- The benchmark is not in the repository: it was throwaway and is described in §5.
- Not measured:
  - dart2js or Chrome speed;
  - a phone;
  - demand-weighted origin/destination pairs;
  - two-transfer coverage of the "neither" pairs.
- No live UI prototype.
