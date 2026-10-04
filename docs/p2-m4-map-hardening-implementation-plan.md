# P2-M4 Map Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for
> tracking.

**Goal:** close Phase 2. The map gets reduced-motion support for its gestures. The walking-router question is
closed with recorded primary-source evidence. The remaining hardening checks from `docs/map-feasibility.md` §10
item 4 run and are recorded:
- the Android tile cache and `max-age`;
- HD tiles;
- the OneMap terms;
- emulator performance;
- TalkBack;
- the final gates, deterministic integration runs and live smoke.

The planner, the journey card, arrivals, the MRT suggestion, the map's scene and camera, and the P2-M3 straight
walking connectors stay exactly as they are.

**Architecture:**
- **One code change, in one widget.**
  - `JourneyMap` (`lib/features/map/presentation/journey_map.dart`) passes flutter_map one of two constant
    `InteractionOptions`, chosen by `MediaQuery.maybeDisableAnimationsOf(context)`. This is the same signal
    `MotionSize` (`lib/core/ui/motion.dart`) already uses.
  - With reduce motion on: no `flingAnimation` flag and `doubleTapZoomDuration: Duration.zero`.
  - Otherwise: today's options, unchanged.
  - Nothing else in `lib/` changes.
- **A dev-only probe for the performance numbers.** `tool/map_performance_probe.dart` is run with
  `flutter drive --profile` on the emulator.
  - It reuses the integration fakes for the journey, and the app's real `OneMapTileProvider` for live tiles.
  - It is not a gate, `flutter test` never runs it, and it is not under `integration_test/`, whose files never
    call live APIs.
- **Everything else is verification and documentation.** No new dependency, provider host, CSP entry, HTTP
  behaviour, credential or network request is added to the app.

**Tech stack:**
- Flutter 3.47.2 / Dart 3.13.2, Riverpod 3, flutter_map 8.3.2.
- `package:integration_test` (`IntegrationTestWidgetsFlutterBinding`) and `package:flutter_test`
  (`FrameTimingSummarizer`, `FakeAccessibilityFeatures`) are both already dev dependencies.
- **No new dependencies.**

**Spec / authoritative context:**
- guide v2.1:
  - §9.3: walking estimate;
  - §17: Phase 2 map, including "Walking-route geometry **only** if … Otherwise keep straight-line 'est.'
    connectors";
  - §19: quality gates;
  - §21: milestones;
  - §26: design principle.
- `docs/map-feasibility.md`:
  - §4.1 and §4.2: OneMap terms, HD tiles and the reasonable-use rules, especially rules 4 and 7;
  - §6: walking routers;
  - §8: caching;
  - §9: risks M7, M9 and M10;
  - §10 item 4: **P2-M4 — Hardening**;
  - §11 item 3.
- `docs/architecture.md`: the Phase 2 Milestone 1–3 sections and ADR-001.
- `docs/assumptions.md`: the map rows, "Walking estimate" and "Motion".
- `docs/p2-m2-bus-geometry-implementation-plan.md` and `docs/p2-m3-map-option-sync-implementation-plan.md`.
- `CLAUDE.md`.
- The P2-M4 discovery report, and the user's decisions D1–D8, Q1–Q4 and R of 2026-10-04 (below; all frozen).

Baseline: `main` at `2c415e52fdaa1d0609ded1ee7c33c9405112d635` (the P2-M3 merge, PR #44).

**Decision numbers.** D1–D8, Q1–Q4 and R here are P2-M4's own (the user's decisions of 2026-10-04). They are not
P2-M2's D1–D6 or P2-M3's D1–D9.

---

## Global Constraints

- **Front end only** (ADR-001):
  - no server-side component, proxy, Worker or serverless function;
  - no credentials or secrets;
  - no `.env`, `--dart-define` or asset secrets.
- **No walking routing** (D2):
  - no router of any kind, no routing host and no CSP entry for one;
  - no new HTTP behaviour (no custom User-Agent, no new client);
  - no coordinate disclosure;
  - `MapScene.walks` stays the straight connectors derived from the markers;
  - `WalkEstimate` stays the only walking time and is shown only in the journey card.
- **The planner is authoritative.** No change to `planDirectBus`, scoring, ranking, `WalkEstimate`, arrivals or the
  MRT lookup.
- **P2-M1–M3 invariants unchanged:**
  - the map is closed by default, and no tile is requested before "Show map";
  - the camera stays inside OneMap's bounds and z11–19;
  - the camera is fitted once per scene change, **never animated**;
  - no prefetch and no automatic tile retry;
  - the persistent OneMap attribution;
  - the bus line is all-or-nothing;
  - `routes.min.json` is lazy, held for the session, and retried only by "Show map";
  - one journey-owned selection tied to the identical plan object;
  - MRT stays informational;
  - `features/journey` never imports `features/map`;
  - `flutter_map` and `latlong2` are imported only in `features/map/presentation/` (plus the dev probe in `tool/`).
- **Reduced motion (D3)** removes only flutter_map's fling glide and the double-tap zoom animation. Every gesture
  that works today keeps working: drag, pinch zoom and move, double-tap zoom, double-tap-drag zoom, scroll-wheel
  zoom, and the keyboard. Rotation stays off as before. Keyboard animations keep Flutter's own reduced-animation
  behaviour (Q2).
- **Performance (D4):** measure and report on the emulator. **No pass/fail threshold** is set, and the numbers are
  never presented as physical-device performance.
- **HD tiles (D5): no.** No HD mode is added.
- **TalkBack (D6):**
  - one attempt;
  - restore the settings;
  - if blocked, record **Not run** with the exact reason;
  - existing a11y tests are never weakened.
- **Tests never call live APIs.** The dev probe in `tool/` calls live OneMap tiles only, for a visible map, within
  §4.2's reasonable-use rules.
- **Evidence rule:**
  - every gate and check is logged in `docs/testing.md` with its real command and result;
  - anything not run is logged as **Not run** with the reason;
  - `flutter test --platform chrome` stays **Not run** (the flutter_tools Windows path bugs logged on 2026-10-03).
    Don't retry it unless the toolchain or OS has materially changed since; P2-M4 adds no Web-specific
    arithmetic.
- **Tunables:** none new. The two `InteractionOptions` are flutter_map behaviour, not tunable values. They are
  recorded in `docs/assumptions.md`.
- **Git:**
  - two PRs (D7);
  - feature branches only;
  - never commit or push to `main`;
  - no force-push or history rewrite;
  - check `git branch --show-current` before every commit (something outside the session once switched the main
    checkout to `main`).
- **Processes:** ask the user before stopping processes, killing the emulator or rebooting it (project
  practice).
- **Out of scope:**
  - walking routing;
  - routed walking times, rescoring or re-ranking;
  - an HD tile mode;
  - map-based planning, transfers or live vehicles;
  - any new map feature;
  - the `docs/simplification-plan.md` refactor;
  - UI polish (a separate stream; D8);
  - an iOS-specific `reduceMotion` reading (the app targets Android and Web only).

## Review Focus

The five failure modes most likely to bite a real user that no other task's tests catch. Each has a test or a
check in the task that owns it.

1. **A user with "Remove animations" on (Android) or `prefers-reduced-motion` (Web) swipes the map.**
   - Today the framework plays a fling 200× faster under that setting (`AnimationController.fling`), so the map
     *jumps* on release by up to its shorter side.
   - Expected: it stops where the finger lifts.
   - Pinned by Task 2, test B.
2. **The same user double-taps to zoom.** Expected: the zoom lands at once, in the same frame. Pinned by Task 2,
   test B.
3. **Reduce motion must not make the map stiff.** Expected: drag, pinch, double-tap, double-tap-drag and
   scroll-wheel zoom all still work. Pinned by Task 2, tests A (flags) and B (the drag moves the map).
4. **The setting changes while the map is open** (Q1).
   - Expected: the camera stays where the user panned it (no rebuild or refit), the next swipe has no glide, and
     the journey stays drawn (line, connectors, MRT pins) with no extra `routes.min.json` load.
   - Pinned by Task 2, test D.
5. **The docs must not promise a router.** Expected: nothing in the current docs still describes `routed-foot` as
   pending or optional, or Valhalla as "development and testing only". Checked by Task 1, step 6: a grep whose only
   allowed matches are the plan documents and §6's corrected history.

---

## Current-state findings (merged code at `2c415e5`)

- **`journey_map.dart:191-193`** passes
  `interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)`.
  - No reduced-motion handling, so flutter_map's defaults apply: fling on, double-tap zoom 200 ms.
  - The camera fit (`_fittedCamera` before the first frame, then `_controller.fitCamera` in `_fitLatest`) is
    never animated.
- **flutter_map 8.3.2:**
  - It never reads `MediaQuery.disableAnimations`.
  - It reads `interactionOptions.flags` on every gesture (`map_interactive_viewer.dart:794`, `hasFlingAnimation`).
  - But it creates `_doubleTapController` once, with the duration of the options at that moment
    (`late final`, `:90-93`).
  - Its scroll-wheel zoom is not animated (`moveRaw`).
  - Keyboard pan and zoom use their own `AnimationController`s.
- **The framework, under `disableAnimations`** (`animation_controller.dart:651`, `:785`):
  - `AnimationController` plays a timed animation at 5 % of its duration, so flutter_map's 200 ms double-tap
    becomes 10 ms (one frame) and the keyboard animations shrink too;
  - it multiplies a **fling's velocity by 200**, so under reduce motion today a fling makes the map jump on
    release.
  - Hence D3's real user-facing fix is the fling. The explicit `Duration.zero` makes the double-tap exact rather
    than one frame late.
- **The platforms report the setting:**
  - Android sets `disableAnimations` when `Settings.Global.TRANSITION_ANIMATION_SCALE` is 0 ("Remove animations"),
    watched live (`AccessibilityBridge.java:585-591`);
  - Web sets both `disableAnimations` and `reduceMotion` from `prefers-reduced-motion`, live
    (`web_ui/.../platform_dispatcher.dart:1284-1308`);
  - `MotionSize` already relies on this, and the UI-polish live check saw it in Chrome (run log, 2026-10-02).
- **Tile cache.**
  - `OneMapTileProvider` (`basemap.dart`) uses `BuiltInMapCachingProvider.getOrCreateInstance(maxCacheSize:
    MapConfig.tileCacheMaxBytes)` (50 MB, P2-M1) with no `overrideFreshAge`.
  - flutter_map computes freshness from `Cache-Control: max-age`, minus `Age` (or minus the age estimated from
    `Date`), in `tile_metadata.dart:50-79`.
  - A fresh tile is served from the cache with no request (`image_provider.dart:213`). A stale one is revalidated
    with `If-Modified-Since` / `If-None-Match`, and a 304 reuses it.
  - OneMap sent `Cache-Control: max-age=14400, s-maxage=14400, must-revalidate` on 2026-10-04.
- **HD tiles** (probed 2026-10-04 02:52 UTC): `Default_HD/16/51673/32534.png` is 256 × 256 with
  `Content-Type: image/undefined`, the same as P2-M0. The standard `Default` tile is 256 × 256 `image/png`.
- **Walking routers** (discovery, 2026-10-04 02:48–02:53 UTC):
  - FOSSGIS terms reachable;
  - `routed-foot` 200 with `ACAO: *`, 852.5 m / 685.9 s;
  - OSRM demo `/foot/` returns a car route of 1,206.8 m;
  - OneMap routing 401;
  - BRouter has no usage policy;
  - details are in Task 1.
- **OneMap terms re-check (§4.2 rule 7):** the run log records one only for P2-M0 (2026-10-03 02:06–02:08 UTC).
  There is none for P2-M1, P2-M2 or P2-M3.
- **Map accessibility today:**
  - one `Semantics(container, label: scene.summary)` over `ExcludeSemantics`;
  - live-region notes;
  - linked attribution;
  - tests: `journey_map_card_test.dart:414` ("the map is one summary for screen readers") and
    `journey_widget_test.dart:693-703` ("Select Bus N", "Bus N selected");
  - Web semantics labels checked live in P2-M3;
  - the TalkBack pass was **Not run** in P2-M1, P2-M2 and P2-M3.
