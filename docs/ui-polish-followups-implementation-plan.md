# UI Polish Follow-ups Implementation Plan

> **Status (2026-10-05):** implemented by PR #48 (merged as `dfc2e8d`). Kept as the historical record: its
> checkboxes are the original execution instructions, not outstanding work.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** close the drift and evidence gaps that Phase 2 left in the UI polish of PR #35. That means
one theme-colour fix, one spacing fix, whole-app motion tests, a scroll-state diagnostic, accurate
docs, and the first live look at the 250 ms card animation. No data, rule, provider or map behaviour
changes.

**Architecture:** presentation, test and doc changes only. There are two production code edits, each a
few lines: the map-pin shadow takes `colorScheme.shadow`, and the journey option's 4 px spacer becomes
conditional. Everything else is code comments, tests (one new file, two new tests in existing files) and
documentation. No new dependency, provider, host or seam.

**Tech Stack:** Flutter 3.47.2 stable (Dart 3.13.2), Material 3, Riverpod 3, flutter_map 8.3.2,
`flutter_test`, `integration_test`.

**Spec:** the frozen decisions below (D1–D3, Q1–Q3, F1–F6, and the two known limitations), from the UI-polish
reconciliation and two approval rounds of 2026-10-04 on `main` @ `8c0ccf6`. Product rules come from `docs/singapore-smart-commute-implementation-guide.v2.md` (`§N`) and
`CLAUDE.md`. The historical plan `docs/ui-polish-implementation-plan.md` was implemented in full by PR #35
(`374a024`). It is context only: **do not re-apply its snippets.** They predate Phase 2 and would delete
`JourneyMapCard`, Select/Selected, the collapsed first step and the #25–#33 accessibility labels.

---

## Frozen decisions (from the review of the reconciliation)

- **D1, scope:** follow-ups only. No general redesign. Tasks 1–7 of the old plan stay as completed history.
- **D2, map Show/Hide:** stays **instant**. No `MotionSize` around `JourneyMapCard` (F6 is a decision with no
  code). Why: it's an explicit user action; the map is far heavier than the other cards; its tiles load as it
  appears; P2-M4 measured a high raster cost on the emulator; and cosmetic motion is no reason to reopen
  Phase 2 map behaviour.
- **D3, scroll disposal:** accepted as a **known presentation limitation** (KL1 below). No keep-alive, and no
  move of widget-local state into providers. The diagnostic stays **observational**. Stop and report only if it
  shows more than KL1: an invariant failing, or anything lost beyond open alternative steps and the map's manual
  pan or zoom.
- **F1:** `Colors.black38` → the `colorScheme.shadow` equivalent at the same opacity, plus a durable guard.
- **F2:** the 4 px spacer only when the option has a heading.
- **F3:** whole-app tests at the real `AppMotion.resize`, with mutation checks; plus the D3 diagnostic.
- **F4:** doc and comment corrections (theme, haptic, `MotionSize`, "Out of date", status wording, a
  historical note on the old plan, the D2 rationale).
- **F5:** observe the 250 ms animation live, preferably in **Chrome through CDP**. Android motion-by-eye may be
  logged **Not run** if the available tooling can't capture the transition reliably. Don't install `ffmpeg`, add a
  project dependency, or change the machine materially just to capture it. Never change code to ease automation.
- **Q1, plan location:** this plan is committed alone as `docs/ui-polish-followups-implementation-plan.md` through
  a **docs-only plan PR** (as for P2-M2, P2-M3 and P2-M4). `feat/ui-polish-followups` is created only after that PR
  is reviewed, merged and cleaned up.
- **Q2, TalkBack:** one normal attempt. Don't answer or change the Android Accessibility Suite notification
  permission to enable it, and **no `pm grant`**. If the prompt takes the input again, log TalkBack **Not run**
  with the precise reason. Restore and verify every setting changed. The widget and Web semantics evidence stands.
- **Q3, `CLAUDE.md`:** durable agent guidance only. Two updates: presentation colours come from the theme scheme,
  with the regression guard; and whole-app motion has real-duration coverage alongside the zero-duration test
  default. No test seam is introduced, so nothing else changes there.

## Known limitations (documented, not implementation tasks)

- **KL1, a deep scroll at 2× text (D3).** The home list is lazy and keeps no section alive. At 2× text, scrolling
  far enough down disposes the top section, and scrolling back recreates it. Two kinds of widget-local view
  state reset: an alternative's expanded steps (collapsed again), and the map's manually panned camera (back to
  its fitted view). What the app owns is unaffected: the selected option, the map left open, origin and
  destination; no bus or map data is loaded again, and there is no exception. This is **not** data loss or
  journey-state loss. Task 3 records it in `docs/assumptions.md`, and Task 1's diagnostic shows it. Nothing
  changes it.
- **KL2, a `MotionSize` entrance can settle at once.** When several asynchronous pieces of the journey card's
  content (the MRT suggestion, the plan, the arrivals) change on adjacent frames, Flutter's `AnimatedSize` settles
  directly to the later layout instead of playing the full entrance animation. An isolated change animates; Task 1
  tests that path at the real duration. Task 3 documents this (the `MotionSize` doc comment and the assumptions
  "Motion" row), and Task 5 reports what happens with real timing. Nothing changes it.

## Out of scope (explicitly)

- A `MotionSize` (or any animation) around `JourneyMapCard` (D2).
- Keep-alive (`AutomaticKeepAlive…`, `keepAlive`), moving widget-local state into providers, or any other
  state-ownership change (D3, KL1).
- A `MotionSize` redesign; coordinating or delaying plan, MRT or arrival timing; any new animation state machinery
  to force an entrance animation (KL2).
- Installing `ffmpeg` or other capture tools, a project dependency, or material machine changes for live capture
  (F5). Pre-granting or answering TalkBack's notification permission (Q2).
- A general redesign, and re-applying any snippet of `docs/ui-polish-implementation-plan.md` (D1).

## Planning evidence (gathered read-only, 2026-10-04)

All of this was measured in a **throwaway copy** of `main` @ `8c0ccf6` (`git archive` into the scratchpad; the
repository was not touched). The test code in Tasks 1–2 is the exact code that ran there.

- **The scheme's shadow is pure black in both themes** (`ColorScheme.fromSeed(teal)` `shadow` = alpha 1, RGB 0
  in light and dark). `Colors.black38` is alpha 0.3804; `shadow.withValues(alpha: 0.38)` is alpha 0.38. Both
  give 97/255 in 8-bit output: **the same pixels**.
- **No lint can enforce "colours only from the scheme".** `analysis_options.yaml` includes only
  `flutter_lints` (no such rule), and analyzer plugins (`custom_lint`, `analysis_server_plugin`) need a new
  dependency, which isn't allowed. So the guard is a narrow source scan, following the precedent of
  `test/web/content_security_policy_test.dart`. On `main` it finds exactly two hits: the seed
  (`lib/app/app.dart:22 Colors.teal`) and `lib/features/map/presentation/journey_map.dart:451 Colors.black38`.
- **How `AnimatedSize` really behaves** (`packages/flutter/lib/src/rendering/animated_size.dart:318-377`). When the
  child's size changes from a stable state, it animates from the **current** size. When it changes **again on the
  very next layout** after a change, the state machine goes `changed → unstable` and **jumps** to each new size
  until the size holds for one layout. So a later interruption continues smoothly (what `motion_test`'s
  "interrupt" case covers), but a burst of changes on consecutive frames lands at once.
