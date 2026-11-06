# E5 Gate 2: Implementation Plan (one-transfer Bus → Bus)

**Status:** Gate 2 plan-only deliverable, 2026-11-06. **No E5 production code exists or is authorized.**
- **Owner's rulings:** two rounds on 2026-11-06 (§12.1). The plan is **conditionally approved** (G2-0). Gate 3 is
  authorized only after this replacement plan PR is merged and the existing fixture-licensing concern is assessed
  (`docs/busrouter-fixture-licensing-audit.md`).
- **Why a replacement PR:** this plan replaces PR #90, closed unmerged so that its snapshot commit never reaches
  `main` (G2-10).
- **What this PR adds:** this plan, the audit, and a development-only benchmark (`tool/e5_transfer_bench/`, owner
  ruling F5). The benchmark never commits its input, and downloading that input is optional (§2.8).
- **Nothing changes** under `lib/`, `web/`, `android/` or `pubspec.*`.

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
- **Fixed input:** busrouter `stops.min.json` and `services.min.json`, byte-identical to `data.busrouter.sg` on
  2026-11-06 12:27 UTC and to `cheeaun/sgbusdata` at commit `a60fe9e` (2026-11-01). `fetch_snapshot.sh` downloads
  them from that commit into the git-ignored `build/` and checks their SHA-256 (README). 5,209 stops, 604 services,
  801 directions, 26,957 (stop, direction, position) entries: the same counts as Gate 0's fetch.
- **App code:** the app's own parser, `planDirectBus` and E2 `estimateBusMinutes` / `estimateDirectJourney`. The transfer search is a prototype
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

Six Chrome runs and six VM runs on 2026-11-06 (ranges across runs; prototype search, same stop, limit 2.5, over
the 301 no-direct pairs, 903 timed queries per run):