- **Stale docs:**
  - `README.md` status ("Milestone 5 (hardening)") and roadmap ("→ Phase 2 map");
  - `docs/map-feasibility.md` §1, §6, §7, §9 (M9), §10 item 4 and §11 item 3 still describe `routed-foot` as a
    possible P2-M4 experiment;
  - §6 and `docs/data-sources.md` call Valhalla "development and testing only", which the primary terms don't
    say.

## Decisions (frozen 2026-10-04, from the user)

- **D1 — Scope.** P2-M4 is the Phase 2 Hardening milestone of `docs/map-feasibility.md` §10 item 4, not a
  walking-routing milestone.
- **D2 — Walking routing: KEEP ESTIMATES.**
  - Integrate no router.
  - The P2-M3 connectors are final for Phase 2.
  - Record the investigation (Task 1) and correct the Valhalla documentation.
- **D3 — Reduced motion:**
  - when the OS requests it, no fling and an instant double-tap zoom;
  - otherwise flutter_map's behaviour is unchanged;
  - the camera fitting is unchanged;
  - test first;
  - no gesture is disabled beyond the fling.
- **D4 — Performance:**
  - measure on the Android emulator in a profile build, with bus geometry, connectors, MRT pins, light and dark
    mode, and panning;
  - report the numbers, with no threshold, as emulator evidence only;
  - investigate an obvious serious regression instead of only recording it.
- **D5 — HD tiles: NO.** Record the fresh probe and keep the current tiles.
- **D6 — TalkBack:** one attempt. If the setup prompt blocks it:
  - stop and restore the settings;
  - record **Not run** with the reason;
  - cite the widget-test and Web semantics evidence.
- **D7 — Two PRs:**
  1. this plan (docs only);
  2. the implementation, after the plan is reviewed and merged.
- **D8 — Phase 2 close-out.** If implementation, verification and the final gates succeed:
  - mark Phase 2 closed in the roadmap and status docs, including the README;
  - don't call the whole project finished (UI polish continues separately).

The user also approved this plan with these follow-up decisions (2026-10-04). They are frozen too.

- **Q1 — Reduce motion switched on while the map is open: as designed, not a defect.**
  - Don't rebuild `FlutterMap` just to turn an already-created double-tap duration into exactly zero. Keep the
    camera, pan and zoom, and don't refit the scene because an accessibility setting changed.
  - The next swipe has no fling, because flutter_map reads the flags on every gesture. The double-tap zoom keeps
    Flutter's reduced timing (about 10 ms, one frame) until the map is next opened.
  - A map created while reduce motion is on uses zero.
  - Task 2, test D pins this behaviour, and the assumptions row documents it as designed.
- **Q2 — Keyboard pan and zoom: unchanged.** Flutter's and flutter_map's existing reduced-animation behaviour
  stays. There is no keyboard customisation and no keyboard-navigation framework, unless implementation testing
  finds a concrete accessibility defect (then stop and report).
- **Q3 — Performance probe: approved** as a dev-only tool in `tool/`, with a deterministic fake journey and the
  intended live OneMap tiles.
  - Record: build mode, emulator/device details, cold/warm cache, light/dark, the scenario, p90/p95/p99, the worst
    frame time, and the jank count and share (missed-budget frames out of all frames).
  - No pass threshold, and no claim that the numbers represent a low-end physical device.
  - If the numbers show an obviously severe regression, stop and report before attempting any optimisation.
- **Q4 — Gesture live checks are supplementary.** The widget tests are the deterministic acceptance evidence for
  reduced motion. If WebDriver or adb can't reliably reproduce a fling or a double-tap, record that live check as
  **Not run (not reproducible)** with the reason, never as invented evidence.
- **R — Router re-probe kept to what the decision needs** (Task 1).
  - Live: FOSSGIS `routed-foot` (GET and CORS preflight), the FOSSGIS terms and the routing about page. The terms
    are the evidence that corrects the Valhalla statement, since they name `valhalla1.openstreetmap.de`, so
    Valhalla itself needs no request.
  - No new requests to the structurally excluded providers: the OSRM demo (guide §17), OneMap routing (token),
    BRouter (no policy) and the keyed routers. Their exclusion rests on their documentation and on the discovery
    run-log row (Task 0).

## What kind of work each item is

| Kind | Items |
|---|---|
| **Code changes, definitely required** | `lib/features/map/presentation/journey_map.dart`: the reduced-motion `InteractionOptions` (Task 2). `test/features/map/journey_map_card_test.dart`: four tests (Task 2). `tool/map_performance_probe.dart`: new, dev-only (Task 6; not app code) |
| **Verification only** | Tile cache and `max-age` (Task 3); HD probe (Task 4); OneMap terms (Task 5); performance runs (Task 6); TalkBack (Task 7); gates, integration runs and live smoke (Task 8) |
| **Documentation corrections** | Valhalla rows (`map-feasibility.md` §6, `data-sources.md`); stale P2-M4 `routed-foot` wording (`map-feasibility.md` §1, §6, §7, §9 M9, §10, §11); "Real walking routing could improve this in Phase 2" (`assumptions.md` "Walking estimate"); README status and roadmap; the rule-7 gap for P2-M1–M3 recorded honestly (`map-feasibility.md` §4.2) |
| **Documentation additions** | `map-feasibility.md` §6.1 (the decision record); `docs/probe-output/walking-routers-p2m4.txt`; `assumptions.md` row "Map gestures and reduced motion (P2-M4)"; `architecture.md` "Phase 2 Milestone 4"; `CLAUDE.md` Map paragraph; `testing.md` run-log rows and Phase 2 status |
| **Conditional: only if a check shows a real problem** | Task 3: the cache doesn't serve fresh tiles, or ignores `max-age`. Task 5: OneMap's terms changed in a way that affects the map. Task 6: an obvious serious regression. Task 8: a gate or live check fails. Each one stops for diagnosis (superpowers:systematic-debugging) and **reports to the user before any fix that changes tile loading, network behaviour or scope** |

## Already done in P2-M1–M3 (not repeated, only re-verified where marked)

| §10 item 4 / P2-M4 note | Status before P2-M4 | P2-M4 action |
|---|---|---|
| Android tile cache cap | Done in P2-M1 (`MapConfig.tileCacheMaxBytes` = 50 MB) | Only verify `max-age` (Task 3). No change to the cap |
| Accessibility semantics | Done P2-M1–M3 (summary label, live-region notes, links, Select semantics; widget tests) | TalkBack attempt (Task 7). Final regression in Task 8 |
| No animated camera | Done in P2-M1 (fit without animation) | Unchanged. Task 2 adds only gesture motion |
| Web drive + Android integration with fake tiles | Done in each of P2-M1–M3 (three files, 0 CSP violations) | Final regression run only (Task 8). No integration test changes |
| Live smoke: light, dark, 360 dp, 2× text | Done in P2-M3 (Web and Android) | Final regression run only (Task 8) |
| Ride line, connectors, MRT pins, option sync, legend | Done in P2-M2 / P2-M3 | Unchanged. Exercised by the probe (Task 6) and live smoke (Task 8) |

---

## File-by-file change list (implementation PR)

| File | Change | Task |
|---|---|---|
| `lib/features/map/presentation/journey_map.dart` | Two `static const InteractionOptions`; pick by `MediaQuery.maybeDisableAnimationsOf`; class doc comment | 2 |
| `test/features/map/journey_map_card_test.dart` | New group "reduced motion (P2-M4)", 4 tests | 2 |
| `tool/map_performance_probe.dart` | New dev-only probe | 6 |
| `docs/map-feasibility.md` | §1 row, §4.1 (HD), §4.2 rules 4 and 7, §6 table + new §6.1, §7, §8, §9 (M7, M9), §10 item 4, §11 item 3 | 1, 3, 4, 5, 6, 9 |
| `docs/data-sources.md` | "Excluded": walking-router lines corrected | 1 |
| `docs/assumptions.md` | "Walking estimate", "Walking connectors and legend (P2-M3)", "Map tiles: reasonable use" rows; new row "Map gestures and reduced motion (P2-M4)" | 1, 2, 3, 4 |
| `docs/probe-output/walking-routers-p2m4.txt` | New: the re-check output | 1 |
| `docs/architecture.md` | P2-M3 "Not in P2-M3" line (:317) points to §6.1; new "Phase 2 Milestone 4 (hardening) and Phase 2 close-out" section; `tool/map_performance_probe.dart` in "Dev tools" | 1, 9 |
| `docs/testing.md` | Run-log rows; "Feasibility probes" (the perf probe); "Open acceptance items" (Phase 2 status) | 1, 3–9 |
| `CLAUDE.md` | Map paragraph (reduced motion; no walking router); Project paragraph (Phase 2 closed) | 2, 9 |
| `README.md` | Status, known limitations (map), roadmap | 9 |

Not changed: the guide (it is the spec), the P2-M2 and P2-M3 plan documents (history), `tool/probe_map.sh` and
`docs/probe-output/map-probes.txt` (P2-M0 evidence), `web/index.html` and the CSP test, `pubspec.*`,
`integration_test/`.

## Interfaces

- **Produced (Task 2), private to `journey_map.dart`:**
  - `static const InteractionOptions _interaction` — today's options, unchanged;
  - `static const InteractionOptions _reducedMotionInteraction` — no fling, `doubleTapZoomDuration:
    Duration.zero`.
  - No public API changes; `JourneyMap`'s constructor is unchanged.
- **Consumed (Task 6):**
  - `buildTestApp(...)` (`integration_test/fakes/test_app.dart`, unchanged);
  - `OneMapTileProvider.new` (`basemap.dart`, unchanged);
  - `initIntegrationTest`, `pumpUntilFound`, `searchAndPick`, `scrollToAndTap` (`integration_test/support.dart`);
  - `FrameTimingSummarizer` (`package:flutter_test`).
- **Test helpers (Task 2), local to the new group:** `camera`, `gestures`, `setReduceMotion`, `openJourneyMap`,
  `doubleTapMap`, `swipeMap`. The file's existing `pumpApp`, `pickDestination`, `openMap`, `marker` and `app()`
  are reused.

---

## Tasks

### Task 0: The plan PR (D7, PR 1; docs only)

**Files:**
- Create: `docs/p2-m4-map-hardening-implementation-plan.md` (this document)
- Modify: `docs/testing.md` (one run-log row)

- [ ] **Step 1: Branch.**
  - `git fetch origin`
  - `git switch -c docs/p2-m4-map-hardening-plan origin/main`
  - Check `git branch --show-current`.