- **The consequence in the whole app (measured):** the fakes resolve on consecutive frames (MRT → plan →
  arrivals), so at the real 250 ms the journey card's entrance **jumps**: heights 0 → 840 → 968 px in two frames.
  With every source held, the entrance is one change and unfolds smoothly (0, 34, 65, 92, … 188 px over about
  250 ms). "Show steps" animates (968 → 1030 px over about 120 ms), and "Hide steps" 100 ms later reverses from
  the current height (1025 → 1018 …) with no jump. Live, whether the entrance animates depends on timing (F5
  observes it). This is **accepted as a known limitation** (KL2): documented, not fixed.
- **D3 diagnostic, observed** (360 × 780 dp, with an alternative's steps open, that alternative selected, and
  the map open and panned 80 px):

  | Text | Top section disposed at the bottom | Steps still open | Map kept its state | Camera kept the pan | Selection / map open | Loads (bus, arrivals, geometry) |
  |---|---|---|---|---|---|---|
  | 1× | no | yes | yes | yes | kept | 1, 2, 1 → unchanged |
  | 2× | **yes** | **no** (collapsed) | **no** (rebuilt) | **no** (refitted) | kept | 1, 2, 1 → unchanged |

  The only things lost are widget-local view state: an open "Show steps", and the map's pan and zoom (it
  returns to the fitted journey view). Nothing is fetched again: only `rideLineProvider` is `autoDispose`, and it
  derives from the session-held geometry. **Accepted as a known presentation limitation** (D3, KL1).
- **Mutation checks, run:**
  - M1 (`MotionSize` never uses `AnimatedSize`) fails the entrance and rapid Show/Hide tests.
  - M2 (`MotionSize` ignores reduce motion) fails the reduce-motion test.
  - Restoring `Colors.black38` fails the guard; a `Color (0xFF000000)` in code fails it; a `// Colors.red` comment
    passes.
  - The old spacer makes the spacing test fail with 12 where 8 is expected.
- **Totals, measured:** with every change in this plan, `dart format` checks 133 files (0 changed), `flutter
  analyze` finds no issues, and `flutter test` passes **645/645** (638 on `main` + 7 new).

## Global Constraints

- No server-side component, no credentials, no secrets, **no new dependency**, no new network host, and no CSP
  change (`CLAUDE.md`, "Hard constraints").
- Presentation, tests and docs only. Don't change the planner, scoring, arrivals, walking estimates, MRT
  recommendation, option-selection ownership, map scene or data flow, route geometry, map loading or session
  rules, routing, providers, network hosts, or `pubspec.yaml` / `pubspec.lock`.
- Colours come from `Theme.of(context).colorScheme` only; the teal seed in `lib/app/app.dart` is the one fixed colour.
- Keep every widget `Key`, including P2-M3's `select-option-<N>` / `selected-option-<N>`, `show-map`,
  `hide-map` and `map-card`.
- Keep the P2-M3 behaviour: "Suggested" is option #1; selecting never reorders, re-plans or touches arrivals;
  the map follows the selection; "Selected" is a live region spoken "Bus N selected"; "Show steps for Bus N" /
  "Hide steps for Bus N" are spoken; a collapsed alternative still shows its walk to the boarding stop.
- Keep the P2-M4 behaviour: under reduced motion the map has no fling and an instant double-tap zoom; the map
  isn't rebuilt when the setting changes; the camera fit is unchanged.
- `MotionSize` wraps the route and journey cards only, once each, never nested; the map card stays instant (D2).
- Tests never call live APIs. Don't weaken any existing test (the `motion_test` cases, the P2-M3 selection group,
  the P2-M4 reduced-motion group, accessibility).
- Evidence rule: log every command and its real result in `docs/testing.md`'s run log; anything not run is
  logged **Not run** with the reason. Never reuse an earlier milestone's results.
- Git: this plan merges first, through its own docs-only PR (Q1). Then branch `feat/ui-polish-followups` from
  `origin/main`; small commits; never commit or push to `main`; no
  force-push. End every commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Host: long runs (`flutter test`, builds, `flutter drive`) go in the **foreground** with `timeout 590`; the host
  is often short of memory. Android device: **`emulator-5556`** (Pixel_8_Pro). `emulator-5554` belongs to another
  project; don't touch it. `adb` is `"$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"`. Ask before stopping any
  process.

## Review Focus

Five conditions most likely to bite a user that the main tests don't otherwise pin, each with the test that pins it:

1. **Reduce motion with the real duration in the whole app:** the card must land in one frame. Pinned by Task 1,
   "reduce motion: the journey card lands in one frame" (mutation M2).
2. **A quick "Hide steps" right after "Show steps":** the height reverses from where it is, with no jump either
   way. Pinned by Task 1's rapid Show/Hide test (mutation M1).
3. **A future hard-coded colour** (the P2-M1 kind of drift): pinned by Task 2's guard (G1–G3).
4. **2× text on a narrow phone after the spacing change:** pinned by the existing
   `journey_widget_test.dart` "dark theme, 2× text, 320 dp …" (re-run in Task 2), plus the new spacing test.
5. **A deep scroll at 2× text:** what the app owns survives and nothing is refetched. Pinned by Task 1's D3
   invariants; the local-state outcome is observed, not required.

---

## File map

| File | Change | Task |
|---|---|---|
| `docs/ui-polish-followups-implementation-plan.md` | Already on `main` (the docs-only plan PR, Q1); unchanged | — |
| `test/app/home_screen_test.dart` | **Create**: real-duration motion tests (3) and the D3 diagnostic (2) | 1 |
| `test/app/app_theme_test.dart` | Add the colour guard (1 test) and `import 'dart:io';` | 2 |
| `test/features/journey/journey_widget_test.dart` | Add the spacing test (1) | 2 |
| `lib/features/map/presentation/journey_map.dart` | `_MarkerPin` shadow → `scheme.shadow` (line 451) | 2 |
| `lib/features/journey/presentation/journey_card.dart` | Spacer only with a heading (lines 218–220) | 2 |
| `lib/core/ui/motion.dart` | Doc comment only (lines 16–21) | 3 |
| `lib/features/places/presentation/place_search_field.dart` | Comment only (line 80) | 3 |
| `lib/features/environment/presentation/environment_dashboard.dart` | Comment only (line 39) | 3 |
| `lib/core/config/app_config.dart` | Comment only (line 215) | 3 |
| `docs/assumptions.md` | Rows "Motion", "Theme", "Place search clear", "Dashboard refresh"; new row "Home list scrolling (D3)" | 3 |
| `docs/architecture.md` | New section "UI polish follow-ups (after Phase 2)" | 3 |
| `README.md` | Status lines 10 and 126 | 3 |
| `CLAUDE.md` | Testing: the colour rule and its guard; the motion seam sentence | 3 |
| `docs/ui-polish-implementation-plan.md` | A status note under the title only | 3 |
| `docs/testing.md` | Run-log rows (every task) and an open-items entry | 0–5 |

---

### Task 0: Baseline

**Precondition (Q1):** the docs-only plan PR that adds this file has been **reviewed, merged and cleaned up**
(its branch deleted locally and remotely). Don't start before then.

**Files:** `docs/testing.md` (one row).