| Measure | Chrome 156 (dart2js -O4) | Dart VM | §10.4 target |
|---|---|---|---|
| One-transfer search, warm, median | 1.7–2.8 ms | 1.9–2.2 ms | |
| One-transfer search, warm, p95 | **3.8–5.6 ms** | 3.4–3.8 ms | < 50 ms Chrome, < 20 ms VM |
| One-transfer search, warm, max | **10.3–17.6 ms** | 4.8–6.4 ms | < 150 ms Chrome |
| First (cold) search | 9.5–10.4 ms | 20.9–23.9 ms | |
| Transfer index build, once per network | **8.2–12.6 ms** | 22.5–27.2 ms | < 100 ms Chrome |
| `planDirectBus` (today's planner), warm, p95 | 5.8–6.9 ms | 4.5–4.9 ms | |
| Parse (`jsonDecode` + parser), cold | 15.7–20.8 ms | 39.9–47.4 ms | |

- Chrome rounds `performance.now()` to 0.1 ms, so these are 0.1 ms resolution.
- **Every target holds with a wide margin [C]:** 8–9× in Chrome, 5× on the VM. A journey with no direct bus costs today's planner plus the
  search: under about 12 ms p95 in Chrome on this PC.
- **Recommendation [P]: keep the §10.4 targets unchanged** (G2-3), and add one: the first search of a session, index
  build included, under 100 ms in Chrome. The margin is kept on purpose: no phone was measured, and a mid-range
  Android phone's Chrome could be several times slower [A].
- Gate 3 points the benchmark at the real implementation. If the owner permits the download (T8), it records the
  same table; otherwise the timing evidence is the table above, with the run logged as Not run.

### 2.5 Ranking among transfer journeys

Under F3 option 1, transfer journeys are ranked only against each other, so a fixed transfer penalty changes nothing
and is dropped (Gate 0 §13). The score is the direct planner's, extended:
`walk to stop + 1.5 × stops on bus 1 + 1.5 × stops on bus 2 + walk from stop` (minutes and stops; no wait).

G2-4 [D, provisional]: keep it for now. The comparison the owner asked for is §2.7.

### 2.6 Other observations

- **[C]** Several best journeys use express or limited services (`851e`, `97e`, `43e`, `89e`, `174e`). busrouter has no
  operating hours, so neither the direct planner nor E5 can tell that such a bus is not running now. This is an
  existing limit of the direct planner, not new in E5. The card's wording does not claim the bus runs now (§4.6).
- **[C]** Coverage criterion of Gate 0 §10.3 ("at least 45% of no-direct pairs") is exceeded: 76.1%. The Gate 3
  criterion becomes exact in the optional T8: the implementation serves exactly the pairs the benchmark does on the pinned input,
  or each difference is explained.

### 2.7 G2-4: stop-count ranking against E2 minutes

The owner's request: compare the two orders on the pinned fixtures and representative journeys, look at the largest
differences, and say whether the stop-count order is reasonable enough for the first release. E2 is used here only to
measure; nothing in the planner changes. Method (`bench.dart`, `_rankingSection`):
- the search keeps every journey (same stop, limit 2.5, no cap);
- **A** is the score order, as planned;
- **B** is the order by E2 minutes: the walks plus each ride rounded up, before E2's 5-minute rounding, no wait.

| | Transfer journeys (sample: 229 pairs with a journey) | Direct options today (sample: 199 pairs, planner uncapped) |
|---|---|---|
| A and B pick a different first journey | **46 (20%)** | 7 (3.5%) |
| A first slower than B first: p50 / p90 / max | 3 / 22 / **35 min** | 1 / 13 / 13 min |
| B first among the 3 shown under A | 37 of 46 | 7 of 7 |
| A shown journey within 5 min of B first | 43 of 46 | |
| B first's rank under A: p50 / max | 2 / 9 | |

- **Named fixtures [C].** 11 of the 12 rank the same first journey under A and B. Sengkang Int → Jurong East Int
  differs: A's Bus 654 (9 stops) then 97e (16 stops), 111 min, against B's Bus 109 (22 stops) then 506 (29 stops),
  101 min.
- **The largest gaps [C].** All 8 largest come from a score-first journey with a long detour (1.78–2.30) on services
  that make few stops over long distances.
  - Example: 46429 → 78039. A takes Bus 648 (14 stops) then 661 (5 stops), detour 1.87, 125 min. B takes Bus 969
    (20 stops) then 109 (11 stops), detour 1.21, 90 min. B is A's 2nd of 11.
  - The score counts stops, not distance, so a 14-stop express ride "costs" less than a 20-stop ride that covers
    the same ground faster.
- **City Direct services [C].** busrouter's raw `bus-services.json` marks 35 services `CITYDIRECT`, for example 647,
  648, 649, 660, 661 and 678. One of them is on A's first journey in **15 of the 46 differing pairs, and in 9 of the
  16 pairs with a gap of 10 min or more**, but on B's first in only 4. These services carry few stops between towns and
  the city. [A] They run only at peak hours in one direction. busrouter has no hours, so the app cannot tell, and the
  E2 estimate, fitted off-peak, is least reliable for them.
- **The direct planner shows the same weakness, much smaller [C].** Direct options for one pair share both ends, so
  their distances are similar. Transfer journeys allow detours up to 2.5 on two rides, so stops and distance diverge
  more.

**Assessment: reasonable enough for the first release, with its limit disclosed.** The owner approved keeping the
score order (G2-4 [D]):
- Every journey shown is valid.
- Each one shows its own estimate, so the faster option is visible.
- In 43 of 46 differing pairs, a shown journey is within 5 min of B's first. In 3 of 229 pairs (1.3%), no shown
  journey comes within 5 min of it. Those misses are 12, 22 and 25 min, and in each, B's first is A's 4th.
- "Suggested" is the label the direct options already use for the first option by score.

**What the first release must record** (G2-4 requirements; Gate 3 puts these in `docs/assumptions.md`):
1. **The order is not the shortest estimated duration.** Transfer journeys are ranked by the stop-count score, and
   that order does not necessarily match the shortest E2 estimate. No E2 minutes enter the ranking, and the ranking
   is not changed silently.
2. **The findings, kept as measured** on the pinned input (sample of 2026-11-06, seed 20261106): in 46 of 229 pairs
   the score's first journey differs from E2's fastest; the score's first is slower by p50 3, p90 22 and at most
   35 min (direct options: 7 of 199, at most 13 min).
3. **Estimates stay visible.** Each displayed journey shows its own estimated time (§4.6), so a rider can compare.
4. **The three pairs where no shown journey comes within 5 min of E2's fastest:**

   | Pair (stop codes) | E2's fastest is A's | Fastest shown is slower than it by |
   |---|---|---|
   | 40059 → 22369 | 4th of 4 | 22 min |
   | 01121 → 75581 | 4th of 16 | 12 min |
   | 65329 → 81011 | 4th of 15 | 25 min |

   The 40059 → 22369 detail: A's first is Bus 960 (11 stops) then 502 (34 stops), detour 1.80, 103 min. E2's fastest
   is Bus 48 (15 stops) then 185 (31 stops), detour 1.27, 81 min. The other two are in the benchmark output's
   "largest 8 gaps" (65329 → 81011) or only in the full list (01121 → 75581).
5. **A future ranking enhancement [P], for separate approval and not in E5.** Order the shown transfer journeys by
   an estimate of travel time rather than by stops. Measured option: keep choosing the three by score and order them
   by E2 minutes, which fixes 37 of the 46 differing pairs. A fuller version might add ride distance to the score,
   or rank by E2 minutes outright. Either needs its own decision, because it makes an estimate a routing metric, and
   it should be re-measured with this benchmark. Excluding City Direct services is not recommended: the type is only
   in a further busrouter file (new data under F7), and the cut would apply to direct buses too.

### 2.8 G2-8: redistribution rights of the busrouter snapshot

**Finding [C]: redistribution rights cannot be established. The snapshot was removed from the PR (§12).** Sources,
read 2026-11-06:

| Source | What it says |
|---|---|
| `cheeaun/busrouter-sg` README, "Data" | Bus stops, services and routes are "mostly _scraped_ from https://www.lta.gov.sg/, which means they are copyrighted by the Land Transport Authority" (link to LTA's website terms of use) |
| `cheeaun/busrouter-sg` README, "License" | "Data © LTA © OneMap © OSM contributors. Everything else: MIT". GitHub reports no licence file for the repository |
| `cheeaun/sgbusdata` (the data repository) | No licence (GitHub `license: null`); its README states no terms for the data |
| sgbusdata `scripts/generate-data.js` | `stops.min.json`: code, position and name from lta.gov.sg `bus_stops.xml`, names corrected from SimplyGo's e-guide, road name from DataMall `BusStops`. `services.min.json`: services and stop lists from lta.gov.sg `bus_services.xml` and per-service route files, with missing routes patched from OneMap and Citymapper |
| LTA website terms of use (updated 3 December 2021), "Restrictions on use of content" | "the Contents of this website shall not be reproduced, republished, uploaded, posted, transmitted, communicated or otherwise distributed in any way, without the prior written permission of LTA". No exception is stated for personal or non-commercial use |
| LTA DataMall API terms of service | Datasets served through the API are under the Singapore Open Data Licence. This covers only the road-name field here, and only data obtained through DataMall |

- **Conclusion [C].** Most of each file comes from lta.gov.sg, whose terms require LTA's prior written permission to
  redistribute. Neither busrouter nor sgbusdata grants a licence. Attribution alone does not grant one. So committing
  the files to this public repository is not shown to be permitted.
- **The alternative used (in this PR).** `fetch_snapshot.sh` downloads the two files from `cheeaun/sgbusdata` at the
  pinned commit `a60fe9e` into git-ignored `build/`, and stops unless both SHA-256 hashes match.
  - The files are byte-identical to the measured snapshot, so every figure in §2 still holds. The 2026-11-06 VM and
    Chrome runs from the fetched files reproduced `expected_results.txt`.
  - Reproducibility lasts as long as GitHub serves that commit. The project republishes nothing.
  - `.gitignore` also refuses `tool/e5_transfer_bench/**/*.min.json` and `test/fixtures/busrouter/snapshot-*/`, so
    the files cannot be committed by mistake.
- **The download is optional [D, G2-11].** Whether downloading LTA-derived data for local use is permitted is
  uncertain: LTA's terms ask for written permission to "use the Contents". So the download is not part of CI, not a
  required developer step, and not a Gate 3 pass condition (T8; audit §8).
- **Limits of the alternative [A].**
  - If sgbusdata's history is ever rewritten or removed, the input is lost. A dated local copy kept outside the
    repository by the owner would be the fallback.
  - Asking LTA for written permission is the only route to a committed snapshot.
- **`expected_results.txt` [A].** It now holds only derived facts: counts, stop codes, service numbers, DataMall road
  names, and labels written for the named pairs. It holds no lta.gov.sg stop names. I assess that such short factual
  excerpts are not a reproduction of the site's contents. This is not legal advice.
- **Gate 3 tests.** Because the input is not in the repository, every required test runs on synthetic networks
  (§6). The real-data checks (named fixtures, coverage, the pre-E5 direct baseline of all 199 direct pairs) are the
  optional T8.
- **History [C, G2-10].** The snapshot was committed as `b1715b6` on PR #90's branch `docs/e5-gate2-plan`. That PR is
  closed unmerged and replaced by this one, whose branch was created fresh from `main`, with the final files copied
  and none of PR #90's history.
  - Closing PR #90 does not remove the hosted data: the commit stays reachable through the PR's refs and, while it
    exists, the old branch.
  - Only GitHub Support can purge PR references and cached views. Their guide makes that conditional on rewriting
    history first. Exposure and options: `docs/busrouter-fixture-licensing-audit.md` §7.
- **The existing fixtures [C, G2-11].** `test/fixtures/busrouter/` holds subsets committed since M3 and P2-M2 with the
  same unresolved rights. They are audited separately in `docs/busrouter-fixture-licensing-audit.md`. The app's
  runtime fetch from `data.busrouter.sg` is not redistribution by this project; whether that use needs LTA's
  permission is the audit's decision A-5.

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
| Line under it | `These routes change buses once, at the same stop. Times exclude waiting for both buses.` |
| Option summary | `Bus 88, then Bus 851e` (each service in its badge) |
| Trip line (when both rides have an estimate) | `About 50 min · excl. waiting for both buses` |
| Trip semantics | `Estimated trip, about 50 minutes, not including waiting for either bus` |
| Step 1 | `~3 min walk (est.) to Bus Stop 52009 — Toa Payoh Int` (today's wording) |
| Step 2 | `Bus 88 toward <towardName> · 12 stops` + the E2 ride detail `· ~20 min ride (est.)` |
| Step 3 | `Change at Bus Stop 54011 — <name>: board Bus 851e at the same stop. Waiting time not included.` |
| Step 4 | `Bus 851e toward <towardName> · 10 stops` + ride detail |
| Step 5 | `Alight at 59009 — Yishun Int` |
| Step 6 | `~2 min walk (est.) to destination` |
| Under the options, instead of the arrivals footer | `Live arrival times are not available for these transfer suggestions.` (owner's wording, G2-7) |
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

**T2. Planner**: synthetic networks only (`transfer_planner_test.dart`, pure Dart, also run on Chrome in CI). Real
busrouter data is not in the repository (§2.8), so the real-data checks are T8:
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
- T2.14 property check over a seeded synthetic network (generated in the test, a few hundred stops and services):
  every journey obeys T1 and the F1 rules.

**T3. Providers** (`journey_providers_test.dart`):
- T3.1 a direct pair returns `planDirectBus`'s result, and the transfer index is never built (spy repository);
- T3.2 regression: on the T2.14 synthetic network, at least 50 pairs with a direct bus give, through the provider,
  plans equal to `planDirectBus` (options, order, scores), with no index built. On real data, T8's direct baseline
  covers the same;
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

**T8. Benchmark (optional; real data; never CI and never a pass condition for Gate 3, §2.8):** run only if the owner
permits the download (audit decision A-5). After `fetch_snapshot.sh`, `tool/e5_transfer_bench` runs `planOneTransfer`.
What a run checks:
- the same-stop rows and the named fixtures equal `expected_results.txt`, so the sample serves exactly 229 of 301;
- the "Direct plans (pre-E5 baseline)" section, all 199 direct pairs, is unchanged;
- each difference is explained;
- the timings are recorded against §2.4.

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
4. Optional, only if the owner permits the download (T8): the benchmark, VM and Chrome, three runs each, with results
   equal to `expected_results.txt` and timings against §2.4. Otherwise it is logged **Not run**, with that reason.
5. A Web live check of a release build with live busrouter data: one named fixture, its card and its map.
6. Not expected to run: TalkBack or a screen reader, and a physical phone. They are logged **Not run** unless they are
   actually done.
7. An independent review against this plan and pre-E5 `main`.

## 9. Commit boundaries (branch `feat/e5-one-transfer`, only after this plan is approved and merged)

1. `test(e5): leg invariants` (RED) → `feat(e5): ordered journey legs` (GREEN)
2. `test(e5): one-transfer planner rules` (RED) → `feat(e5): one-transfer planner` (GREEN)
3. `test(e5): synthetic-network properties and direct regression` → GREEN; `tool(e5): benchmark runs the real planner`
4. `test(e5): transfers only without a direct bus` (RED) → `feat(e5): plan transfers when no direct bus` (GREEN)
5. `test(e5): transfer journey card` (RED) → `feat(e5): leg-list journey card` (GREEN)
6. `test(e5): two-ride map` (RED) → `feat(e5): map a transfer journey` (GREEN)
7. `test(e5): integration` → GREEN; `ci: run the transfer planner on Chrome`
8. Mutation runs (not merged), then `docs(e5): run log, assumptions, ADR, CLAUDE.md`

## 10. Rollback

E5 is merged as one merge commit. Rollback is `git revert -m 1 <merge>` through a PR. Nothing is stored on the device,
and there is no data migration, new host or new dependency, so nothing else needs undoing. The benchmark can
stay.

## 11. Risks and stop conditions

| Risk | Tag | Mitigation or stop |
|---|---|---|
| A direct-bus result changes | C (F3 requires none) | T3.2, T6.2 and T8's direct baseline. **Stop** if any direct pair differs |
| The card grows too complex at 2× text | A | T5.7. Stop and report if the leg list cannot fit without dropping information |
| Phone performance is far below the PC | A | Targets kept with an 8–9× margin in Chrome. Measure on Android if a device is available; otherwise Not run |
| Express, limited or City Direct services shown when not running, and ranked first by stop count (§2.7) | C (existing limit, larger for transfers) | Wording claims no operating time; each option shows its estimate; recorded in `assumptions.md` |
| busrouter data drifts | C | The benchmark input is pinned by commit and hash; the live check uses live data; the parser's validation is unchanged |
| New findings change the design | A | Stop and report (a Gate 1 report then, G0-1) |

## 12. Decisions

### 12.1 Owner rulings [D]

First round, 2026-11-06:

| ID | Ruling |
|---|---|
| G2-1 | Detour limit **2.5** |
| G2-2 | **Same-stop** transfers only for E5 |
| G2-3 | Keep the §10.4 targets; add a cold first search under 100 ms in Chrome |
| G2-5 | Up to three transfer journeys |
| G2-6 | No live-arrival requests for transfer journeys in E5 |
| G2-7 | UI, map, accessibility and failure handling approved. Live-arrival line: "Live arrival times are not available for these transfer suggestions." The card must say clearly that durations exclude waiting for both buses (both in §4.6) |
| G2-9 | Benchmark code accepted as a required feasibility artifact, kept apart from production code; the snapshot only with confirmed rights (it was removed) |

Second round, 2026-11-06:

| ID | Ruling |
|---|---|
| G2-0 | **Conditionally approved:** ordered `WalkLeg`/`BusLeg`, the direct planner preserved, same stop only, limit 2.5, up to three suggestions, no transfer live arrivals, the "waiting for both buses" disclosure, and the performance, accessibility and regression requirements. Gate 3 authorization waits on this replacement PR being merged and on the fixture-licensing assessment |
| G2-4 | **Keep the score order** for E5; no E2 minutes in the ranking. The five requirements are in §2.7 |
| G2-8 | Remove the possibly restricted data from the repository (done) |
| G2-10 | **Replace PR #90:** close it unmerged, then open a fresh branch from `main` with only the final files and no old history; check that no snapshot blob is in the new history, and that ignore rules guard against it; record the historical exposure (§2.8; audit §7) |
| G2-11 | **Separate licensing audit** of the existing busrouter fixtures: `docs/busrouter-fixture-licensing-audit.md`. No history deletion or rewrite, and no third-party contact, without explicit approval. The benchmark download stays optional unless its use is shown to be permitted |

### 12.2 Remaining decisions

Before Gate 3:
- this PR's review and merge;
- the audit's decisions A-1 to A-5 (`docs/busrouter-fixture-licensing-audit.md` §9). A-1, replacing the fixtures with
  synthetic ones, and A-5, LTA permission for the runtime use and the optional download, are the ones that bear on E5.

No other E5 design decision is open.

## 13. Out of scope

Everything §3 excludes, issue #82 and the repository secret, and every gate after E5 (master plan §11: rail and
multimodal feasibility each need separate approval).