- [ ] **Step 2: Add the plan** at `docs/p2-m4-map-hardening-implementation-plan.md`.
- [ ] **Step 3: Record the discovery evidence.** Append this row to the `docs/testing.md` run log:

  ```markdown
  | 2026-10-04 | P2-M4 discovery and planning (branch `docs/p2-m4-map-hardening-plan` from `2c415e5`; adds `docs/p2-m4-map-hardening-implementation-plan.md`, no code change). Read-only investigation of the P2-M4 scope and the walking-router question; the user's decisions (D1–D8, Q1–Q4, R; all frozen) are in the plan | `curl` with an identifying User-Agent, one request per endpoint, ≥ 1 s apart (02:48–02:53 UTC): FOSSGIS terms `https://www.fossgis.de/arbeitsgruppen/osm-server/nutzungsbedingungen/`, `https://routing.openstreetmap.de/about.html`, the OSRM demo-server wiki (`raw.githubusercontent.com/wiki/Project-OSRM/osrm-backend/Demo-server.md`), `brouter.de` and `brouter.de/brouter-web/`; `routed-foot` GET and an OPTIONS preflight, OSRM demo `/foot/`, OneMap routing without a token (Raffles Place MRT 103.8515,1.2840 → Fullerton Hotel 103.8531,1.2862); OneMap `Default` and `Default_HD` tile z16/51673/32534; a web search for keyless walking routers | FOSSGIS terms 200 (`Last-Modified` 2026-10-03 07:51:28 GMT; German and English). One set of terms covers `routing.openstreetmap.de` and `valhalla1.openstreetmap.de`, with no development/testing-only clause. It says: primary purpose their website and OSM contributors; URLs "should not be hardcoded into the app" (explicitly recommended); an operator email on the website / app-store entries; an identifying User-Agent ("User agents of libraries are not sufficient"); ≤ 1 request/s; high-traffic websites not permitted; attribution plus a fix-the-map link; revocable; one server, no guarantee. About page 200 (requests are logged). OSRM wiki 200 ("reasonable, non-commercial use-cases", ≤ 1 req/s). `routed-foot` 200, `Access-Control-Allow-Origin: *`, precision-5 polyline, 709 B, 852.5 m / 685.9 s (the same as P2-M0); preflight 200 (`GET`; `X-Requested-With, Content-Type`). OSRM demo `/foot/` 200 but a car route, 1,206.8 m / 124 s. OneMap routing 401 `{"message":"Unauthorized"}`. BRouter: only a privacy-policy link, no usage policy. `Default` 256 × 256 `image/png`, `Cache-Control: max-age=14400, s-maxage=14400, must-revalidate`; `Default_HD` 256 × 256, `Content-Type: image/undefined`. The search found no new keyless walking router. Repository unchanged during discovery (`git status` clean at `2c415e5`). **Not run:** builds and integration tests (docs-only change) |
  ```

- [ ] **Step 4: Sanity gates.**
  - `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test`. All must pass.
  - Add their actual results to the same row, just before its **Not run** sentence: files changed, issues, the
    passed/total count, and the exit codes.
- [ ] **Step 5: Commit, push, open the PR. Don't merge.**
  - `git add docs/p2-m4-map-hardening-implementation-plan.md docs/testing.md`
  - `git commit -m "docs(p2-m4): map hardening implementation plan"`, ending with the attribution lines.
  - `git push -u origin docs/p2-m4-map-hardening-plan`
  - `gh pr create --base main` with a body that summarises D1–D8, Q1–Q4, R and the task list.
- [ ] **Step 6: Stop** until the user has reviewed and merged the plan PR.

### Task 1: Close the walking-router question; correct the Valhalla docs (D2)

Docs only. It starts the implementation PR.

**Files:**
- Create: `docs/probe-output/walking-routers-p2m4.txt`
- Modify: `docs/map-feasibility.md` (§1 table row "Walking geometry", §6, new §6.1, §7, §9 M9, §10 item 4's last
  bullet, §11 item 3)
- Modify: `docs/data-sources.md` ("Excluded")
- Modify: `docs/assumptions.md` ("Walking estimate", "Walking connectors and legend (P2-M3)")
- Modify: `docs/architecture.md` (one line in the P2-M3 section, :317)
- Modify: `docs/testing.md` (run log)

- [ ] **Step 0: Branch** (after the plan PR is merged).
  - `git fetch origin`
  - `git switch -c feat/p2-m4-map-hardening origin/main`
  - Check `git branch --show-current`.
- [ ] **Step 1: Re-check what the decision rests on** (decision R) and save the output. It makes four requests,
  2 s apart, and writes **nothing** to the app:
  - FOSSGIS `routed-foot` (GET and CORS preflight);
  - the FOSSGIS terms, which also cover Valhalla;
  - the routing about page.

  The OSRM demo, OneMap routing, BRouter and the keyed routers are not requested again. Their exclusion rests on
  the Task 0 discovery row and their documentation. Run from the repo root in Git Bash:

  ```bash
  UA="sg-smart-commute-p2m4-probe (university course project)"
  A="103.8515,1.2840"; B="103.8531,1.2862"   # Raffles Place MRT -> Fullerton Hotel, about 300 m apart
  T=$(mktemp -d)
  hdr() { tr -d '\r' | grep -iE '^HTTP/|^access-control-allow-|^content-type|^cache-control|^last-modified' | sort -u; }
  get() { # name url [extra curl args...]
    local name="$1" url="$2"; shift 2
    echo "=== $name"; echo "GET $url"
    curl -s -m 20 -D - -o "$T/body" -A "$UA" -H "Origin: https://example.com" "$@" "$url" | hdr
    echo "bytes: $(wc -c < "$T/body")"; echo "body: $(head -c 300 "$T/body" | tr '\n' ' ')"; echo
    sleep 2
  }
  {
    echo "# P2-M4 walking-router re-check: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# Four requests, 2 s apart: only what the P2-M4 decision rests on (decision R)."
    echo "# Decision and reasons: docs/map-feasibility.md §6.1. The OSRM demo, OneMap routing and BRouter"
    echo "# results are from the 2026-10-04 discovery (docs/testing.md run log), not re-requested."
    echo
    get "FOSSGIS OSRM routed-foot" "https://routing.openstreetmap.de/routed-foot/route/v1/foot/$A;$B?overview=full&geometries=polyline"
    echo "=== FOSSGIS OSRM routed-foot, CORS preflight"
    curl -s -m 20 -X OPTIONS -D - -o /dev/null -A "$UA" -H "Origin: https://example.com" \
      -H "Access-Control-Request-Method: GET" "https://routing.openstreetmap.de/routed-foot/route/v1/foot/$A;$B" | hdr
    echo; sleep 2
    echo "=== FOSSGIS terms, covering routing.openstreetmap.de and valhalla1.openstreetmap.de"
    echo "    (https://www.fossgis.de/arbeitsgruppen/osm-server/nutzungsbedingungen/)"
    curl -s -m 20 -D - -o "$T/terms.html" -A "$UA" https://www.fossgis.de/arbeitsgruppen/osm-server/nutzungsbedingungen/ | hdr
    python - "$T/terms.html" <<'EOF'
  import hashlib, html, re, sys
  t = open(sys.argv[1], encoding='utf-8', errors='replace').read()
  t = re.sub(r'(?is)<(script|style).*?</\1>', '', t)
  t = re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', t)))
  print('extracted text sha256:', hashlib.sha256(t.encode()).hexdigest())
  for clause in [
      'primary purpose is to support usage on our website',
      'should not be hardcoded into the app',
      'an email address of the operator must be easily identifiable',
      'User agents of libraries are not sufficient',
      'Websites with high traffic volumes are generally not permitted',
      'Maximum one request per second',
      'routing.openstreetmap.de, valhalla1.openstreetmap.de',
      'may be revoked by us at any time',
      'development and testing',
      'testing only',
  ]:
      print(f'{clause!r}: {"present" if clause in t else "absent"}')
  EOF
    echo; sleep 2
    echo "=== routing.openstreetmap.de/about.html (request logging)"
    curl -s -m 20 -A "$UA" https://routing.openstreetmap.de/about.html | grep -o -i 'saved[^<]\{0,60\}log file'
  } > docs/probe-output/walking-routers-p2m4.txt
  rm -rf "$T"
  ```

  Expected (as in discovery):
  - `routed-foot`: 200, `access-control-allow-origin: *`, a body starting `{"code":"Ok"`;
  - the preflight: 200, allowing `GET`;
  - the terms clauses: the first eight `present` (the seventh names Valhalla's host), and `'development and testing'`
    and `'testing only'` `absent`;
  - about page: `saved in the server log file`.

  **If the results differ materially** (the terms now explicitly allow third-party app traffic, the clauses
  changed, or the service is gone): **stop and report to the user** before writing §6.1. D2 was decided on these
  facts.
- [ ] **Step 2: `docs/map-feasibility.md` §6.**
  - In the table, replace the FOSSGIS Valhalla row's policy and verdict cells with:
    - policy: "Same FOSSGIS terms as `routed-foot` (primary source, read 2026-10-04). The P2-M0 wording
      'development and testing only' came from a secondary source and is **not** in the primary terms";
    - verdict: "Not adopted (§6.1). It would also need a precision-6 decoder".
  - Replace the `routed-foot` row's verdict "**Only candidate.** Off by default (below)" with "Not adopted (§6.1)".
  - In the "**Conclusion.**" list, replace "Valhalla's server policy restricts it to development and testing;"
    with "Valhalla is under the same FOSSGIS terms as `routed-foot` (§6.1);".
  - Change the "**Recommendation:**" paragraph to past tense. P2-M0 recommended keeping the straight-line
    connectors and offered FOSSGIS `routed-foot` as an opt-in P2-M4 experiment under the listed conditions;
    **P2-M4 decided against it (§6.1)**. Keep the conditions list as history.
- [ ] **Step 3: Add §6.1** after §6's last paragraph (the privacy sentence):

  ```markdown
  ### 6.1 Decision in P2-M4: no walking router (2026-10-04)

  **Decided by the user on 2026-10-04: the P2-M3 straight dashed "Walk (straight-line estimate)" connectors are
  the final Phase 2 behaviour.** No walking router is integrated: not FOSSGIS `routed-foot` or Valhalla, the OSRM
  demo, OneMap routing, BRouter, or any other. Nothing is added for it: no routing host, CSP entry, HTTP
  behaviour, credential, backend, proxy or coordinate disclosure.

  **Evidence** (read and probed on 2026-10-04; commands and results in the `docs/testing.md` run log, the P2-M4
  discovery row and the Task 1 re-check row, and in `docs/probe-output/walking-routers-p2m4.txt`):
  - **Primary terms:** FOSSGIS e.V., "Nutzungsbedingungen OSM-Server des FOSSGIS e.V."
    (https://www.fossgis.de/arbeitsgruppen/osm-server/nutzungsbedingungen/, German with an English version).
    P2-M0 could not load the page; it loads now.
    - **One set of terms covers both `routing.openstreetmap.de` (`routed-foot`) and
      `valhalla1.openstreetmap.de`.** The routing server's about page (https://routing.openstreetmap.de/about.html)
      and the OSRM demo-server wiki both point to them.
    - From the English version:
      - "Their primary purpose is to support usage on our website and to assist OpenStreetMap contributors in
        their work."
      - "Explicitly recommended: The URLs of our services should not be hardcoded into the app."
      - "For websites, an email address of the operator must be easily identifiable and directly reachable … For
        apps, this applies to the app website and its entries in app stores."
      - "Valid HTTP User-Agent identifying the application. User agents of libraries are not sufficient."
      - "Websites with high traffic volumes are generally not permitted to use our services."
      - "Commercial use is only permitted if the use of the services does not constitute a substantial part of an
        online offering."
      - For the routing servers: "Maximum one request per second."
      - Attribution "as required by the license", plus a link to https://www.openstreetmap.org/fixthemap.
      - "permission to use the services may be revoked by us at any time without stating reasons".
      - "each service is backed by only a single server. We do not guarantee availability."
    - The about page adds that a route request "is saved in the server log file".
    - No clause limits the routing servers to development or testing.
  - **Technically, `routed-foot` works**: it is reachable and usable from Flutter Web.
    - `GET https://routing.openstreetmap.de/routed-foot/route/v1/foot/{lng,lat};{lng,lat}?overview=full&geometries=polyline`
      returns 200 with `Access-Control-Allow-Origin: *` and needs no key.
    - A plain GET needs no CORS preflight; the preflight allows only `X-Requested-With, Content-Type`.
    - The answer is OSRM JSON with a precision-5 Google polyline (the app's `decodePolyline` reads it), a distance
      and a duration.
    - For Raffles Place MRT → Fullerton Hotel (about 300 m apart): 852.5 m in 685.9 s, the same as in P2-M0.

  **Why it is not suitable for this app:**
  1. **Hardcoded URL.** With no backend (ADR-001) there is no remote configuration or kill switch. The URL would
     be a constant in every APK, against FOSSGIS's explicit recommendation, and an installed APK would keep
     calling it after a revocation or a change of terms.
  2. **Operator contact.** The terms require an operator email that is easy to find on the website and in
     app-store entries. The project publishes none.
  3. **Android User-Agent.** Library User-Agents are not enough. On Android, `JsonHttpClient` sends Dart's
     default, so meeting this would change the shared HTTP client or add a second one. On Web the browser's own
     headers are acceptable, by FOSSGIS's own note.
  4. **Privacy.** Routing would send the exact origin (often the GPS position) and the destination to a third
     party that logs requests. Today no request carries exact user coordinates: OneMap search gets typed text,
     ArriveLah gets stop codes, and OneMap tiles reveal only the area being viewed.
  5. **Traffic.** The services are mainly for FOSSGIS's own site and OSM contributors, and high-traffic sites are
     not allowed. A public Web/APK app with no backend and no analytics can neither bound nor observe its total
     request volume (about 2 requests per shown option, sent again for each journey or selection).
  6. **Attribution.** A routed line needs a second attribution next to OneMap's required one: OSM (ODbL) plus a
     "fix the map" link, whenever the line is shown.
  7. **No service commitment.** There is one server, no availability guarantee, and the permission can be
     withdrawn at any time.

  Valhalla is under the same terms, and would also need a precision-6 decoder. The OSRM demo's `/foot/` returns a
  car route, and its wiki limits it to "reasonable, non-commercial use-cases". OneMap routing needs a token
  (401). BRouter publishes only a privacy policy. The keyed routers (openrouteservice, GraphHopper, Mapbox,
  Geoapify, Stadia) need credentials. A 2026-10-04 search found no new keyless walking router.

  **Why the estimates meet the specification.** Guide §17 allows walking-route geometry "**only** if a keyless,
  CORS-enabled routing provider is found and its policy allows client use. Otherwise keep straight-line 'est.'
  connectors." So the second branch is the specified behaviour, not a degraded one.
  - The walking times stay the planner's labelled estimate (guide §9.3, `WalkEstimate`), shown only in the journey
    card.
  - The map draws its connectors between the same points that estimate uses, and labels them "Walk (straight-line
    estimate)".
  - Its screen-reader summary says the walks are straight lines and estimates only.

  **Reopen only on a material change, and only with the user's explicit approval:**
  - a keyless, CORS-enabled walking router whose published terms explicitly allow third-party client or app
    traffic at this app's scale, on conditions the project can meet without a backend;
  - FOSSGIS changing these terms in that direction (to re-check, use the commands in
    `docs/p2-m4-map-hardening-implementation-plan.md`, Task 1, Step 1);
  - a change to the project's architecture (ADR-001 superseded), which is not planned;
  - on-device routing becoming practical on both Web and Android.

  A successful HTTP request alone is never a reason to reopen.
  ```

- [ ] **Step 4: Point the other `map-feasibility.md` mentions at §6.1.**
  - **§1 table, row "Walking geometry":** "**Keep straight-line "est." connectors** (guide §17). **Decided in P2-M4
    (2026-10-04): no walking router** (§6.1)". The why cell: "None of the keyless routers had terms this app can
    meet without a backend; the primary FOSSGIS terms were read in P2-M4 (§6.1)".
  - **§7 "What would add hosts, if chosen later":** "FOSSGIS walk: `https://routing.openstreetmap.de` (not chosen,
    §6.1)".
  - **§9 M9 mitigation:** "OneMap only (already used for search); **no walking router** (§6.1), so no exact
    coordinates leave the app".
  - **§10 item 4, last bullet:** replace "Optional, **only if approved**: the FOSSGIS `routed-foot` experiment behind
    a config flag, with the §6 conditions and its own CSP host." with "The optional FOSSGIS `routed-foot` experiment:
    not adopted (P2-M4 D2, 2026-10-04; §6.1)."
  - **§11 item 3:** "Walking: **decided in P2-M3 (2026-10-04).** Straight-line "est." connectors, drawn dashed; no
    walking router. **Closed in P2-M4 (2026-10-04): FOSSGIS `routed-foot` is not adopted (§6.1).**"
- [ ] **Step 5: `docs/data-sources.md` "Excluded".** Under "**Phase 2 map candidates ruled out in P2-M0**":
  - Replace "The OSRM demo server is car-only." with "The OSRM demo server: its `/foot/` returns a car route
    (checked again in the P2-M4 discovery, 2026-10-04), and its wiki limits it to reasonable, non-commercial
    use."
  - Replace "FOSSGIS Valhalla is for development and testing only." with "FOSSGIS `routed-foot` and Valhalla
    (`routing.openstreetmap.de`, `valhalla1.openstreetmap.de`): keyless and CORS-enabled, but their shared terms
    don't fit a backend-less public app (no hardcoded URLs recommended, an operator email, an app User-Agent,
    request logging, no high-traffic sites). Not adopted in P2-M4 (`docs/map-feasibility.md` §6.1)."
  - Keep "BRouter has no usage policy." and add "(checked again in the P2-M4 discovery, 2026-10-04)". Keep the
    keyed-provider line.
  - Change the heading to "**Phase 2 map candidates ruled out in P2-M0 and P2-M4**" and add §6.1 to its
    references.