- [ ] **Step 1: Check the starting point.**

  ```bash
  git fetch --prune origin
  git switch main && git merge --ff-only origin/main
  git status --porcelain                       # Expected: empty
  git log --oneline -1 -- docs/ui-polish-followups-implementation-plan.md   # Expected: the plan PR's commit
  git diff --stat 8c0ccf6 origin/main -- lib test integration_test tool web pubspec.yaml README.md CLAUDE.md
  ```

  Expected: the last command prints nothing. Since `8c0ccf6`, only the plan PR (this file plus one
  `docs/testing.md` row) should have landed. If it prints anything, read those changes. If one touches a file in the
  file map, **stop and report** before going on.

- [ ] **Step 2: Create the branch** (never edit on `main`):

  ```bash
  git switch -c feat/ui-polish-followups origin/main
  flutter pub get
  ```

- [ ] **Step 3: Run the baseline gates in the foreground**, saving the output to a scratch log:

  ```bash
  dart format --set-exit-if-changed .
  flutter analyze
  timeout 590 flutter test
  ```

  Expected: "Formatted 132 files (0 changed)", exit 0; "No issues found!"; "+638: All tests passed!". Use the
  real numbers from the output from here on. If anything fails before any change, stop and report it.

- [ ] **Step 4: Log the baseline.** In `docs/testing.md`, append one run-log row at the end of the table, with the
  real times and counts:

  ```markdown
  | 2026-10-0X | UI polish follow-ups T0: baseline on `feat/ui-polish-followups` from `origin/main` `<sha>` (plan merged as `docs/ui-polish-followups-implementation-plan.md`) | `dart format --set-exit-if-changed .`; `flutter analyze`; `flutter test` | Pass: 132 files, 0 changed; no issues; **638/638** |
  ```