- [ ] **Step 6: `docs/assumptions.md`, then the stale-wording check.**
  - "Walking estimate": replace "Real walking routing could improve this in Phase 2" with "Phase 2 looked at keyless
    walking routers and kept this estimate (P2-M4, `docs/map-feasibility.md` §6.1)".
  - "Walking connectors and legend (P2-M3)": add to the rule cell "Final for Phase 2: P2-M4 closed the walking-router
    question with no router (2026-10-04, `docs/map-feasibility.md` §6.1)", and add "P2-M4 D2" to its source cell.
  - `docs/architecture.md:317` (P2-M3 "Not in P2-M3"): replace "(the `routed-foot` question stays with P2-M4)" with
    "(the `routed-foot` question went to P2-M4, which closed it with no router: `docs/map-feasibility.md` §6.1)".
  - Run (before this task, it matched architecture.md:317, data-sources.md:132 and map-feasibility.md:31, 260, 268,
    276, 362, 423 and 434):

    ```bash
    git grep -n -i -E "development and testing|stays a P2-M4 question|stays with P2-M4|opt-in|only if approved|walking router off by default" -- docs README.md CLAUDE.md
    ```

    Expected matches afterwards:
    - the plan documents (`docs/p2-m3-map-option-sync-implementation-plan.md` and this plan);
    - `map-feasibility.md` §6's Valhalla row, which quotes the old claim in order to correct it;
    - §6's recommendation paragraph, now history ("P2-M0 … offered … as an opt-in P2-M4 experiment").

    Any other match is stale wording: fix it.
- [ ] **Step 7: Run-log row** in `docs/testing.md`: "P2-M4 Task 1: walking-router re-check and decision record".
  Give the command (Task 1, Step 1), the UTC time, each result from the output file, and "docs only; `lib/`
  unchanged".
- [ ] **Step 8: Gates for a docs change:** `dart format --set-exit-if-changed .`, `flutter analyze`. They must
  pass.
- [ ] **Step 9: Commit.**
  - Check `git branch --show-current` (must be `feat/p2-m4-map-hardening`).
  - `git add docs/map-feasibility.md docs/data-sources.md docs/assumptions.md docs/architecture.md docs/testing.md docs/probe-output/walking-routers-p2m4.txt`
  - `git commit -m "docs(p2-m4): close the walking-router question; correct the Valhalla rows"`

### Task 2: Reduced motion for map gestures, test first (D3)

**Files:**
- Modify: `lib/features/map/presentation/journey_map.dart` (the class doc comment at :13-23; `build`, around
  :137-145; the `MapOptions` at :185-197)
- Test: `test/features/map/journey_map_card_test.dart` (new group at the end of `main`)
- Modify: `docs/assumptions.md` (new row), `CLAUDE.md` (Map paragraph), `docs/testing.md` (run log)

**Interfaces:** produces the two private constants above. No public change.

- [ ] **Step 1: Write the failing tests.** Add this group as the last group in `main()` of
  `test/features/map/journey_map_card_test.dart`. It needs no new imports: `FakeAccessibilityFeatures` comes from
  `flutter_test`, and `InteractionOptions`, `InteractiveFlag` and `MapCamera` from `flutter_map`.

  ```dart
    group('reduced motion (P2-M4)', () {
      MapCamera camera(WidgetTester tester) =>
          MapCamera.of(tester.element(find.byType(MarkerLayer)));

      InteractionOptions gestures(WidgetTester tester) => tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .options
          .interactionOptions;

      /// The system's reduce-motion setting as the engine reports it (Android
      /// "Remove animations", Web prefers-reduced-motion). It reaches both
      /// MediaQuery and the framework's own animation scaling.
      void setReduceMotion(WidgetTester tester, bool on) {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            FakeAccessibilityFeatures(disableAnimations: on);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
      }

      Future<void> openJourneyMap(WidgetTester tester) async {
        await pumpApp(tester, app());
        await pickDestination(tester, 'VivoCity', 'VIVOCITY');
        await openMap(tester);
        await tester.pump();
      }

      /// Two taps on an empty part of the map: near its top-left corner, which
      /// the fitted camera keeps clear of every pin (MapConfig.fitPadding).
      Future<void> doubleTapMap(WidgetTester tester) async {
        final spot =
            tester.getTopLeft(find.byType(FlutterMap)) + const Offset(12, 12);
        await tester.tapAt(spot);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(spot);
      }

      /// A quick swipe, well over flutter_map's 800 px/s fling threshold.
      Future<void> swipeMap(WidgetTester tester) =>
          tester.fling(find.byType(FlutterMap), const Offset(-300, 0), 2000);

      const allButRotate = InteractiveFlag.all & ~InteractiveFlag.rotate;

      testWidgets('the gestures follow the reduce-motion setting: no fling and '
          'an instant double-tap zoom while it is on, flutter_map\'s defaults '
          'otherwise; every other gesture stays on', (tester) async {
        await openJourneyMap(tester);
        expect(gestures(tester).flags, allButRotate);
        expect(
          gestures(tester).doubleTapZoomDuration,
          const InteractionOptions().doubleTapZoomDuration,
        );

        setReduceMotion(tester, true);
        await tester.pump();
        expect(
          gestures(tester).flags,
          allButRotate & ~InteractiveFlag.flingAnimation,
        );
        expect(gestures(tester).doubleTapZoomDuration, Duration.zero);

        setReduceMotion(tester, false);
        await tester.pump();
        expect(gestures(tester).flags, allButRotate);
        expect(
          gestures(tester).doubleTapZoomDuration,
          const InteractionOptions().doubleTapZoomDuration,
        );
      });

      testWidgets('reduce motion: a swipe moves the map and it stops where the '
          'finger lifts; a double-tap zoom lands in the same frame', (
        tester,
      ) async {
        setReduceMotion(tester, true);
        await openJourneyMap(tester);
        final before = camera(tester).center;

        await swipeMap(tester);
        await tester.pump();
        final released = camera(tester).center;
        expect(released, isNot(before), reason: 'the drag itself still works');
        await tester.pump(const Duration(seconds: 1));
        expect(camera(tester).center, released, reason: 'no glide, no jump');

        final zoom = camera(tester).zoom;
        await doubleTapMap(tester);
        await tester.pump();
        expect(camera(tester).zoom, closeTo(zoom + 1, 1e-9));
      });

      // A guard, not a regression test: it passes before and after P2-M4. It
      // pins flutter_map's default motion when the setting is off, and shows
      // that the checks above can tell motion from none.
      testWidgets('without reduce motion: a swipe glides on after the finger '
          'lifts and a double-tap zoom animates (flutter_map\'s defaults)', (
        tester,
      ) async {
        await openJourneyMap(tester);
        await swipeMap(tester);
        await tester.pump();
        final released = camera(tester).center;
        await tester.pump(const Duration(seconds: 1));
        expect(camera(tester).center, isNot(released));

        final zoom = camera(tester).zoom;
        await doubleTapMap(tester);
        await tester.pump();
        expect(camera(tester).zoom, closeTo(zoom, 1e-9));
        await tester.pump(const Duration(milliseconds: 300));
        expect(camera(tester).zoom, closeTo(zoom + 1, 1e-9));
      });

      testWidgets('reduce motion switched on while the map is open (as '
          'designed, Q1): the camera stays where the user panned it, the next '
          'swipe stops where the finger lifts, a double-tap zoom lands within a '
          'frame, and the journey stays drawn', (tester) async {
        await openJourneyMap(tester);
        expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
        // A slow pan (under the fling threshold), so the user's view differs
        // from the fitted one and a refit would show.
        await tester.timedDrag(
          find.byType(FlutterMap),
          const Offset(-200, 0),
          const Duration(seconds: 1),
        );
        await tester.pump();
        final panned = camera(tester);

        setReduceMotion(tester, true);
        await tester.pump();
        expect(camera(tester).center, panned.center, reason: 'no rebuild/refit');
        expect(camera(tester).zoom, panned.zoom, reason: 'no rebuild/refit');

        await swipeMap(tester);
        await tester.pump();
        final released = camera(tester).center;
        await tester.pump(const Duration(seconds: 1));
        expect(camera(tester).center, released);

        // As designed (P2-M4 Q1): the map is not rebuilt when the setting
        // changes, so it keeps the duration flutter_map fixed at creation, and
        // the framework plays it at 5 % (10 ms), within one frame. A map opened
        // with the setting on uses zero.
        final zoom = camera(tester).zoom;
        await doubleTapMap(tester);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 17));
        expect(camera(tester).zoom, closeTo(zoom + 1, 1e-9));

        expect(find.byKey(const Key('map-ride-line')), findsOneWidget);
        expect(find.byKey(const Key('map-walk-connectors')), findsOneWidget);
        expect(marker('mrtNearOrigin'), findsOneWidget);
        expect(marker('mrtNearDestination'), findsOneWidget);
        expect(geometry.loads, 1);
      });
    });
  ```

- [ ] **Step 2: Watch them fail.**
  - Run: `flutter test test/features/map/journey_map_card_test.dart --plain-name "reduced motion (P2-M4)"`
  - Expected: three tests FAIL and one passes.
    - "the gestures follow…" fails at the reduced flags (`flingAnimation` still set).
    - "reduce motion: a swipe…" fails at `'no glide, no jump'`: today the framework's ×200 fling moves the map
      after release.
    - "switched on while the map is open" fails at the same center check.
    - "without reduce motion…" passes (a guard).
  - If the double-tap expectations fail on their own because the taps were not recognised (the zoom is unchanged
    even after 300 ms in the guard), the gesture timing is wrong, not the feature. flutter_map's
    `PositionedTapDetector2` needs the second tap within 250 ms and within 48 px of the first, so adjust only the
    pump between the taps.
- [ ] **Step 3: Implement.** In `lib/features/map/presentation/journey_map.dart`:
  - Add to `_JourneyMapState`, next to `_constraint`:

    ```dart
      /// Every gesture but rotation (P2-M1), with flutter_map's motion: the map
      /// glides on after a quick swipe and a double tap zooms over 200 ms.
      static const _interaction = InteractionOptions(
        flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
      );

      /// The same gestures for the system's reduce-motion setting (P2-M4): the
      /// map stops where the finger lifts, and a double-tap zoom lands at once.
      /// Under that setting the framework would otherwise play a fling 200×
      /// faster, so the map jumped on release.
      static const _reducedMotionInteraction = InteractionOptions(
        flags:
            InteractiveFlag.all &
            ~InteractiveFlag.rotate &
            ~InteractiveFlag.flingAnimation,
        doubleTapZoomDuration: Duration.zero,
      );
    ```

  - In `build`, after `_brightness = brightness;`:

    ```dart
        // Android "Remove animations", Web prefers-reduced-motion. flutter_map
        // reads the flags on every gesture but the double-tap duration only when
        // the map is created; a change while it is open leaves that zoom to the
        // framework's reduced timing (one frame) until the map is next opened.
        final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    ```

  - In `MapOptions`, replace the `interactionOptions: const InteractionOptions(...)` argument with:

    ```dart
                          interactionOptions: reduceMotion
                              ? _reducedMotionInteraction
                              : _interaction,
    ```

  - At the end of the class doc comment (after "…failed tiles are not retried automatically."), add a paragraph:

    ```dart
    ///
    /// Reduced motion (P2-M4): with the system's setting on, a swipe stops
    /// where the finger lifts and a double-tap zoom lands at once; every
    /// gesture still works.
    ```
- [ ] **Step 4: Watch them pass, then the whole file and the suite.**
  - `flutter test test/features/map/journey_map_card_test.dart --plain-name "reduced motion (P2-M4)"`: 4/4.
  - `flutter test test/features/map/journey_map_card_test.dart`: all pass.
  - `flutter test`: all pass.
- [ ] **Step 5: Mutation checks.** Apply each one alone, run the group, confirm it fails, then revert:
  1. Remove `& ~InteractiveFlag.flingAnimation` from `_reducedMotionInteraction`. Expected to fail: "the
     gestures follow…", "reduce motion: a swipe…", "switched on…".
  2. Remove `doubleTapZoomDuration: Duration.zero`. Expected to fail: "the gestures follow…" and "reduce motion: a
     swipe…" (its double-tap expectation; the zoom is still at `zoom` after one pump).
  3. Use `_reducedMotionInteraction` always. Expected to fail: "the gestures follow…" (the default flags) and the
     guard.

  Record the results in the run-log row.
- [ ] **Step 6: Docs.**
  - **`docs/assumptions.md`:** add a row after "Map tiles: reasonable use":

    ```markdown
    | Map gestures and reduced motion (P2-M4) | Every gesture but rotation works: drag, pinch zoom and move, double-tap zoom, double-tap-drag zoom, scroll-wheel zoom, keyboard. With the system's reduce-motion setting (Android "Remove animations", i.e. transition animation scale 0; Web `prefers-reduced-motion`; read as `MediaQuery.disableAnimations`, as `MotionSize` does) the map stops where a swipe ends (no fling) and a double-tap zoom lands at once (`Duration.zero`). Before P2-M4 the framework played a fling 200× faster under that setting, so the map jumped on release. Without the setting, flutter_map's defaults are unchanged (fling, 200 ms double-tap zoom). The setting is read on every build. By design, a change while the map is open does not rebuild the map, so the camera, pan and zoom are kept and the scene is not refitted. The next swipe has no fling at once. flutter_map fixed the double-tap duration when the map was created, so that zoom keeps the framework's reduced timing (5 %, one frame) until the map is next opened. Keyboard pan and zoom keep Flutter's reduced-animation behaviour. The camera fit stays unanimated (*Map camera*) | — | P2-M4 D3, Q1, Q2; `docs/map-feasibility.md` §10 item 4 |
    ```

  - **`CLAUDE.md`, Map paragraph:** after "OneMap Default/Night tiles,", add "gestures without fling and with an
    instant double-tap zoom under the system's reduce-motion setting (P2-M4),".
  - **`docs/testing.md`:** a run-log row with the RED and GREEN runs and the mutation results.
- [ ] **Step 7: Format, analyze, commit.**
  - `dart format --set-exit-if-changed .` and `flutter analyze`.
  - Check the branch.
  - `git add lib/features/map/presentation/journey_map.dart test/features/map/journey_map_card_test.dart docs/assumptions.md CLAUDE.md docs/testing.md`
  - `git commit -m "feat(map): reduced motion: no fling, instant double-tap zoom"`
- [ ] **Step 8: Build the release APK once for the device checks.**
  - `flutter build apk --release`.
  - Tasks 3, 7 and 8 use this APK while `lib/` stays unchanged. Rebuild it if a conditional fix changes `lib/`.

### Task 3: Verify that the Android tile cache honours `max-age` (verification only)

**Files:**
- Modify: `docs/map-feasibility.md` (§4.2 rule 4, §8 "Caching")
- Modify: `docs/assumptions.md` ("Map tiles: reasonable use")
- Modify: `docs/testing.md` (run log)

- [ ] **Step 1: Source check** (flutter_map 8.3.2 in the pub cache). Record the file and line numbers in the
  run-log row:
  - `OneMapTileProvider` (`basemap.dart`) passes no `overrideFreshAge`, so freshness comes from the headers.
  - `CachedMapTileMetadata.fromHttpHeaders` (`caching/tile_metadata.dart:50-79`): `staleAt = now + max-age − Age`,
    or minus the age estimated from `Date`.
  - `image_provider.dart:213`: a cached tile that is not stale is returned with **no request**. Otherwise the
    request carries `If-Modified-Since` / `If-None-Match`, and a 304 reuses the bytes and refreshes the metadata.
- [ ] **Step 2: Headers.** Run:

  ```bash
  curl -s -m 20 -D - -o /dev/null -A "sg-smart-commute-p2m4-probe (university course project)" \
    -H "Origin: https://example.com" https://www.onemap.gov.sg/maps/tiles/Default/16/51673/32534.png \
    | tr -d '\r' | grep -iE '^HTTP/|^date|^age|^cache-control|^etag|^last-modified|^expires'
  ```

  Expected: 200 and `Cache-Control: max-age=14400, …`. Note whether `Date`, `Age`, `ETag` and `Last-Modified` are
  present.
- [ ] **Step 3: Live, release APK on the AVD.** Two app sessions, so the second has an empty memory image cache
  and only the disk cache can supply tiles.
  1. Record the AVD (`adb -s emulator-5554 emu avd name`) and install: `adb install -r
     build/app/outputs/flutter-apk/app-release.apk`. If the signature differs from the installed build, `adb
     uninstall sg.smartcommute.sg_smart_commute` first.
  2. **Session A (online).**
     - Deny location (P2-M2/M3 recipe; the emulator's GNSS ANR).
     - Origin by search, "Bishan MRT Station"; destination "VivoCity".
     - "Show map", wait 10 s for tiles, `screencap` (`a-online.png`).
     - `adb shell am force-stop sg.smartcommute.sg_smart_commute`.
  3. **Session B.**
     - Relaunch.
     - Set up the **same** journey online, and leave the map closed (the default).
     - Then `adb shell cmd connectivity airplane-mode enable`.
     - Confirm offline: `adb shell ping -c 1 -W 3 www.onemap.gov.sg` fails.
     - "Show map", wait 5 s, `screencap` (`b-offline-cached.png`).
     - **Expected:** the same tiles drawn, with **no** "Map tiles are unavailable" note. The ride-line note may
       appear, because `routes.min.json` can't load offline; that is expected and recorded.
  4. **Control.** Still offline, pan about two map widths away, into tiles not seen before: twice `adb shell input
     swipe <right x> <map y> <left x> <map y> 400`, with the coordinates read from `b-offline-cached.png`. Then
     `screencap` (`b-offline-new.png`). **Expected:** the tiles note appears. This shows the device really was
     offline.
  5. Run `adb shell cmd connectivity airplane-mode disable` and confirm it is back online.
  6. **Not run, with the reason:** the expiry after 4 h (revalidation). Seeing it live needs a 4-hour wait or a
     changed device clock (the Play Store image has no root). The source check (Step 1) covers it.
  - Run `adb` commands from Git Bash with `MSYS_NO_PATHCONV=1` when a path starts with `/`.
- [ ] **Step 4: Conditional.** If `b-offline-cached.png` shows the tiles note or blank tiles while the control
  behaves as expected, the disk cache did not serve fresh tiles. **Stop.**
  - Diagnose with superpowers:systematic-debugging (cache directory, metadata, headers).
  - **Report to the user before changing tile loading.**
  - Otherwise, no code change.
- [ ] **Step 5: Docs.**
  - **`map-feasibility.md` §4.2 rule 4:** replace "check in P2-M4 that it honours `max-age=14400`" with "Verified in
    P2-M4 (date): flutter_map serves a cached tile without a request until `max-age` (minus `Age`) has passed, then
    revalidates. Seen offline on the AVD (`docs/testing.md`)".
  - **§8 "Caching":** the same, shorter.
  - **`assumptions.md` "Map tiles: reasonable use":** add "Verified in P2-M4: a fresh cached tile is shown with no
    request; a stale one is revalidated (304 reuses it)".
  - **`testing.md`:** a run-log row with every command, the screenshots' findings and the Not run item.
- [ ] **Step 6: Commit.**
  - Check the branch.
  - `git add docs/map-feasibility.md docs/assumptions.md docs/testing.md`
  - `git commit -m "docs(p2-m4): the Android tile cache follows max-age (verified)"`

### Task 4: HD tiles: record the decision (D5; verification and docs only)

**Files:**
- Modify: `docs/map-feasibility.md` (§4.1)
- Modify: `docs/assumptions.md` ("Map tiles: reasonable use")
- Modify: `docs/testing.md`

- [ ] **Step 1: Probe.** Run:

  ```bash
  UA="sg-smart-commute-p2m4-probe (university course project)"
  for s in Default Night Default_HD Night_HD; do
    f=$(mktemp)
    curl -s -m 20 -D "$f.h" -o "$f" -A "$UA" -H "Origin: https://example.com" \
      "https://www.onemap.gov.sg/maps/tiles/$s/16/51673/32534.png"
    printf '%s: %s; %s; ' "$s" "$(head -1 "$f.h" | tr -d '\r')" "$(grep -i '^content-type' "$f.h" | tr -d '\r')"
    python -c "import struct,sys;d=open(sys.argv[1],'rb').read(24);print(struct.unpack('>II',d[16:24]) if d[:8]==b'\x89PNG\r\n\x1a\n' else 'not a PNG')" "$f"
    rm -f "$f" "$f.h"; sleep 1
  done
  curl -s -m 20 -A "$UA" https://www.onemap.gov.sg/maps/json/raster/tilejson/2.2.0/Default.json | head -c 400; echo
  ```

  Expected, as on 2026-10-04:
  - `Default` / `Night`: `image/png`, (256, 256);
  - `*_HD`: `image/undefined`, (256, 256);
  - the TileJSON points at `Default_HD`.
- [ ] **Step 2: Docs.**
  - **§4.1:** replace "Revisit HD in P2-M4." with "**Decided in P2-M4 (D5, 2026-10-04): no HD tiles.** Re-probed
    (date): the `*_HD` tiles are still 256 × 256 and served as `image/undefined`, so they add no detail. The app
    keeps the standard `Default` / `Night` tiles, and no HD mode is added".
  - **`assumptions.md` "Map tiles: reasonable use":** add "No HD tiles (P2-M4 D5)".
  - **`testing.md`:** a run-log row with the probe and its output.
  - D5 holds whatever the probe shows. If HD tiles have become 512 px, record that fact and keep D5.
- [ ] **Step 3: Commit.** `git commit -m "docs(p2-m4): no HD tiles"` (check the branch first).

### Task 5: Re-check the OneMap terms (§4.2 rule 7; verification and docs only)

**Files:**
- Modify: `docs/map-feasibility.md` (§4.2 rule 7)
- Modify: `docs/testing.md`

- [ ] **Step 1: Fetch** (one request each, 1 s apart, into a temporary directory, **not** the repo):

  ```bash
  UA="sg-smart-commute-p2m4-probe (university course project)"; T=$(mktemp -d)
  for u in https://www.onemap.gov.sg/legal/termsofuse.html https://www.onemap.gov.sg/docs/maps/ \
           https://www.onemap.gov.sg/docs/maps/resources/code-attr.txt; do
    curl -s -m 20 -A "$UA" -o "$T/$(basename "$u")" -w "%{http_code} %{size_download} $u\n" "$u"; sleep 1
  done
  cat "$T/code-attr.txt"
  python - "$T/termsofuse.html" <<'EOF'
  import html, re, sys
  t = open(sys.argv[1], encoding='utf-8', errors='replace').read()
  t = re.sub(r'\s+', ' ', html.unescape(re.sub(r'<[^>]+>', ' ', re.sub(r'(?is)<(script|style).*?</\1>', '', t))))
  for k in ['revocable licence', 'any period of time without any prior notice', 'Registered Developers only',
            'as is', 'as available', 'rate limit', 'quota', 'token', 'requests per']:
      print(f'{k!r}: {"present" if k.lower() in t.lower() else "absent"}')
  EOF
  rm -rf "$T"
  ```

  Expected, as on 2026-10-03:
  - all three 200;
  - the attribution snippet still names the 20 × 20 `om_logo.png`, "OneMap © contributors | Singapore Land
    Authority", and links to onemap.gov.sg and sla.gov.sg (compare with `BasemapAttribution` and
    `BasemapEndpoints` in `app_config.dart`);
  - the licence, suspension and "as is" clauses present;
  - no rate limit, quota or token requirement for tiles.