- [ ] **Step 5: Commit.**

  ```bash
  git add docs/testing.md
  git commit -m "docs(testing): UI polish follow-ups baseline" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 1: Motion evidence: the real duration, and the scroll diagnostic (F3, D3)

**Files:**
- Create: `test/app/home_screen_test.dart`
- Modify (temporarily, for the mutation checks only; restored before the commit): `lib/core/ui/motion.dart`

**Interfaces:**
- Consumes: `buildTestApp(motionDuration:, routeGeometry:, mrt:, busArrivals:, busNetwork:)`
  (`integration_test/fakes/test_app.dart`); `FakeBusNetworkRepository.hold()/release()/loads`;
  `FakeBusArrivalRepository.hold(stop)/release(stop)/totalCalls`; `FakeRouteGeometryRepository.loads`;
  `MrtAssetRepository({Future<String> Function()? load})`; `encodeMrtStations` (`lib/features/journey/data/mrt_asset.dart`);
  `fakeMrtStations`; `AppMotion.resize`; `MotionSize`.
- Produces: nothing used by later tasks. Task 3 cites the D3 result.

The three motion tests guard behaviour that already exists, so they pass the first time they run. Their proof is the
mutation checks (Step 3), which must make them fail. The D3 tests are a diagnostic: they assert only what must hold
either way, and they **print** what happened to the top section's widget state.

- [ ] **Step 1: Write `test/app/home_screen_test.dart`:**

  ```dart
  // UI polish follow-ups: the home screen at the real card-resize duration, and
  // what scrolling far down does to the top section (diagnostic D3). Every
  // external provider is a fake (integration_test/fakes/).
  import 'dart:async';
  import 'dart:convert';

  import 'package:flutter/material.dart';
  import 'package:flutter_map/flutter_map.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sg_smart_commute/core/config/app_config.dart';
  import 'package:sg_smart_commute/core/geo/geo.dart';
  import 'package:sg_smart_commute/core/location/location_service.dart';
  import 'package:sg_smart_commute/core/ui/motion.dart';
  import 'package:sg_smart_commute/features/journey/data/mrt_asset.dart';
  import 'package:sg_smart_commute/features/journey/data/mrt_asset_repository.dart';

  import '../../integration_test/fakes/fake_bus_arrival_repository.dart';
  import '../../integration_test/fakes/fake_bus_network.dart';
  import '../../integration_test/fakes/fake_environment_repository.dart';
  import '../../integration_test/fakes/fake_location_service.dart';
  import '../../integration_test/fakes/fake_place_search_repository.dart';
  import '../../integration_test/fakes/fake_route_geometry.dart';
  import '../../integration_test/fakes/test_app.dart';

  const bishan = LatLng(1.3508, 103.8485);
  const destinationField = Key('destination-field');
  const journeyCard = Key('journey-card');
  const alternative = Key('journey-alternative-1');

  void main() {
    late FakeBusNetworkRepository bus;
    late FakeBusArrivalRepository arrivals;
    late FakeRouteGeometryRepository geometry;
    late Completer<void> mrtGate;

    setUp(() {
      bus = FakeBusNetworkRepository();
      arrivals = FakeBusArrivalRepository();
      geometry = FakeRouteGeometryRepository();
      mrtGate = Completer<void>()..complete(); // open unless a test holds it
    });

    /// The real app at Bishan by GPS. [motion] is the card-resize duration;
    /// buildTestApp's default is zero.
    Widget app({Duration motion = Duration.zero}) => buildTestApp(
      location: FakeLocationService(
        access: LocationAccess.granted,
        position: bishan,
      ),
      environment: FakeEnvironmentRepository(),
      places: FakePlaceSearchRepository(),
      busNetwork: bus,
      busArrivals: arrivals,
      routeGeometry: geometry,
      // The fake MRT asset, behind a gate the motion tests can hold.
      mrt: MrtAssetRepository(
        load: () async {
          await mrtGate.future;
          return jsonEncode({'stations': encodeMrtStations(fakeMrtStations)});
        },
      ),
      motionDuration: motion,
    );

    /// Types VivoCity and picks it. The route card resizes when the results
    /// appear, so [settle] lets that finish before the tap.
    Future<void> pickVivoCity(
      WidgetTester tester, {
      Duration settle = Duration.zero,
    }) async {
      await tester.enterText(find.byKey(destinationField), 'VivoCity');
      await tester.pump(const Duration(milliseconds: 400)); // search debounce
      await tester.pump();
      await tester.pump(settle);
      await tester.tap(find.text('VIVOCITY'));
      await tester.pump();
    }

    Finder inAlternative(String text) =>
        find.descendant(of: find.byKey(alternative), matching: find.text(text));

    group('motion at the real duration (AppMotion.resize)', () {
      /// The journey card's height as the user sees it (its MotionSize) and
      /// its full height.
      double shown(WidgetTester tester) => tester
          .getSize(
            find.ancestor(
              of: find.byKey(journeyCard),
              matching: find.byType(MotionSize),
            ),
          )
          .height;
      double full(WidgetTester tester) =>
          tester.getSize(find.byKey(journeyCard)).height;

      Future<void> pumpTall(WidgetTester tester, Widget widget) async {
        tester.view.physicalSize = const Size(1080, 5000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(widget);
        await tester.pump();
      }

      /// Holds every journey source, so the card's entrance is one change
      /// (nothing → its loading rows). Data landing on the very next frame
      /// would make AnimatedSize jump instead (docs/assumptions.md, "Motion").
      void holdJourneyData() {
        bus.hold();
        arrivals
          ..hold('BSH1')
          ..hold('BSH2');
        mrtGate = Completer<void>();
      }

      void releaseJourneyData() {
        bus.release();
        mrtGate.complete();
        arrivals
          ..release('BSH1')
          ..release('BSH2');
      }

      testWidgets('the journey card unfolds over AppMotion.resize, then is '
          'usable', (tester) async {
        holdJourneyData();
        await pumpTall(tester, app(motion: AppMotion.resize));
        await pickVivoCity(tester, settle: AppMotion.resize);

        await tester.pump(AppMotion.resize ~/ 2);
        expect(shown(tester), greaterThan(0));
        expect(shown(tester), lessThan(full(tester))); // still unfolding
        await tester.pump(AppMotion.resize ~/ 2);
        expect(shown(tester), full(tester));

        releaseJourneyData();
        await tester.pump();
        await tester.pump();
        await tester.pump(AppMotion.resize);
        expect(shown(tester), full(tester));

        await tester.tap(inAlternative('Show steps'));
        await tester.pump();
        await tester.pump(AppMotion.resize);
        expect(inAlternative('Hide steps'), findsOneWidget);
        await tester.tap(find.byKey(const Key('select-option-F10')));
        await tester.pump();
        await tester.pump(AppMotion.resize);
        expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
        expect(shown(tester), full(tester));
        expect(tester.takeException(), isNull);
      });

      testWidgets('reduce motion: the journey card lands in one frame', (
        tester,
      ) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        holdJourneyData();
        await pumpTall(tester, app(motion: AppMotion.resize));
        await pickVivoCity(tester);

        expect(shown(tester), greaterThan(0));
        expect(shown(tester), full(tester));
        releaseJourneyData();
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('"Hide steps" right after "Show steps" reverses from the '
          'current height, with no jump', (tester) async {
        await pumpTall(tester, app(motion: AppMotion.resize));
        await pickVivoCity(tester, settle: AppMotion.resize);
        // Let the data land and the card settle: one pump is one frame, and a
        // change on the frame after another one jumps instead of animating.
        for (var i = 0; i < 4; i++) {
          await tester.pump(AppMotion.resize);
        }
        final closed = shown(tester);
        expect(closed, full(tester)); // settled

        await tester.tap(inAlternative('Show steps'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        final opening = shown(tester);
        expect(opening, greaterThan(closed));
        expect(opening, lessThan(full(tester))); // still opening

        await tester.tap(inAlternative('Hide steps'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(shown(tester), lessThanOrEqualTo(opening)); // no jump open
        expect(shown(tester), greaterThan(closed)); // no jump shut
        await tester.pump(AppMotion.resize);
        expect(shown(tester), closed);
        expect(tester.takeException(), isNull);
      });
    });

    group('scrolling to the bottom and back (diagnostic D3)', () {
      for (final scale in [1.0, 2.0]) {
        testWidgets('360 × 780 dp at $scale× text: what the top section '
            'keeps', (tester) async {
          tester.view.physicalSize = const Size(360, 780);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(app());
          await tester.pump();
          await pickVivoCity(tester);
          await tester.pump();

          Future<void> tapVisible(Finder finder) async {
            await tester.ensureVisible(finder);
            await tester.pump();
            await tester.tap(finder);
            await tester.pump();
            await tester.pump();
          }

          // The user's own state in the top section: an alternative's steps
          // open, that alternative selected, the map open and panned.
          await tapVisible(inAlternative('Show steps'));
          await tapVisible(find.byKey(const Key('select-option-F10')));
          await tapVisible(find.byKey(const Key('show-map')));
          await tester.ensureVisible(find.byType(FlutterMap));
          await tester.pump();
          MapCamera camera() =>
              MapCamera.of(tester.element(find.byType(MarkerLayer)));
          await tester.timedDrag(
            find.byType(FlutterMap),
            const Offset(-80, 0),
            const Duration(milliseconds: 600),
          );
          await tester.pump(const Duration(seconds: 1));
          final panned = camera().center;
          final map = tester.state(find.byType(FlutterMap));
          final loads = (
            bus: bus.loads,
            arrivals: arrivals.totalCalls,
            geometry: geometry.loads,
          );

          final list = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          list.jumpTo(list.maxScrollExtent);
          await tester.pump();
          final disposed = find
              .byKey(journeyCard, skipOffstage: false)
              .evaluate()
              .isEmpty;
          list.jumpTo(0);
          await tester.pump();
          await tester.pump();

          // Must hold either way: what the app owns survives, and nothing is
          // fetched again (once-per-session loads, one arrivals request per
          // shown stop).
          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('selected-option-F10'), skipOffstage: false),
            findsOneWidget,
          );
          expect(
            find.byKey(const Key('map-card'), skipOffstage: false),
            findsOneWidget,
          );
          expect((
            bus: bus.loads,
            arrivals: arrivals.totalCalls,
            geometry: geometry.loads,
          ), loads);

          // What the widgets kept: observed, not required. D3: no keep-alive
          // change without a separate decision (docs/assumptions.md, "Home
          // list scrolling").
          await tester.ensureVisible(find.byType(FlutterMap));
          await tester.pump();
          final stepsOpen = find
              .text('Hide steps', skipOffstage: false)
              .evaluate()
              .isNotEmpty;
          debugPrint(
            'D3 $scale× text: top section disposed at the bottom: $disposed; '
            'steps still open: $stepsOpen; map kept its state: '
            '${identical(map, tester.state(find.byType(FlutterMap)))}; '
            'camera kept the pan: ${camera().center == panned}',
          );
        });
      }
    });
  }
  ```

- [ ] **Step 2: Run it.**

  Run: `dart format test/app/home_screen_test.dart && timeout 590 flutter test test/app/home_screen_test.dart`
  Expected: `+5: All tests passed!`, with these two printed lines:
  ```text
  D3 1.0× text: top section disposed at the bottom: false; steps still open: true; map kept its state: true; camera kept the pan: true
  D3 2.0× text: top section disposed at the bottom: true; steps still open: false; map kept its state: false; camera kept the pan: false
  ```
  - If a D3 **invariant** fails (an exception, the selection or the open map lost, or any load count changed): that's
    a real defect. **Stop and report** with the output; don't change the test or the app.
  - If the printed observations differ from the lines above: record what you see. If it shows *more* than the
    accepted limitation KL1 (anything beyond open alternative steps and the map's manual pan or zoom resetting),
    **stop and report**. Never add keep-alive or move state to make it pass.

- [ ] **Step 3: Mutation checks** (temporary edits to `lib/core/ui/motion.dart`, restored afterwards):

  - **M1, no animated path.** Replace `if (duration == Duration.zero) return child;` with `return child;`.
    Run: `timeout 590 flutter test test/app/home_screen_test.dart --plain-name "motion at the real duration"`
    Expected: **2 failures**, "the journey card unfolds over AppMotion.resize, then is usable" and "\"Hide steps\"
    right after \"Show steps\" …"; the reduce-motion test still passes. Then `git checkout -- lib/core/ui/motion.dart`.
  - **M2, reduce motion ignored.** Replace
    `final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;` with `const reduceMotion = false;`.
    Run: `timeout 590 flutter test test/app/home_screen_test.dart --plain-name "reduce motion"`
    Expected: **1 failure**, "reduce motion: the journey card lands in one frame". Then
    `git checkout -- lib/core/ui/motion.dart`.
  - Then `git diff --quiet -- lib` must succeed (exit 0): `lib/` is untouched.
  - Also confirm the existing isolated tests are untouched and green:
    `timeout 590 flutter test test/core/motion_test.dart` → `+5: All tests passed!`.

- [ ] **Step 4: Full suite.** `timeout 590 flutter test` → **643/643** (638 + 5). Then `flutter analyze` → no issues.

- [ ] **Step 5: Log and commit.** Append run-log rows to `docs/testing.md`. One row covers the new file, its run,
  M1, M2 and the suite count. One row is the D3 diagnostic with both printed lines verbatim and this sentence:
  "Observational: invariants asserted (no exception, selection and open map kept, bus/arrivals/geometry loads
  unchanged); widget-local state reported, not required (D3)."

  ```bash
  git add test/app/home_screen_test.dart docs/testing.md
  git commit -m "test(app): home screen motion at the real duration; D3 scroll diagnostic" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 2: Small presentation drift (F1, F2)

**Files:**
- Modify: `test/app/app_theme_test.dart` (guard), `test/features/journey/journey_widget_test.dart` (spacing test)
- Modify: `lib/features/map/presentation/journey_map.dart` (`_MarkerPin`), `lib/features/journey/presentation/journey_card.dart` (`_OptionState.build`)

**Interfaces:** none produced or consumed; private widgets only.

- [ ] **Step 1: Write the failing guard.** In `test/app/app_theme_test.dart`, add `import 'dart:io';` as the first
  import (followed by a blank line), and add this test at the end of `main()`:

  ```dart
    test('lib/ takes its colours from the theme scheme; the teal seed is the '
        'one fixed colour', () {
      // Colors.x, Color(…) and Color.from…(…) in code; text after `//` is
      // dropped as a comment. ponytail: a line scan, not a Dart parser — `//`
      // inside a string hides the rest of that line, and a /* block */ comment
      // is scanned. Add a parser only if that ever misleads.
      final fixed = RegExp(r'Colors\s*\.\s*\w+|\bColor\s*(?:\.\s*from\w*\s*)?\(');
      final found = <String>[];
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final code = file
            .readAsLinesSync()
            .map((line) => line.split('//').first)
            .join('\n');
        final path = file.path.replaceAll(r'\', '/');
        for (final m in fixed.allMatches(code)) {
          final line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
          found.add('$path:$line ${m[0]}');
        }
      }
      final seed = RegExp(r'^lib/app/app\.dart:\d+ Colors\.teal$');
      expect(found.where(seed.hasMatch), hasLength(1), reason: 'the seed');
      expect(
        found.where((f) => !seed.hasMatch(f)),
        isEmpty,
        reason: 'take colours from Theme.of(context).colorScheme',
      );
    });
  ```

  The regex tolerates whitespace and line breaks between tokens because it runs over the joined file. It doesn't
  match `ColorScheme`, `Color.lerp`, `Color?` or `color:`.

- [ ] **Step 2: See it fail.**
  Run: `timeout 590 flutter test test/app/app_theme_test.dart --plain-name "fixed colour"`
  Expected: FAIL, `Actual: … ['lib/features/map/presentation/journey_map.dart:451 Colors.black38']`.

- [ ] **Step 3: F1 fix.** In `lib/features/map/presentation/journey_map.dart`, `_MarkerPin.build` (`scheme` is
  already defined there), replace

  ```dart
            boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
  ```

  with

  ```dart
            boxShadow: [
              BoxShadow(
                blurRadius: 3,
                color: scheme.shadow.withValues(alpha: 0.38),
              ),
            ],
  ```

  The pixels are identical: `shadow` is black in both themes, and 0.38 and 0.3804 both give alpha 97/255.

- [ ] **Step 4: See it pass, then check the guard against three cases** (temporary, restored with `git checkout`):
  - Run the guard: PASS.
  - **G1:** put `Colors.black38` back → FAIL naming `journey_map.dart`. Restore.
  - **G2:** append the line `// Colors.red in a comment is ignored.` to `lib/app/app_logo.dart` → PASS. Restore.
  - **G3:** append `const _probe = Color (0xFF000000);` to `lib/app/app_logo.dart` → FAIL naming
    `lib/app/app_logo.dart:<line> Color (`. Restore.
  - Then confirm `git diff --stat -- lib` shows only `journey_map.dart`.

- [ ] **Step 5: Write the failing spacing test.** In `test/features/journey/journey_widget_test.dart`, directly
  after the test `'each option leads with a service badge'`:

  ```dart
    testWidgets('only an option with a heading has a gap above its summary', (
      tester,
    ) async {
      await pumpApp(tester, gpsApp());
      await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
      await tester.pump();
      await tester.pump();
      double top(Finder f) => tester.getTopLeft(f).dy;
      Finder summary(String option) => find.descendant(
        of: find.byKey(Key(option)),
        matching: find.textContaining('Take Bus'),
      );
      // An alternative has no heading: its summary starts right under the
      // option's 8 px top padding.
      expect(
        top(summary('journey-alternative-1')) -
            top(find.byKey(const Key('journey-alternative-1'))),
        8,
      );
      // The suggestion keeps 4 px between "Suggested" and its summary.
      expect(
        top(summary('journey-suggested')) -
            tester.getBottomLeft(inKey('journey-suggested', 'Suggested')).dy,
        4,
      );
    });
  ```

- [ ] **Step 6: See it fail.**
  Run: `timeout 590 flutter test test/features/journey/journey_widget_test.dart --plain-name "gap above its summary"`
  Expected: FAIL, `Expected: <8>  Actual: <12.0>`.

- [ ] **Step 7: F2 fix.** In `lib/features/journey/presentation/journey_card.dart`, `_OptionState.build`, replace

  ```dart
            if (widget.heading != null)
              Text(widget.heading!, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
  ```

  with

  ```dart
            if (widget.heading != null) ...[
              Text(widget.heading!, style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
            ],
  ```

  Nothing else in `_Option` changes: not `_SelectControl`, the `Wrap`, the toggle or `_Steps`.

- [ ] **Step 8: Run the affected suites, then everything.**
  - `timeout 590 flutter test test/features/journey/ test/features/map/ test/app/ test/features/bus_arrival/` → all
    pass. This includes the P2-M3 selection group, the P2-M4 reduced-motion group, "dark theme, 2× text, 320 dp …"
    and "2× text at 360 dp: no overflow".
  - Then `dart format --set-exit-if-changed .` → 133 files, 0 changed; `flutter analyze` → no issues;
    `timeout 590 flutter test` → **645/645**.

- [ ] **Step 9: Log and commit** (two commits, one per fix, so each can be reverted alone). Add run-log rows with
  the RED/GREEN output, G1–G3 and the suite count.

  ```bash
  git add test/app/app_theme_test.dart lib/features/map/presentation/journey_map.dart
  git commit -m "fix(map): pin shadow from the colour scheme; guard lib/ against fixed colours" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  git add test/features/journey/journey_widget_test.dart lib/features/journey/presentation/journey_card.dart docs/testing.md
  git commit -m "fix(journey): no gap above an option's summary without a heading" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 3: Documentation and comment corrections (F4, F6)

**Files:** `lib/core/ui/motion.dart`, `lib/features/places/presentation/place_search_field.dart`,
`lib/features/environment/presentation/environment_dashboard.dart`, `lib/core/config/app_config.dart` (comments
only), `docs/assumptions.md`, `docs/architecture.md`, `README.md`, `CLAUDE.md`,
`docs/ui-polish-implementation-plan.md` (note only), `docs/testing.md`.

Leave alone: `StaleAfter`, `isStale` and the `stale:` parameters (code names for the §6.3 staleness concept, not UI
text); the assumptions row "Stale arrival answers" (a different concept); `docs/architecture.md:336` (an accurate
history of P2-M4's scope); and the body of `docs/ui-polish-implementation-plan.md`.

- [ ] **Step 1: `lib/core/ui/motion.dart`, doc comment of `MotionSize`.** Replace

  ```dart
  /// Animates [child]'s height when its content changes, from the top edge, so
  /// new content unfolds below what caused it and collapses back the same way.
  /// A change mid-animation continues from the current on-screen size. With
  /// the system's reduce-motion setting on, changes are instant.
  ```

  with

  ```dart
  /// Animates [child]'s height when its content changes, from the top edge, so
  /// new content unfolds below what caused it and collapses back the same way.
  /// A later change mid-animation continues from the current on-screen size,
  /// but content that changes again on the very next layout (data landing on
  /// consecutive frames) makes [AnimatedSize] jump to each new size until it
  /// holds for a frame, so such a burst lands at once. With the system's
  /// reduce-motion setting on, changes are instant.
  ```

- [ ] **Step 2: Three comments** (each line stays within 80 characters, so `dart format` changes no code layout;
  checked in the scratch copy):
  - `place_search_field.dart:80`, replace the one line
    `    // Confirms the commit moment only; a no-op on Web.` with:

    ```dart
        // Confirms the commit moment only. On Web: a 10 ms vibration where the
        // browser has the Vibration API (e.g. Chrome on Android), else nothing.
    ```

  - `environment_dashboard.dart:39`, replace
    `    ref.watch(uiTickProvider); // recompute ages, Stale and UV night over time` with:

    ```dart
        ref.watch(uiTickProvider); // recompute ages, "Out of date", UV night
    ```

  - `app_config.dart:215-216`, replace

    ```dart
      /// ("N min ago", Stale, the UV night rule, bus ETAs). A UI-only rebuild: it
      /// never sends a request, so there is still no automatic polling.
    ```

    with

    ```dart
      /// ("N min ago", "Out of date", the UV night rule, bus ETAs). A UI-only
      /// rebuild: it never sends a request, so there is still no automatic
      /// polling.
    ```

- [ ] **Step 3: `docs/assumptions.md`.**
  - **Motion** row, Assumption cell. Replace the sentence
    `a change mid-animation continues from the current size.` with:
    `a later change mid-animation continues from the current size. **Known limitation:** when several pieces of the journey card's content (the MRT suggestion, the plan, the arrivals) change on adjacent frames, \`AnimatedSize\` settles directly to the later layout instead of playing the full entrance animation (always with the test fakes; live it depends on timing). An isolated change animates, and is tested at the real duration in \`test/app/home_screen_test.dart\`. Not fixed: no \`MotionSize\` redesign, and no coordinating or delaying of data (UI polish follow-ups, KL2).`
    After `One \`MotionSize\` per card, never nested.` add:
    `The map card's Show/Hide is instant (no \`MotionSize\`): an explicit action on a much heavier card whose tiles load as it appears, with P2-M4's emulator raster cost already high (UI polish follow-ups, D2).`
  - **Theme** row: `Colours come only from the scheme` →
    `Colours come only from the scheme (the map pins' shadow is \`colorScheme.shadow\` at 38 % opacity); \`test/app/app_theme_test.dart\` scans \`lib/\` and allows only the seed`.
  - **Place search clear** row: `Choosing a result gives one selection haptic (a no-op on Web)` →
    `Choosing a result gives one selection haptic (Android: \`performHapticFeedback(CLOCK_TICK)\`; Web: a 10 ms vibration in browsers with the Vibration API, e.g. Chrome on Android, nothing elsewhere)`.
  - **Dashboard refresh** row: `the Stale marker still follows` → `the Out-of-date marker still follows`.
  - **New last row** (after "MRT markers (P2-M3)"). Write it from the Task 1 output; if that matched the planning
    evidence, it reads:

    ```markdown
    | Home list scrolling (D3) | **Known presentation limitation.** The home list is lazy and keeps no section alive. At 2× text (observed at 360 × 780 dp), scrolling to the bottom of Conditions disposes the top section, and scrolling back recreates it. Two kinds of widget-local view state reset: an alternative's expanded steps (collapsed again), and the map's manually panned camera (back to its fitted view). The selected option, the map left open, origin and destination are unaffected; no bus or map data is loaded again; no exception. At 1× text nothing is disposed. Not changed: no keep-alive, and no move of this widget-local state into providers | — | UI polish follow-ups (D3, KL1); diagnostic in `test/app/home_screen_test.dart` |
    ```

- [ ] **Step 4: `docs/architecture.md`.** Insert this section after the "Phase 2 Milestone 4 (hardening) and Phase 2
  close-out" section, before "## Dev tools (M0)":

  ```markdown
  ## UI polish follow-ups (after Phase 2)

  `docs/ui-polish-implementation-plan.md` was implemented by PR #35, before Phase 2. This closes the drift and
  evidence gaps Phase 2 left (`docs/ui-polish-followups-implementation-plan.md`): presentation, tests and docs only.

  - **Colours:** only from the theme scheme. The map pins' shadow, added in P2-M1 as a fixed colour, uses
    `colorScheme.shadow`. `test/app/app_theme_test.dart` scans `lib/`, and the teal seed is the one fixed colour.
  - **Motion:** `MotionSize` as documented. Known limitation: content changing on adjacent frames settles directly
    to the later layout. Whole-app tests at the real 250 ms are in `test/app/home_screen_test.dart`. The map card's
    Show/Hide stays instant (D2).
  - **Home list:** lazy, with no keep-alive. Known presentation limitation: at 2× text, a deep scroll resets open
    alternative steps and a panned map's camera; the selection, the open map and the data are unaffected
    (assumptions, "Home list scrolling (D3)").
  ```

- [ ] **Step 5: `README.md`.**
  - Line 10: `walking estimates and the MRT suggestions. UI polish continues separately.` →
    `walking estimates and the MRT suggestions. UI polish is complete (PR #35, plus follow-ups after Phase 2).`
  - Line 126: `markers → P2-M4 hardening): **complete**. UI polish continues separately.` →
    `markers → P2-M4 hardening): **complete**. UI polish: **complete** (PR #35, plus follow-ups after Phase 2).`

- [ ] **Step 6: `CLAUDE.md`** (Q3: durable agent guidance only. It has no "UI polish continues" wording, and none
  is added. No test seam is introduced: the new tests use existing ones, `buildTestApp(motionDuration:)`, the
  fakes' `hold`/`release`, and `MrtAssetRepository(load:)`).
  - In Testing, `` `test/core/motion_test.dart` covers the animated path) `` →
    `` `test/core/motion_test.dart` covers the animated path and `test/app/home_screen_test.dart` the whole app at the real duration) ``.
  - After the bullet "A new provider host must be added to the CSP …", add:
    `- Presentation colours come only from \`Theme.of(context).colorScheme\`; the teal seed in \`lib/app/app.dart\` is the one fixed colour (\`test/app/app_theme_test.dart\` scans \`lib/\`).`

- [ ] **Step 7: `docs/ui-polish-implementation-plan.md`, status note only.** Directly under the title line, insert:

  ```markdown
  > **Status (2026-10-04):** implemented in full by PR #35 (merged as `374a024` on 2026-10-02), before Phase 2. Kept
  > as the historical record. Its snippets predate Phase 2 and must not be re-applied. The drift and evidence gaps
  > found after Phase 2 are closed by `docs/ui-polish-followups-implementation-plan.md`.
  ```

  Change nothing else in that file.

- [ ] **Step 8: Check.** `dart format --set-exit-if-changed .`; `flutter analyze`; `timeout 590 flutter test` →
  645/645. Then `git diff --stat` must list only the files named in this task, and
  `git diff -U0 -- lib | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-]\s*//'` must print exactly two lines: the old and new
  `ref.watch(uiTickProvider); // recompute …` (the same code; only the trailing comment differs). Every `lib/`
  change in this task is a comment. Append a run-log row and commit:

  ```bash
  git add lib/core/ui/motion.dart lib/features/places/presentation/place_search_field.dart \
    lib/features/environment/presentation/environment_dashboard.dart lib/core/config/app_config.dart \
    docs/assumptions.md docs/architecture.md README.md CLAUDE.md docs/ui-polish-implementation-plan.md docs/testing.md
  git commit -m "docs: correct motion, haptic, colour and status wording; record D2 and D3" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
  ```

---

### Task 4: Full verification

**Files:** `docs/testing.md` (run-log rows only).

- [ ] **Step 1: Scope check.** Each command should give the stated result:

  ```bash
  git diff --name-only origin/main...HEAD -- pubspec.yaml pubspec.lock web/ integration_test/ \
    'lib/features/*/domain' 'lib/features/*/data' 'lib/features/*/*_providers.dart' lib/core/http lib/core/location
  # Expected: nothing.
  git diff -U0 origin/main...HEAD -- lib | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-]\s*//'
  # Expected: only the journey_map.dart shadow lines, the journey_card.dart spacer lines, and the
  # old/new `ref.watch(uiTickProvider); // …` pair (the same code; only the comment changes).
  git grep -n -i -E 'routing\.openstreetmap|valhalla|project-osrm|brouter|routingsvc' -- lib web test integration_test pubspec.yaml
  # Expected: nothing.
  git diff --name-only origin/main...HEAD -- lib/app/home_screen.dart lib/app/route_card.dart lib/features/map/presentation/journey_map_card.dart
  # Expected: nothing (no MotionSize around the map card, no layout change; D2).
  git grep -n -E 'AutomaticKeepAlive|wantKeepAlive|keepAlive' -- lib
  # Expected: nothing (no keep-alive or state-ownership change; D3).
  git diff -U0 origin/main...HEAD -- lib/core/ui/motion.dart | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -vE '^[+-]\s*//'
  # Expected: nothing (motion.dart: doc comment only; no MotionSize redesign; KL2).
  ```

- [ ] **Step 2: Gates** (foreground, `timeout 590` on each long one; record the real start and end times):

  ```bash
  dart format --set-exit-if-changed .     # 133 files, 0 changed
  flutter analyze                         # No issues found!
  timeout 590 flutter test                # 645/645, including the P2-M3 selection and P2-M4 reduced-motion groups
  timeout 590 flutter build web --release
  timeout 590 flutter build apk --debug
  timeout 590 flutter build apk --release # record size and SHA-1
  ```

- [ ] **Step 3: Android integration**, on `emulator-5556` only:
  - Check it first: `adb devices`; `adb -s emulator-5556 shell getprop sys.boot_completed` → `1`; and
    `adb -s emulator-5556 shell service check package` → found.
  - Run `timeout 590 flutter test integration_test -d emulator-5556`. Expected: 3 files, 5 tests pass.
  - If one file fails to load or install because of the emulator (adb daemon, package service): run that file
    alone **once**. If it fails again, **ask before** any reboot or process stop, as in P2-M4. Never change a test or
    the app to work around an emulator failure; log it **Not run** with the error.

- [ ] **Step 4: Web integration**, one file per run:
  - Check that chromedriver's major.minor.build matches Chrome's, then start it on port 4444 with
    `--enable-chrome-logs`.
  - Then for each of `app_boot_test.dart`, `happy_path_test.dart` and `fallback_path_test.dart`:
    `timeout 590 flutter drive --driver=test_driver/integration_test.dart --target=integration_test/<file> -d web-server --browser-name=chrome --profile`.
  - Expected: "All tests passed." for each; 0 CSP violations and 0 SEVERE in the Chrome log.
  - Afterwards, list any `adb logcat` or `chromedriver` processes these runs left. Stop only ones confirmed to be
    this task's, and ask first.

- [ ] **Step 5: Log and commit.** One run-log row per step, with real results; anything not run gets **Not run** and
  the reason. Commit `docs/testing.md` with message `docs(testing): UI polish follow-ups gates` plus the trailer.

---

### Task 5: Live checks (F5 and the Phase 2 regressions)

**Files:** `docs/testing.md` (run-log rows, plus one open-items entry). Scratch tools live **outside the repo** (the
session scratchpad). No app change for automation's sake.

The release web build comes from Task 4. Serve it with `python -m http.server 8773 --bind 127.0.0.1 --directory build/web`.
Live providers are used (NEA, OneMap search and tiles, busrouter, ArriveLah).

- [ ] **Step 1: Web session setup** (the P2-M4 recipe):
  - Headless Chrome through chromedriver.
  - GPS overridden to Bishan with CDP `Emulation.setGeolocationOverride`, after granting geolocation.
  - **Normal motion:** this machine's OS reports `prefers-reduced-motion: reduce`, so emulate `no-preference`
    with CDP `Emulation.setEmulatedMedia` **before** loading the page. Check `matchMedia('(prefers-reduced-motion:
    reduce)').matches === false` in the page.
  - Narrow screen: CDP `Emulation.setDeviceMetricsOverride` (width 360).
  - 2× text: Chrome pref `webkit.webprefs.default_font_size` = 32.
  - Typing: a real pointer tap on the field plus key actions. Labels: read from `flt-semantics`.

- [ ] **Step 2: Capture the motion (F5)**, in light mode, at normal motion and a wide window:
  - **Primary method:** a CDP screencast. Read Chrome's `debuggerAddress` from the session capabilities, open the
    page's DevTools websocket with a small stdlib websocket client in the scratchpad, send `Page.startScreencast`
    (`format: png`, `everyNthFrame: 1`), and save each `Page.screencastFrame` with its `metadata.timestamp`
    (acknowledging each frame).
  - **Fallback:** repeated `Page.captureScreenshot` through chromedriver's `goog/cdp/execute` for 400 ms.
  - Triggers:
    1. **Journey-card appearance:** pick a destination.
    2. **"Show steps"** on an alternative, once the data has settled.
    3. **"Hide steps" about 100 ms after "Show steps":** two pointer taps on the same toggle 100 ms apart.
  - For each trigger, record the number of frames, and their timestamps, from the trigger to 400 ms after it.
    Look at the frames at about 0, 60, 120 and 250 ms (open the PNGs).
  - **Animated** means a partly revealed card in at least one frame, settling over roughly 250 ms; for trigger 3, a
    reversal with no frame that jumps fully open or fully shut.
  - For the appearance, record **what is seen**. With live timing it may animate or land at once (the burst
    behaviour in Planning evidence); both are acceptable, and the run log states which.
  - Repeat in **dark** (`prefers-color-scheme: dark`) for trigger 2.
  - Repeat with **`prefers-reduced-motion: reduce`** for triggers 1 and 2. Expected: the change lands in one frame.
  - **Not run rule:** if neither method yields at least 2 frames inside a 250 ms window, log that specific check as
    **Not run (capture tooling)** with what was tried.

- [ ] **Step 3: Web regressions** (resource timing for request counts):
  - 0 tiles and 0 `routes.min.json` before "Show map"; tiles and exactly 1 `routes.min.json` after.
  - The map card appears and disappears **at once** on Show/Hide map: at full height in the first frame after the tap, gone in the first frame after "Hide map" (D2).
  - "Select" an alternative: "Bus N selected"; the map's summary and line follow; no extra `routes.min.json` or
    ArriveLah request.
  - Only the hosts already in the CSP appear, and there are 0 requests to a routing host.
  - 360 px with 2× text, light and dark: nothing clipped. The 4 px spacing change is visible as a tighter top on the
    alternatives.

- [ ] **Step 4: Android** (`emulator-5556`, the release APK from Task 4, `adb install -r`, launched with `monkey`):
  - First read the settings baseline: the three animation scales, `font_scale`, night mode, accessibility
    services, airplane mode.
  - Check:
    - normal motion;
    - light and dark (`cmd uimode night yes`);
    - 360 dp (`wm density`, if the P2-M4 recipe needs it) and `font_scale` 2.0;
    - "Remove animations" (all three scales 0);
    - Select/Selected with the map following;
    - Show/Hide map is instant;
    - no Flutter error in logcat.
  - **Motion by eye on Android:** use only tooling already on the machine. If no frame decoder is already installed,
    log **Not run (no frame decoder installed; `screencap` takes ~0.7 s per frame)**. Don't install `ffmpeg`, add a
    dependency, or change the machine for it (F5).
  - **TalkBack (Q2):** **one** normal attempt. Set the journey up first; enable TalkBack through settings; check
    that the "Selected" mark and "Show steps for Bus N" are announced. **Don't** answer or change the Accessibility
    Suite notification permission, and **no `pm grant`**. If its prompt takes the input, log TalkBack **Not run**
    with the precise reason (which prompt, at which step). The widget and Web semantics evidence stands.
  - Restore every setting and `diff` it against the baseline.

- [ ] **Step 5: Record.**
  - Add the run-log rows: what was seen, frame counts and timestamps, every **Not run** with its reason.
  - Add an open-items entry "UI polish follow-ups (2026-10-0X)" after the Phase 2 one, listing the remaining Not
    runs. Commit `docs/testing.md` with `docs(testing): UI polish follow-ups live checks` plus the trailer.
  - If a live check shows a real defect in what this plan changed, **stop and report**. Don't fix outside the
    plan's scope.

---

### Task 6: Final review and PR

- [ ] **Step 1: A fresh whole-branch review** on the most capable model:
  - Range: `git merge-base origin/main HEAD`..`HEAD`.
  - Inputs: this plan, the frozen decisions and the Review Focus.
  - Checks:
    - only the two code edits plus comments in `lib/`;
    - no domain, provider, data, map-data-flow, host, CSP or dependency change;
    - P2-M3 and P2-M4 tests unchanged and green;
    - D3 handled observationally, KL1 and KL2 documented as known limitations (never as data or journey-state loss);
    - no `MotionSize` around the map card, no keep-alive or state-ownership change, no `MotionSize` redesign
      (Task 4's scope checks);
    - TalkBack handled under Q2 (no `pm grant`, prompt not answered);
    - docs accurate against the code;
    - no stale "UI polish continues" wording left (`git grep -n "UI polish continues"` → nothing outside history).
- [ ] **Step 2: Grade the findings by user effect.**
  - Critical and Important findings get one fix pass, each fix test-first, followed by a green suite.
  - Minors are listed in the PR as deferred.
  - Re-run the gates any fix touches, and log them.
- [ ] **Step 3: Freeze the head.** `git status` clean; record the SHA.
- [ ] **Step 4: Push and open the PR** (never push to `main`):

  ```bash
  git push -u origin feat/ui-polish-followups
  gh pr create --base main --title "UI polish follow-ups: theme drift, spacing, motion evidence, docs" --body-file <scratch file>
  ```

  Body: Summary / Evidence / Merge Danger (the repo's `pr` format). Include the D3 table, the mutation results,
  the gates with real counts, the live checks and every **Not run**. End it with
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- [ ] **Step 5: Don't merge.** Report the PR URL, branch, head SHA and results, then stop for review.

---

## Self-review record (by the plan author)

- **Spec coverage:**
  - D1 → Tasks 1–6 only, with the "Out of scope" list.
  - Q1 → the Task 0 precondition and the file map (the plan arrives through its own docs-only PR).
  - Q2 → Task 5 Step 4 (one attempt, no `pm grant`, prompt not answered, Not run with the precise reason).
  - Q3 → Task 3 Step 6 (two durable `CLAUDE.md` updates; no seam introduced).
  - KL1 / KL2 → "Known limitations"; recorded in Task 3 Steps 1, 3 and 4; shown by Task 1 and Task 5; no task
    changes either.
  - D2 / F6 → the Motion assumptions row and the architecture section, with no `MotionSize` added (the
    Task 4 scope check would show one).
  - D3 → the Task 1 diagnostic, its stop rule and the new assumptions row.
  - F1 → Task 2, Steps 1–4.
  - F2 → Task 2, Steps 5–7.
  - F3 → Task 1, Steps 1–4 (mutations M1 and M2).
  - F4 → Task 3: each listed correction has its step (theme Step 3; haptic Steps 2–3; "Out of date" Steps 2–3;
    `MotionSize` Steps 1 and 3; README/architecture/CLAUDE Steps 4–6; historical note Step 7).
  - F5 → Task 5, Step 2.
  - The user's T0–T6 shape is kept.
- **Placeholders:**
  - Dates "2026-10-0X" and real counts are filled in from the actual run, by the evidence rule.
  - The D3 row's text is given, with the rule for when the observation differs.
- **Scope (checked against `main` @ `8c0ccf6` before the plan PR):** the only `lib/` code edits are the pin shadow and
  the conditional spacer; everything else in `lib/` is a comment. No task adds a map-card `MotionSize`, keep-alive,
  provider-held view state, a `MotionSize` change beyond its doc comment, a dependency, a host or a seam. Every line
  anchor (`journey_map.dart:451`, `journey_card.dart:218-220`, `motion.dart:16-19`, `place_search_field.dart:80`,
  `environment_dashboard.dart:39`, `app_config.dart:215`) matches `main`.
- **Consistency:**
  - Test counts: 638 → 643 (Task 1) → 645 (Task 2).
  - Format: 132 → 133 files.
  - Every key used exists on `main`: `journey-card`, `journey-alternative-1`, `select-option-F10`,
    `selected-option-F10`, `show-map`, `map-card`, `destination-field`.
  - The fakes' stops `BSH1` / `BSH2` come from `integration_test/fakes/fake_bus_network.dart`.
- **Known limits, accepted:**
  - The colour guard is a line scan (marked `ponytail:`).
  - KL1 and KL2 are documented, not changed.
  - Android motion-by-eye depends on a frame decoder already on the machine; otherwise it is logged Not run.