- [ ] **Step 2: Conditional.** If the terms now require a token for tiles, publish a volume limit the map could
  exceed, or change the required attribution: **stop and report to the user.** That is a new reviewed decision
  (§4.2 "If OneMap refuses tiles"). Otherwise there is no code change.
- [ ] **Step 3: Docs.**
  - Under §4.2 rule 7, add "Re-checked in P2-M4 (date, time UTC): unchanged" (or the changes found). "Re-checks were
    not recorded for P2-M1, P2-M2 or P2-M3. The P2-M0 reading (2026-10-03) was the last before P2-M4".
  - **`testing.md`:** a run-log row with the commands and the results.
- [ ] **Step 4: Commit.** `git commit -m "docs(p2-m4): OneMap terms re-checked"` (check the branch first).

### Task 6: Measure map performance on the emulator (D4)

**Files:**
- Create: `tool/map_performance_probe.dart` (dev only)
- Modify: `docs/testing.md` ("Feasibility probes" section and run log)
- Modify: `docs/map-feasibility.md` (§9 M7)

**Interfaces:** consumes `buildTestApp`, `OneMapTileProvider.new`, `initIntegrationTest`, `pumpUntilFound`,
`searchAndPick`, `scrollToAndTap` and `FrameTimingSummarizer`. Its output is
`build/integration_response_data.json`, written by the existing `test_driver/integration_test.dart`
(`integrationDriver()` writes the reported data there by default).

- [ ] **Step 1: Write the probe** at `tool/map_performance_probe.dart`:

  ```dart
  // Dev-only probe (P2-M4, docs/testing.md): frame timings of the open journey
  // map on an Android device or emulator, in profile mode. Not part of the app
  // and not a test gate; `flutter test` never runs it:
  //
  //   flutter drive --profile --keep-app-running -d <android-device> \
  //     --driver=test_driver/integration_test.dart \
  //     --target=tool/map_performance_probe.dart
  //
  // Without --keep-app-running, flutter drive uninstalls the app at the end,
  // and the tile cache goes with it, so a second run would start cold.
  //
  // The journey is the integration tests' fake one (GPS at Bishan, a direct bus
  // to VivoCity with its ride line, both walking connectors and both MRT pins),
  // but the tiles are live OneMap tiles through the app's OneMapTileProvider, so
  // tile decoding and drawing are measured too. Only the tiles of the map on
  // screen are requested: the fitted view and what the scripted pans reveal, in
  // light and then dark mode (docs/map-feasibility.md §4.2). Android only: it
  // imports the shared fakes from integration_test/, which a Web build cannot.
  // The results (FrameTimingSummarizer's summary per mode, plus p95, which it
  // does not compute) land in build/integration_response_data.json.
  import 'dart:ui' show FrameTiming;

  import 'package:flutter/material.dart';
  import 'package:flutter_map/flutter_map.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:integration_test/integration_test.dart';
  import 'package:sg_smart_commute/core/geo/geo.dart';
  import 'package:sg_smart_commute/core/location/location_service.dart';
  import 'package:sg_smart_commute/features/map/presentation/basemap.dart';

  import '../integration_test/fakes/fake_environment_repository.dart';
  import '../integration_test/fakes/fake_location_service.dart';
  import '../integration_test/fakes/test_app.dart';
  import '../integration_test/support.dart';

  void main() {
    initIntegrationTest();

    testWidgets('journey map frame timings, light then dark', (tester) async {
      final binding = IntegrationTestWidgetsFlutterBinding.instance;
      // Frames come from the engine as in the app, not only on pump.
      binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
      await tester.pumpWidget(
        buildTestApp(
          location: FakeLocationService(
            access: LocationAccess.granted,
            position: const LatLng(1.3508, 103.8485), // Bishan
          ),
          environment: FakeEnvironmentRepository(),
          mapTiles: OneMapTileProvider.new,
        ),
      );
      await pumpUntilFound(tester, find.text('From: Current location'));
      await searchAndPick(
        tester,
        field: const Key('destination-field'),
        query: 'VivoCity',
        result: 'VIVOCITY',
      );
      await pumpUntilFound(tester, find.byKey(const Key('journey-suggested')));
      await scrollToAndTap(tester, find.byKey(const Key('show-map')));
      await pumpUntilFound(tester, find.byKey(const Key('map-ride-line')));

      final report = <String, Object?>{};
      for (final mode in [Brightness.light, Brightness.dark]) {
        tester.platformDispatcher.platformBrightnessTestValue = mode;
        // Back to the fitted view, then give this style's first tiles time.
        await scrollToAndTap(tester, find.byKey(const Key('hide-map')));
        await scrollToAndTap(tester, find.byKey(const Key('show-map')));
        await pumpUntilFound(tester, find.byKey(const Key('map-ride-line')));
        for (final key in [
          'map-walk-connectors',
          'map-marker-mrtNearOrigin',
          'map-marker-mrtNearDestination',
        ]) {
          expect(find.byKey(Key(key)), findsOneWidget, reason: key);
        }
        await tester.ensureVisible(find.byType(FlutterMap));
        await tester.pump(const Duration(seconds: 3));
        report[mode.name] = await _measure(tester);
      }
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
      binding.reportData = report;
    });
  }

  /// Four pans around the journey, twice (each 600 ms long, like a finger), then
  /// a double-tap zoom; every frame drawn meanwhile is summarised.
  Future<Map<String, Object?>> _measure(WidgetTester tester) async {
    final frames = <FrameTiming>[];
    void record(List<FrameTiming> timings) => frames.addAll(timings);
    tester.binding.addTimingsCallback(record);

    final map = find.byType(FlutterMap);
    for (var round = 0; round < 2; round++) {
      for (final pan in const [
        Offset(-250, 0),
        Offset(0, -200),
        Offset(250, 0),
        Offset(0, 200),
      ]) {
        await tester.timedDrag(map, pan, const Duration(milliseconds: 600));
        await tester.pump(const Duration(milliseconds: 400));
      }
    }
    // An empty corner of the map (the fitted camera keeps pins clear of it).
    final spot = tester.getTopLeft(map) + const Offset(12, 12);
    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(spot);
    await tester.pump(const Duration(seconds: 1));
    // The engine reports frame timings in batches, about once a second.
    await tester.pump(const Duration(seconds: 2));
    tester.binding.removeTimingsCallback(record);
    if (frames.isEmpty) throw StateError('no frame timings were reported');

    final summary = FrameTimingSummarizer(frames);
    // The same nearest-rank rule FrameTimingSummarizer uses for p90 and p99.
    double p95(List<Duration> times) {
      final sorted = [...times]..sort();
      return sorted[((sorted.length - 1) * 0.95).round()].inMicroseconds / 1e3;
    }

    return {
      ...summary.summary,
      '95th_percentile_frame_build_time_millis': p95(summary.frameBuildTime),
      '95th_percentile_frame_rasterizer_time_millis': p95(
        summary.frameRasterizerTime,
      ),
      'tiles_unavailable_note': find
          .byKey(const Key('map-tiles-unavailable'))
          .evaluate()
          .isNotEmpty,
    };
  }
  ```

- [ ] **Step 2: Analyze.** `dart format --set-exit-if-changed .` and `flutter analyze` must pass. `flutter test`
  must still pass (it doesn't pick up `tool/`).
- [ ] **Step 3: Record the configuration**, where practical:
  - `flutter devices`; `adb -s emulator-5554 emu avd name`;
  - `adb shell getprop ro.build.version.release`, `ro.build.version.sdk`, `ro.product.cpu.abi`,
    `ro.hardware.egl`;
  - `adb shell wm size`, `adb shell wm density`, `adb shell nproc`, `adb shell head -1 /proc/meminfo`;
  - the display refresh rate from `adb shell dumpsys display` (`refreshRate` / `renderFrameRate`, if shown);
  - the host CPU (`powershell -c "(Get-CimInstance Win32_Processor).Name"`).
- [ ] **Step 4: Run it, twice.** Both runs pass `--keep-app-running`. By default, `flutter drive` stops **and
  uninstalls** the app when a run ends (flutter_tools `drive/drive_service.dart`, `stop()`), and that would
  delete Run 1's tile cache before Run 2. With the app still installed, Run 2's start reinstalls it with
  `adb install -r`, which keeps the app's data (`android/android_device.dart`, `installApp`).
  - Don't use `--use-existing-app`. It attaches to an app that is already running and doesn't start it, and this
    probe's test runs once, at app start, so nothing would be measured.
  - **Run 1 (cold tile cache):**
    - `adb uninstall sg.smartcommute.sg_smart_commute` (ignore "not installed");
    - then `flutter drive --profile --keep-app-running -d emulator-5554
      --driver=test_driver/integration_test.dart --target=tool/map_performance_probe.dart`;
    - copy `build/integration_response_data.json` to the scratchpad as `perf-run1.json`.
  - **Run 2 (warm cache):**
    - check the app is still installed: `adb shell pm list packages sg.smartcommute.sg_smart_commute` lists it;
    - run the same command right after Run 1;
    - copy the output as `perf-run2.json`.
    - If Run 2's output shows "Uninstalling old version..." (the `-r` install failed, so the app's data was
      deleted), record Run 2 as a **cold** run, not a warm one.
  - Watch `adb logcat -d -s flutter AndroidRuntime ActivityManager` for exceptions, ANRs or crashes during each
    run.
  - Expected: "All tests passed", and each mode reports `frame_count` > 0 and `tiles_unavailable_note: false`.
  - If `flutter drive --profile` is refused on the x86_64 AVD, stop and report. A release build has no VM service
    for `flutter drive`, and a debug build's timings mean nothing, so neither stands in silently.
  - The live tile requests are those of a visible map panned by hand (§4.2 rules 1–3). Run it **at most twice**,
    and don't repeat runs for nicer numbers.
- [ ] **Step 5: Judge, don't threshold** (D4, Q3). Report, per run (cold or warm cache) and mode (light or dark):
  - the build mode (profile);
  - `frame_count`;
  - average, p90, p95, p99 and worst frame **build** times;
  - the same for **raster** times;
  - the jank count and share: `missed_frame_build_budget_count` and `missed_frame_rasterizer_budget_count`
    (Flutter's 16 ms budget), each also as a share of `frame_count`;
  - the GC counts.

  **Stop and report before attempting any optimisation** (diagnose first with superpowers:systematic-debugging) if:
  - the probe throws or times out;
  - there is an ANR, a crash or a Flutter exception;
  - most frames miss the budget in both build and raster;
  - or a worst frame shows a visible freeze (about a second or more).

  These are triggers for investigation, not a pass mark. Otherwise record the numbers as emulator evidence only.
- [ ] **Step 6: Restore the device for the next tasks.** `adb uninstall sg.smartcommute.sg_smart_commute`, then `adb
  install build/app/outputs/flutter-apk/app-release.apk`. The runs used `--keep-app-running`, so the profile build
  is still installed and running.
- [ ] **Step 7: Docs.**
  - **`testing.md` "Feasibility probes":** add a "Phase 2 M4 (performance)" block. Give the `flutter drive --profile
    --keep-app-running` command and one sentence: the probe uses live OneMap tiles, runs on Android only and is
    not a gate; `--keep-app-running` stops `flutter drive` from uninstalling the app, and with it the tile cache,
    between runs.
  - **Run-log row:** the configuration, the scenario (fake Bishan → VivoCity journey, ride line, two connectors,
    two MRT pins; 8 pans of 600 ms and one double-tap zoom, in light then dark; live OneMap tiles, cold then warm
    cache), both runs' numbers, and "emulator evidence only, not physical-device performance".
  - **`map-feasibility.md` §9 M7:** "check frame times in P2-M4" becomes "measured in P2-M4 on the emulator
    (`docs/testing.md`, date); no physical device was available".
- [ ] **Step 8: Commit, in two commits** (check the branch first):
  - `git add tool/map_performance_probe.dart` and `git commit -m "tool: journey map performance probe (dev-only)"`;
  - `git add docs/testing.md docs/map-feasibility.md` and `git commit -m "docs(p2-m4): map performance on the
    emulator"`.

### Task 7: Accessibility check, one TalkBack attempt (D6)

**Files:**
- Modify: `docs/testing.md` (run log; Task 9 adds the open-items line)

- [ ] **Step 1: Record the current settings:**
  - `adb shell settings get secure enabled_accessibility_services`
  - `adb shell settings get secure accessibility_enabled`
  - `adb shell settings get global transition_animation_scale`
- [ ] **Step 2: One attempt.**
  - `adb shell settings put secure enabled_accessibility_services
    com.google.android.marvin.talkback/com.google.android.marvin.talkback.TalkBackService`
  - `adb shell settings put secure accessibility_enabled 1`
  - `screencap`.
- [ ] **Step 3a: If a setup or permission prompt from the Accessibility Suite blocks it** (as in P2-M3):
  - Don't try further settings or answer the prompt.
  - Go to Step 4 and record **Not run** with the exact prompt text from the screenshot.
- [ ] **Step 3b: If TalkBack runs:**
  - Open the release app with a direct-bus journey and the map open.
  - Move focus with single-finger swipes right (`adb shell input swipe <left x> <y> <right x> <y> 120`, with the
    coordinates read from a screenshot), with a `screencap` after each.
  - Check, by the focus outline and any `adb logcat -d | grep -i talkback` speech lines:
    - the map is **one** node (its summary);
    - the legend text is read;
    - "Select Bus N" and "Bus N selected" are read;
    - the "OneMap" and "Singapore Land Authority" links are links.
  - Record what was and wasn't verifiable. Spoken text may not be in the log; then the focus order is the evidence.
- [ ] **Step 4: Restore** the exact values from Step 1 (`settings put`; if the first value was `null`, use `settings
  delete secure enabled_accessibility_services`). Read them back to confirm.
- [ ] **Step 5: Run-log row:**
  - the result, or **Not run** with the exact reason;
  - the restored values;
  - "Accessibility evidence otherwise: `test/features/map/journey_map_card_test.dart` 'the map is one summary for
    screen readers'; `test/features/journey/journey_widget_test.dart` ('Select Bus F10', 'Bus F20 selected',
    `isSemantics`); the Web semantics-tree labels in the P2-M3 live Web check (2026-10-04)".
  - Don't change any accessibility test.
- [ ] **Step 6: Commit.** `git commit -m "docs(p2-m4): TalkBack check"` (check the branch first).

### Task 8: Final gates, integration runs and live smoke (regression)

**Files:**
- Modify: `docs/testing.md` (run log only)

- [ ] **Step 1: No-routing code check.** Run:

  ```bash
  git grep -n -i -E "routing\.openstreetmap|valhalla|project-osrm|brouter|routingsvc" -- lib web test integration_test pubspec.yaml
  ```

  Expected: no output.
- [ ] **Step 2: Gates** (the next section) on the code-final head. Each must actually pass.
- [ ] **Step 3: Live checks** (the section after). Record every result. A failure goes to the conditional rule:
  stop, diagnose, report.
- [ ] **Step 4: Run-log rows** for the gates and the live checks, then commit with `git commit -m "docs(testing):
  P2-M4 gates and live checks"`.

### Task 9: Phase 2 close-out and the PR (D8)

Only if Tasks 1–8 succeeded.

**Files:**
- Modify: `docs/map-feasibility.md` (§10 item 4, §11)
- Modify: `docs/architecture.md` (new section before "## Dev tools (M0)")
- Modify: `README.md` (status, known limitations, roadmap)
- Modify: `CLAUDE.md` (Project paragraph)
- Modify: `docs/testing.md` ("Open acceptance items")

- [ ] **Step 1: `map-feasibility.md` §10 item 4.** Add "**Done in P2-M4** (date; plan
  `docs/p2-m4-map-hardening-implementation-plan.md`, D1–D8, Q1–Q4, R)" with these bullets:
  - the cache cap was already done in P2-M1, and `max-age` was verified;
  - emulator frame times are measured (link);
  - reduced motion: no fling, instant double-tap zoom;
  - TalkBack: the result or Not run;
  - the integration and live regression runs;
  - no HD tiles;
  - no walking router (§6.1).

  Then the line: "**Phase 2 (the journey map) is complete.**" Add §11 item 4: "P2-M4 decisions: D1–D8, Q1–Q4 and R
  in the P2-M4 plan; all closed."
- [ ] **Step 2: `architecture.md`.** Add a section `## Phase 2 Milestone 4 (hardening) and Phase 2 close-out`:
  - **Reduced motion:** two constant `InteractionOptions` in `JourneyMap`, chosen by
    `MediaQuery.disableAnimations`. Why: flutter_map ignores the setting, and the framework's ×200 fling made the
    map jump. The camera fit is unchanged, and the double-tap duration is fixed when the map is created.
  - **No walking router:** `docs/map-feasibility.md` §6.1, so no new host, client or CSP change; the map stays a
    consumer of the plan.
  - **Verified, unchanged:** the tile cache follows `max-age`; no HD tiles; OneMap terms re-checked.
  - **Dev tool:** `tool/map_performance_probe.dart` (profile, Android, live tiles, not a gate).
  - **Not in P2-M4:** any new map feature, routing, the simplification refactor, UI polish.
  - Also add `tool/map_performance_probe.dart` to the "Dev tools (M0)" list.
- [ ] **Step 3: `README.md`.**
  - **Status paragraph:** replace it with:

    > **Status:** Phase 1 (M1–M5) and Phase 2 (the optional journey map, P2-M0–P2-M4) are complete: location with
    > manual fallback, the environmental dashboard, OneMap place search, a direct-bus suggestion with live arrivals
    > and an MRT alternative, and an optional map (OneMap basemap) showing the selected option's bus route, straight
    > walking estimates and the MRT suggestions. UI polish continues separately.

  - **Known limitations:** add "The map's walking lines are straight-line estimates between the same points as the
    walking times; there is no walking router (`docs/map-feasibility.md` §6.1)" and "The map needs network for its
    OneMap tiles (no offline maps); OneMap gives no service-level agreement".
  - **Roadmap:** "M1 location + environment → M2 places → M3 direct-bus planner + MRT → M4 live arrivals → M5
    hardening → Phase 2 map (P2-M0 feasibility → P2-M1 map shell → P2-M2 bus ride line → P2-M3 option sync, walk
    connectors, MRT markers → P2-M4 hardening): **complete**. UI polish continues separately."
- [ ] **Step 4: `CLAUDE.md` Project paragraph.**
  - After the milestone list "(guide §21: … → Phase 2 map)", add "Phase 2 closed in P2-M4; a later change needs its
    own milestone".
  - In the Map bullet, change "straight and dashed, never routed" to "straight and dashed, never routed (no walking
    router: `docs/map-feasibility.md` §6.1)".
- [ ] **Step 5: `testing.md` "Open acceptance items".** Add "**Phase 2 (map), after P2-M4**" bullets:
  - integration on Android and Web: closed (the three files, 0 CSP violations);
  - live smoke on Web and Android: light, dark, 360 dp, 2× text;
  - tile cache: verified (4-hour expiry Not run, source-verified);
  - performance: emulator numbers only, no physical device;
  - TalkBack: the result or Not run;
  - `flutter test --platform chrome`: Not run (the flutter_tools Windows path bugs).
- [ ] **Step 6: Docs gates.** `dart format --set-exit-if-changed .`, `flutter analyze`, `flutter test`. Docs only,
  so these confirm nothing else changed. Record the results in the Task 8 row as "later commit docs-only".
- [ ] **Step 7: Commit, push, open the PR. Don't merge.**
  - Check the branch.
  - `git commit -m "docs: close Phase 2 (P2-M4)"`
  - `git push -u origin feat/p2-m4-map-hardening`
  - `gh pr create --base main`, with a body that lists D1–D8, Q1–Q4 and R, the tasks, the gates, the live checks
    and the Not run items, ending with the attribution line.

---

## Quality gates (Task 8; all must actually pass)

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
flutter build apk --release
flutter test integration_test -d emulator-5554
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_boot_test.dart     -d web-server --browser-name=chrome --profile
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/happy_path_test.dart   -d web-server --browser-name=chrome --profile
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/fallback_path_test.dart -d web-server --browser-name=chrome --profile
```

- The Web drive runs need chromedriver 154.0.8037.92 on port 4444. Start it with `--enable-chrome-logs`, and count
  CSP violations and SEVERE lines in its log; expect 0.
- **`flutter test --platform chrome`: Not run.**
  - Reason: the known flutter_tools Windows path bugs (logged 2026-10-03).
  - P2-M4 adds no Web-specific arithmetic, and its gesture logic is platform-independent Dart covered on the VM.
  - Retry only if the Flutter toolchain or Windows has materially changed since.
- **Before serving for the live checks,** rebuild with `flutter build web --release`. `flutter drive` leaves a test
  build in `build/web`.
- After a run, stop chromedriver through its `/shutdown` endpoint, and stop the `http.server` background task. Ask
  the user before killing anything else (the dartvm holding a port, the emulator).

## Live checks (real APIs; log in `docs/testing.md`)

**Web** (release build served by `python -m http.server 8773`; headless Chrome 154 through chromedriver; GPS
overridden to Bishan through CDP; the P2-M1–M3 recipe):
1. Bishan → VivoCity (or Bishan → HDB Hub, the P2-M3 trip with three buses). Show the map and check:
   - the line, two dashed connectors, both MRT pins, the legend and the attribution;
   - 0 CSP violations.
2. **No walking router.** The page's resource timing lists no request to `routing.openstreetmap.de`,
   `valhalla1.openstreetmap.de`, `router.project-osrm.org`, `brouter.de` or OneMap `routingsvc`, and only the
   CSP's hosts.
3. **Browser cache.** Reload the page, set up the same journey, "Show map": the tile entries have `transferSize ==
   0` (served from Chrome's HTTP cache within `max-age`).
4. **Reduced motion.**
   - New session with CDP `Emulation.setEmulatedMedia` set to `prefers-reduced-motion: reduce` before loading.
   - Make a quick WebDriver pointer drag on the map (pointerDown, a 300 px move over 50 ms, pointerUp).
     Screenshot at once and after 1 s: the map is the same in both.
   - **Control:** the same drag in a session without the emulation: the map has moved on in the second
     screenshot.
   - Supplementary only (Q4). If the control doesn't glide either (WebDriver may not produce fling velocity),
     record this check as **Not run (not reproducible through WebDriver)**, with that reason. The widget tests are
     the acceptance evidence. The reduce-motion session must still load and pan with no error.
5. Select an alternative: the line and connectors move, there is no arrival request, and one `routes.min.json`
   (P2-M3 regression).
6. A walk-only trip and a no-direct-bus trip: the ends and MRT pins only; no connectors and no legend.
7. Dark mode (Night tiles), and 360 px with a 2× root font: readable, no overflow, and the legend wraps.
8. Visual spot-check (§9 M10): real OneMap imagery, no watermark tiles.

**Android** (release APK of the code-final head; Pixel_8_Pro AVD; location denied and origin by search, as in
P2-M2/M3):
1. Journey with a direct bus. "Show map": line, connectors, MRT pins, legend, attribution.
2. Select an alternative: the map follows it (regression).
3. **Fling, default motion.** A quick horizontal swipe across the map, `adb shell input swipe <right x> <map y>
   <left x> <map y> 60`, with the coordinates read from a screenshot. Then `screencap` at once and after 1.5 s: the
   map has moved on in between.
4. **Reduced motion.**
   - Record the current values of `window_animation_scale`, `transition_animation_scale` and
     `animator_duration_scale`, then set each to 0 (`adb shell settings put global <name> 0`). This is what
     "Remove animations" does.
   - Relaunch the app and repeat step 3: the two screenshots show the same map.
   - Double-tap an empty part of the map (`adb shell "input tap <x> <y>; input tap <x> <y>"`): it zooms in, with no
     error. If the two taps arrive more than 250 ms apart, flutter_map sees two single taps; then record this check
     as **Not run (not reproducible through adb)** (Q4). Likewise, if the default-motion swipe in step 3 shows no
     glide, record the fling comparison as not reproducible rather than as a pass.
   - **Restore** the three recorded values and read them back.
5. Dark mode (`cmd uimode night yes`, then `no`) and `font_scale 2.0` (then `1.0`): readable, no overflow, the
   selection survives. Restore the settings.
6. Visual spot-check (§9 M10).
7. TalkBack: Task 7 (one attempt), not repeated here.

---

## Commit boundaries (summary)

**PR 1** (`docs/p2-m4-map-hardening-plan`): `docs(p2-m4): map hardening implementation plan`.

**PR 2** (`feat/p2-m4-map-hardening`):

| Task | Commit |
|---|---|
| 1 | `docs(p2-m4): close the walking-router question; correct the Valhalla rows` |
| 2 | `feat(map): reduced motion: no fling, instant double-tap zoom` |
| 3 | `docs(p2-m4): the Android tile cache follows max-age (verified)`, plus a fix commit only if Step 4 found a defect and the user approved the fix |
| 4 | `docs(p2-m4): no HD tiles` |
| 5 | `docs(p2-m4): OneMap terms re-checked` |
| 6 | `tool: journey map performance probe (dev-only)`; `docs(p2-m4): map performance on the emulator` |
| 7 | `docs(p2-m4): TalkBack check` |
| 8 | `docs(testing): P2-M4 gates and live checks` |
| 9 | `docs: close Phase 2 (P2-M4)` |

Every commit message ends with the attribution line given in the session.

## Required-test and check coverage map

| Requirement | Test / check (task) |
|---|---|
| D3: no fling under reduce motion | T2 test B ("stops where the finger lifts"); test D (switched on while open); mutation 1; Android live step 4; Web live step 4 |
| D3: instant double-tap zoom under reduce motion | T2 test B (same frame); test D (within a frame after a mid-session change); mutation 2 |
| D3: defaults unchanged without reduce motion | T2 test A (flags and duration); test C (guard: glide and 200 ms zoom); mutation 3; Android live step 3 |
| D3: every other gesture still works | T2 test A (exact flag set); test B ("the drag itself still works") |
| D3: camera fit unchanged | No code touched in `_fittedCamera` / `_fitLatest`; existing camera tests stay green (T2 step 4) |
| Q1: a setting change while the map is open, as designed | T2 test D (camera kept where panned: no rebuild or refit; line, connectors, MRT pins; `geometry.loads == 1`; double-tap within a frame) |
| Q4: live gesture checks are supplementary | Web live step 4, Android live step 4 (Not run / not reproducible when a tool can't produce the gesture) |
| D2: no router introduced | T8 step 1 (code grep); Web live step 2 (resource timing); CSP test unchanged |
| D2: docs record the investigation, Valhalla corrected | T1 steps 1–6, including the stale-wording grep |
| Tile cache follows `max-age` | T3 source check, headers, two-session offline check with a control; Web live step 3 |
| D5: HD decision recorded | T4 probe and docs |
| §4.2 rule 7 terms re-check | T5 |
| D4: performance measured | T6 (two runs, light and dark, numbers and configuration) |
| D6: TalkBack, one attempt | T7 |
| P2-M1–M3 regression | T8 gates (all unit, widget and integration tests), Web drive 3/3, Android integration, live steps |
| D8: Phase 2 close-out | T9 docs |

## Risks (the open questions are resolved: Q1–Q4 and R above)

1. **Resolved (Q1): a double-tap right after reduce motion is switched on, with the map already open, takes one
   frame, not zero.**
   - flutter_map 8.3.2 reads `doubleTapZoomDuration` only when the map is created, and the framework's 5 % scaling
     makes it 10 ms.
   - This is the designed behaviour: the map is not rebuilt, so the camera, pan and zoom are kept and the scene is
     not refitted.
   - A map opened with the setting on uses zero.
   - Test D and the assumptions row record it as designed.
2. **Resolved (Q2): keyboard pan and zoom (Web, desktop)** keep Flutter's and flutter_map's reduced-animation
   behaviour, with no customisation. If implementation testing finds a concrete accessibility defect there: stop
   and report.
3. **The performance probe uses fake journey geometry** (approved, Q3).
   - The fake ride line runs straight through its stops: a handful of points, against tens for a real busrouter
     slice.
   - The tiles are real.
   - Polyline cost at tens of points is negligible next to tile raster, but it is a known difference, and it is
     recorded.
4. **Emulator numbers say little about low-end phones.** The project has no physical device. The emulator's
   rendering also depends on the host GPU, so its configuration is recorded.
5. **The probe makes live OneMap tile requests** (approved, Q3): two runs, about the tiles a user sees panning the
   map by hand. This is within §4.2's rules: a visible map, bounded pans, no prefetch, no retry. It is a dev tool,
   as `tool/probe_map.sh` is.
6. **TalkBack may be blocked again** by the Accessibility Suite prompt. D6 covers this: Not run, with the reason.
7. **The 4-hour cache expiry is not observed live.** The source covers it (Task 3).
8. **The missing OneMap terms re-checks for P2-M1–M3 can't be done after the fact.** Task 5 records the gap
   honestly.
9. **The double-tap timing in widget tests depends on flutter_map's `PositionedTapDetector2`** (250 ms window,
   48 px). Test C is the guard that shows the taps are recognised.
10. **`tool/` importing `integration_test/fakes/`** is new. It works on Android only, which is fine for a dev
    probe. The CLAUDE.md rule that "nothing else in `test/` should import from `integration_test/`" is about
    `test/` and is unaffected.

## Self-review notes (2026-10-04, against `main` at `2c415e5`)

- **The user's approval applied (2026-10-04):**
  - Q1–Q4 and R are recorded under "Decisions" and frozen.
  - No section still asks for a decision.
  - Task 1's re-probe is cut to `routed-foot` and the FOSSGIS sources (R).
  - Test D and the assumptions row call the already-open setting change "as designed" (Q1).
  - Task 6 reports the build mode, the jank share and the worst frame, and stops before any optimisation (Q3).
  - The live gesture checks are supplementary, recorded as Not run (not reproducible) when a tool can't produce
    the gesture (Q4).

- **Re-checked against the code:**
  - `journey_map.dart`:
    - `InteractionOptions` at :191-193;
    - the `build` order (brightness at :139-145, `LayoutBuilder` at :176);
    - `_fittedCamera` / `_fitLatest` untouched;
    - the tile layer disposes the tile provider (flutter_map `tile_layer.dart:517`), so the plan never rebuilds
      `FlutterMap` on its own.
  - `journey_map_card.dart` (no key on `JourneyMap`; unchanged).
  - `motion.dart` (the `maybeDisableAnimationsOf` pattern).
  - `basemap.dart` (`OneMapTileProvider`, no `overrideFreshAge`).
  - `journey_map_card_test.dart`: the helpers `pumpApp`, `pickDestination`, `openMap`, `marker`, `app()`; the
    `geometry` fake with `loads`; `MapCamera.of(...MarkerLayer)` as in existing tests.
  - `test_app.dart`: the `mapTiles` factory; the fake MRT, bus and geometry defaults.
  - `support.dart`: `initIntegrationTest`, `searchAndPick`, `scrollToAndTap`, `pumpUntilFound`.
  - `test_driver/integration_test.dart`: `integrationDriver()`.
  - flutter_map 8.3.2:
    - `InteractiveFlag.all` includes `flingAnimation`;
    - the fling threshold is 800 px/s;
    - `late final _doubleTapController` takes its duration from the options;
    - flags are read per gesture;
    - `PositionedTapDetector2` uses 250 ms and 48 px;
    - scroll-wheel zoom uses `moveRaw`, not animated;
    - the caching code lines are cited.
  - The Flutter SDK:
    - `AnimationController` 5 % / ×200 (`animation_controller.dart:651`, `:785`);
    - `FakeAccessibilityFeatures` (`disableAnimations`, `reduceMotion`);
    - `FrameTimingSummarizer` exported by `flutter_test`, with p90/p99 by `((n-1)·p).round()`;
    - Android `AccessibilityBridge` `TRANSITION_ANIMATION_SCALE`; Web `prefers-reduced-motion` sets both flags.
- **No contradiction with P2-M1–M3:**
  - The camera is still fitted once per scene change, never animated, with no new fit trigger. The design
    deliberately avoids a map rebuild for this reason (Q1).
  - No tile is requested before "Show map"; the probe is a dev tool, not app behaviour.
  - `routes.min.json` behaviour and the selection are unchanged (test D asserts `loads == 1`).
  - The connectors, legend and summary are unchanged.
  - The dependency direction is unchanged.
- **No walking routing:**
  - no task adds a host, client, header or request to the app;
  - Task 1 only documents and re-reads public pages with curl;
  - Task 8 greps the code and audits the Web requests.
- **No duplicated work:**
  - the cache cap, a11y semantics, unanimated camera, integration tests and light/dark/2× smoke were done in
    P2-M1–M3;
  - P2-M4 only verifies them or re-runs them as the final regression (the table "Already done in P2-M1–M3");
  - no integration test changes.
- **Sequence refinements versus the user's outline:**
  - Task 0 (the plan PR, D7) is added before Task 1.
  - The release APK is built once, at the end of Task 2, and reused by Tasks 3, 7 and 8 while `lib/` is unchanged.
  - Task 6 restores the release build after its profile runs.
  - Task 9's docs-only commit follows the gates, as P2-M3 did; its cheap gates are re-run and recorded as
    "later commit docs-only".
- **Placeholders:** none. "(date)" in the docs text means the date the step runs, filled in at that time.
