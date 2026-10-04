# UI Polish Implementation Plan

> **Status (2026-10-04):** implemented in full by PR #35 (merged as `374a024` on 2026-10-02), before Phase 2. Kept
> as the historical record. Its snippets predate Phase 2 and must not be re-applied. The drift and evidence gaps
> found after Phase 2 are closed by `docs/ui-polish-followups-implementation-plan.md`.

> **For agentic workers:** execute the tasks in order, one at a time; each ends on a green test run and a
> commit. If your harness has `superpowers:subagent-driven-development` or `superpowers:executing-plans`, use
> it. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** make the home screen glanceable and calm (the next bus and each reading become the most visible
thing on their card, layout changes animate instead of jumping, dark mode works) without changing any data,
rule or provider behaviour.

**Architecture:** presentation-only changes in `lib/app/` and `lib/features/*/presentation/`, plus one shared
motion primitive (`lib/core/ui/motion.dart`) and one tunable (`AppMotion` in `lib/core/config/app_config.dart`).
Domain, data, providers and HTTP are untouched. Every existing widget `Key` stays, so tests keep finding
widgets; where a test pins visible wording that this plan changes, the task lists the exact edits.

**Tech Stack:** Flutter 3.47.2 stable (Dart 3.13.2), Material 3, Riverpod 3 (`flutter_riverpod`),
`flutter_test`, `integration_test`. No new packages.

**Spec:** this plan is self-contained. The design rationale is the *Design brief* section below (an
assessment of the M5 UI against Apple's design principles, `.claude/skills/apple-design/`). Product rules
come from `docs/singapore-smart-commute-implementation-guide.v2.md` (cited as `§N`) and `CLAUDE.md`; read
`CLAUDE.md` before Task 0.

---

## Design brief (why each change exists)

| # | Problem in the current UI | Principle | Change (task) |
|---|---|---|---|
| 1 | No dark theme: `MaterialApp` sets only `theme` | Craft: colours adapt to light/dark | Light + dark theme from the same teal seed, following the system (Task 1) |
| 2 | Cards and sections appear, vanish and resize in one frame (destination card, journey card, search results, "Change") | Spatial consistency: content unfolds from where it came; respond with motion, not jumps | One `MotionSize` per card: height animates 250 ms with no overshoot, instant under reduce-motion (Task 2) |
| 3 | Origin and destination are two separate cards; "From: X (chosen manually)" / "(from GPS)" is jargon | Familiarity (maps apps show one From/To block); plain language | One route card; "From: Current location" / "From: VIVOCITY", provenance shown by the icon (Task 3) |
| 4 | Every tile repeats its title in the headline ("1-hr PM2.5" then "1-hr PM2.5 18 µg/m³ (Normal)"); the number is no bigger than any other line; "Stale" is jargon | Simplicity and hierarchy: the most important thing is the most obvious | Title once, the number large, the band as a text pill, "Out of date" (Task 4) |
| 5 | The app-bar refresh only refreshes Conditions, which sit at the bottom of the page | Grouping and mapping: a control sits next to what it affects | Refresh button beside the "Conditions" heading (Task 5) |
| 6 | A bus option is seven equal lines; the live times are line four; two alternatives double the card's length | Simplicity: common path first, detail one level deeper | Summary first (service badge, "Take Bus …", next buses), steps below with icons; alternatives' steps collapsed behind "Show steps" (Task 6) |
| 7 | No way to clear a search field; selecting a place gives no tactile confirmation | Familiarity; multimodal feedback on the commit moment only | A clear (×) button; one selection haptic when a place is chosen (Task 7) |

Not taken from the brief, on purpose (do **not** build these here):

- **Swap origin/destination, pull-to-refresh, translucent app bar, map:** new features or behaviour. Out of
  scope; raise them separately.
- **A total journey time** ("~25 min"): the app has no in-vehicle time, so any total would be invented. The
  rule against invented data (`CLAUDE.md`) forbids it.
- **One shared timestamp for all tiles:** §7 requires each PSI and PM2.5 tile to show its own region and
  timestamp.
- **Band colours (green/amber/red):** the band text carries the meaning (§7); a colour scale would add
  thresholds no NEA table defines for this UI. The band pill uses one neutral colour for every band.
- **Reordering home sections** (§16 lists Conditions first): leave the current order.
- **Drag, flick, momentum, rubber-band behaviour:** the app has no custom gestures; Flutter's scroll physics
  already rubber-band per platform.

## Global Constraints

Every task's requirements include these. Values are verbatim from `CLAUDE.md` and the guide.

- No server-side component of any kind, no credentials, no secrets.
- Tunable values are Dart constants in `lib/core/config/app_config.dart`, which stays pure Dart (it imports
  nothing from Flutter). Record each new tunable in `docs/assumptions.md`.
- Never invent readings, arrival times, routes or stops; show a degraded/error state instead.
- "Always label PSI as "24-hr PSI" and PM2.5 as "1-hr PM2.5"" (§6.1); "Show 24-hr PSI and 1-hr PM2.5 as
  separate tiles, each with region and timestamp" (§7); "Don't communicate the band by colour alone. Include
  the band text" (§7); no medical advice.
- "Never label an option "best"; use "Suggested"" (§5.6).
- Accessibility (§16): "Adequate touch targets. Semantic labels. Readable contrast. Never use colour alone
  for bands or bus load. Scalable text." Layouts must not overflow at 2× text on 320 and 360 dp phones.
- Colours come from `Theme.of(context).colorScheme` only; no `Colors.*` or `Color(0x…)` outside the seed in
  `lib/app/app.dart`.
- State stays Riverpod 3 `AsyncValue<T>` with typed `AppFailure`s; no parallel `LoadState` type.
- Keep every existing widget `Key` (tests and integration tests find widgets by them): `refresh-conditions`,
  `change-origin`, `change-destination`, `retry-location`, `keep-origin`, `use-current-location`,
  `origin-line`, `destination-line`, `manual-origin-field`, `destination-field`, `background-location-failure`,
  `place-<id>`, `journey-card`, `journey-suggested`, `journey-alternative-<n>`, `journey-walk-only`,
  `journey-no-stops`, `journey-no-direct`, `journey-mrt`, `journey-mrt-origin`, `journey-mrt-destination`,
  `arrivals-<stop>-<service>`, `arrivals-footer`, `arrivals-refresh`, `tile-forecast`, `tile-uv`, `tile-pm25`,
  `tile-psi`, `refresh-failed`, `conditions-grid-<n>`, `app-logo`.
- `MotionSize` wraps a whole card from the outside, at most once per card, and is never nested inside
  another `MotionSize` (nested size animations lag and clip each other).
- Integration tests never call live APIs and use `pumpUntilFound` (never `pumpAndSettle`, which never
  settles while a progress indicator spins). `pumpAndSettle` is fine only in the isolated motion tests that
  have no spinner.
- Quality gates must actually pass; don't suppress lints. **Evidence rule:** log every gate command and its
  real result in the run log of `docs/testing.md`; anything not run is logged **Not run** with the reason.
- Git: work on a feature branch, small descriptive commits, merge via PR. Never commit or push to `main`;
  no force-push or history rewrites.

## Review Focus

The five conditions most likely to bite a user that no task's main test exercises. Each has a test in the
task named.

1. **Large text on a small phone** (2× text, 320 dp): the service badge, band pill and step rows must wrap,
   never overflow. Test: Task 6 Step 7 (whole app, dark, 2×, 320 dp) and the existing large-text cases in
   `test/features/environment/conditions_grid_test.dart` (re-run in Task 4).
2. **Reduce motion on**: every layout change lands in one frame. Test: Task 2 Step 1, "reduce motion".
3. **A change interrupted mid-animation** (e.g. "Show steps" then "Hide steps" quickly): the size continues
   from where it is on screen, no jump. Test: Task 2 Step 1, "interrupt".
4. **Dark mode legibility**: no hard-coded colour; the whole journey renders in dark mode. Test: Task 1 Step 6
   (grep) and Task 6 Step 7.
5. **Screen readers after the tile redesign**: a tile is still read as label, value, band, scope and time.
   Test: Task 4 Step 1, "screen readers".

---

## File map

| File | Change | Responsibility after the change |
|---|---|---|
| `lib/app/app.dart` | Modify | Light and dark `ThemeData` from one seed; `ThemeMode.system` |
| `lib/core/config/app_config.dart` | Modify | Adds `AppMotion.resize` |
| `lib/core/ui/motion.dart` | **Create** | `uiMotionDurationProvider`, `motionCurve`, `MotionSize` |
| `lib/app/route_card.dart` | **Create** | One card holding the origin and destination sections |
| `lib/app/home_screen.dart` | Modify | Layout; Conditions heading row with the refresh button |
| `lib/features/origin/presentation/origin_card.dart` | Modify | Origin section (no own `Card`), plain "From:" wording |
| `lib/features/destination/presentation/destination_card.dart` | Modify | Destination section (no own `Card`) |
| `lib/features/environment/presentation/reading_text.dart` | Modify | Adds value/band parts and `staleLabel`; removes the unused full-sentence `psi`/`pm25` |
| `lib/features/environment/presentation/environment_dashboard.dart` | Modify | Tile reading layout, band pill, outlined tiles |
| `lib/features/journey/presentation/journey_card.dart` | Modify | Option summary, steps, collapsible alternatives |
| `lib/features/bus_arrival/presentation/option_arrivals.dart` | Modify | Next-buses text style (larger, tabular figures) |
| `lib/features/places/presentation/place_search_field.dart` | Modify | Clear button; haptic on selection |
| `integration_test/fakes/test_app.dart` | Modify | `motionDuration` parameter (default zero) |
| `test/features/environment/data_gov_sg_rate_limit_widget_test.dart` | Modify | Zero motion override (it builds its own `ProviderScope`) |
| `test/app/app_theme_test.dart` | **Create** | Theme tests |
| `test/core/motion_test.dart` | **Create** | `MotionSize` tests |
| Existing tests listed per task | Modify | Wording updates only |
| `docs/assumptions.md`, `docs/architecture.md`, `docs/testing.md`, `CLAUDE.md` | Modify | Task 8 |

Class names `OriginCard` and `DestinationCard` stay even though they no longer draw a `Card`: tests and
`docs/architecture.md` reference them, and renaming is churn with no user value. Their doc comments say what
they are now.

---

### Task 0: Workspace and baseline

**Files:** none changed.

- [ ] **Step 1: Check the baseline.** This plan was written against `main` @ `4f58979` (M5, PR #23,
  merged). Check what changed in the files this plan touches since then:

  ```bash
  git fetch origin
  git diff --stat 4f58979 origin/main -- lib test integration_test
  ```

  Expected: no output. If files in the file map below have changed, read those changes before each task.
  Where a quoted snippet no longer matches the code, follow the plan's intent and note the deviation in the
  PR. If a change contradicts a task (e.g. the widget was rewritten), **stop and ask the user**.

- [ ] **Step 2: Create the feature branch from the latest `main`** (in a worktree if the main checkout has
  other work in progress):

  ```bash
  git switch -c feat/ui-polish origin/main
  flutter pub get
  ```

- [ ] **Step 3: Run the baseline gates** and note the test count:

  ```bash
  dart format --set-exit-if-changed .
  flutter analyze
  flutter test
  ```

  Expected: format no changes, analyze "No issues found!", tests "All tests passed!". If anything fails
  before you have changed code, stop and report it; don't fix unrelated failures inside this plan.

- [ ] **Step 4: Read the code you will change**, once, end to end: every file in the file map above, plus
  `integration_test/support.dart` (`pumpUntilFound`, `inTile`, `scrollToAndTap`) and the helpers at the top
  of `test/widget_test.dart`, `test/features/journey/journey_widget_test.dart` and
  `test/features/places/place_search_widget_test.dart`. Later tasks use those helpers by name.

---

### Task 1: Dark theme that follows the system

**Files:**
- Modify: `lib/app/app.dart`
- Test: `test/app/app_theme_test.dart` (create)

**Interfaces:**
- Produces: `SmartCommuteApp.lightTheme`, `SmartCommuteApp.darkTheme` (`static final ThemeData`).

- [ ] **Step 1: Write the failing test** `test/app/app_theme_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sg_smart_commute/app/app.dart';
  import 'package:sg_smart_commute/app/home_screen.dart';
  import 'package:sg_smart_commute/core/location/location_service.dart';

  import '../../integration_test/fakes/fake_environment_repository.dart';
  import '../../integration_test/fakes/fake_location_service.dart';
  import '../../integration_test/fakes/test_app.dart';

  void main() {
    test('light and dark themes share the teal seed', () {
      expect(SmartCommuteApp.lightTheme.brightness, Brightness.light);
      expect(SmartCommuteApp.darkTheme.brightness, Brightness.dark);
      expect(
        SmartCommuteApp.darkTheme.colorScheme,
        ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('the app follows a ${brightness.name} system setting', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = brightness;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await tester.pumpWidget(
          buildTestApp(
            location: FakeLocationService(access: LocationAccess.denied),
            environment: FakeEnvironmentRepository(),
          ),
        );
        await tester.pump();
        final context = tester.element(find.byType(HomeScreen));
        expect(Theme.of(context).brightness, brightness);
      });
    }
  }
  ```

- [ ] **Step 2: Run it and see it fail**

  Run: `flutter test test/app/app_theme_test.dart`
  Expected: compile error, `lightTheme` / `darkTheme` not defined.

- [ ] **Step 3: Implement.** In `lib/app/app.dart`, replace the `theme:` argument and add the two themes:

  ```dart
  class SmartCommuteApp extends StatelessWidget {
    const SmartCommuteApp({super.key});

    static const String title = 'Singapore Smart Commute';

    /// Light and dark schemes from one seed, so both stay the same palette.
    /// Widgets take colours only from the scheme, never fixed values.
    static final ThemeData lightTheme = _theme(Brightness.light);
    static final ThemeData darkTheme = _theme(Brightness.dark);

    static ThemeData _theme(Brightness brightness) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: brightness,
      ),
    );

    @override
    Widget build(BuildContext context) {
      return MaterialApp(
        title: title,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.system,
        home: const HomeScreen(),
      );
    }
  }
  ```

- [ ] **Step 4: Run the test and see it pass**

  Run: `flutter test test/app/app_theme_test.dart`
  Expected: 3 tests pass.

- [ ] **Step 5: Run the whole suite** (`flutter test`). Expected: all pass.

- [ ] **Step 6: Check for hard-coded colours** (Review Focus 4):

  ```bash
  grep -rn "Colors\.\|Color(0x" lib
  ```

  Expected: exactly one hit, the `Colors.teal` seed in `lib/app/app.dart`. Any other hit: replace it with a
  `colorScheme` role and re-run the tests.

- [ ] **Step 7: Commit**

  ```bash
  git add lib/app/app.dart test/app/app_theme_test.dart
  git commit -m "feat(ui): dark theme that follows the system setting"
  ```

---

### Task 2: Motion primitive (`MotionSize`) and the journey card's entrance

**Files:**
- Modify: `lib/core/config/app_config.dart` (add `AppMotion`)
- Create: `lib/core/ui/motion.dart`
- Modify: `integration_test/fakes/test_app.dart`, `test/features/environment/data_gov_sg_rate_limit_widget_test.dart`
- Modify: `lib/app/home_screen.dart` (wrap `JourneyCard`)
- Test: `test/core/motion_test.dart` (create), `test/features/journey/journey_widget_test.dart` (one new test)

**Interfaces:**
- Produces: `AppMotion.resize` (`Duration`), `uiMotionDurationProvider` (`Provider<Duration>`),
  `motionCurve` (`Curve`), `MotionSize({Key? key, required Widget child})`, and a
  `Duration motionDuration = Duration.zero` parameter on `buildTestApp`.

Why the test default is zero: existing tests tap and find widgets one frame after a change. A 250 ms
animation would leave them half-grown and clipped. Zero duration keeps the old one-frame behaviour in every
existing test; `test/core/motion_test.dart` tests the animated path on its own.

- [ ] **Step 1: Write the failing tests** `test/core/motion_test.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sg_smart_commute/core/config/app_config.dart';
  import 'package:sg_smart_commute/core/ui/motion.dart';

  /// A [MotionSize] around a box of 50 or 200 px height. [duration] overrides
  /// [uiMotionDurationProvider]; null keeps the real [AppMotion.resize].
  Widget host({
    required bool tall,
    bool reduceMotion = false,
    Duration? duration,
  }) => ProviderScope(
    overrides: [
      if (duration != null) uiMotionDurationProvider.overrideWithValue(duration),
    ],
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: MotionSize(
            key: const Key('motion'),
            child: SizedBox(width: 100, height: tall ? 200 : 50),
          ),
        ),
      ),
    ),
  );

  double heightOf(WidgetTester tester) =>
      tester.getSize(find.byKey(const Key('motion'))).height;

  void main() {
    final half = AppMotion.resize ~/ 2;

    testWidgets('grows to new content over AppMotion.resize', (tester) async {
      await tester.pumpWidget(host(tall: false));
      expect(heightOf(tester), 50);

      await tester.pumpWidget(host(tall: true));
      await tester.pump(half);
      expect(heightOf(tester), greaterThan(50));
      expect(heightOf(tester), lessThan(200));

      await tester.pumpAndSettle();
      expect(heightOf(tester), 200);
    });

    testWidgets('interrupt: a change mid-animation continues from the '
        'current size', (tester) async {
      await tester.pumpWidget(host(tall: false));
      await tester.pumpWidget(host(tall: true));
      await tester.pump(half);
      final mid = heightOf(tester);

      await tester.pumpWidget(host(tall: false)); // reverse half-way
      await tester.pump(const Duration(milliseconds: 16));
      expect(heightOf(tester), lessThanOrEqualTo(mid)); // no jump to 200
      expect(heightOf(tester), greaterThan(50)); // no jump to 50

      await tester.pumpAndSettle();
      expect(heightOf(tester), 50);
    });

    testWidgets('reduce motion: the change lands in one frame', (tester) async {
      await tester.pumpWidget(host(tall: false, reduceMotion: true));
      await tester.pumpWidget(host(tall: true, reduceMotion: true));
      expect(heightOf(tester), 200);
    });

    testWidgets('a zero duration override (tests) also lands in one frame', (
      tester,
    ) async {
      await tester.pumpWidget(host(tall: false, duration: Duration.zero));
      await tester.pumpWidget(host(tall: true, duration: Duration.zero));
      expect(heightOf(tester), 200);
    });
  }
  ```

- [ ] **Step 2: Run them and see them fail**

  Run: `flutter test test/core/motion_test.dart`
  Expected: compile errors, `AppMotion` / `motion.dart` not found.

- [ ] **Step 3: Add the tunable.** In `lib/core/config/app_config.dart`, after `AppTimings`:

  ```dart
  /// Layout transitions (presentation only; docs/assumptions.md, "Motion").
  abstract final class AppMotion {
    /// How long a card takes to grow or shrink to new content. The short end
    /// of the 0.3–0.4 s response of a critically damped UI spring, because a
    /// card resizing is a reveal, not a journey across the screen.
    static const Duration resize = Duration(milliseconds: 250);
  }
  ```

- [ ] **Step 4: Create** `lib/core/ui/motion.dart`:

  ```dart
  import 'package:flutter/widgets.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  import '../config/app_config.dart';

  /// How long [MotionSize] animates. Tests override it with [Duration.zero]
  /// so a layout change lands in one frame (`buildTestApp`).
  final uiMotionDurationProvider = Provider<Duration>(
    (ref) => AppMotion.resize,
  );

  /// Decelerates into place with no overshoot: the curve form of a critically
  /// damped spring, so content settles instead of bouncing. Kept here, not in
  /// app_config.dart, because a Curve is a Flutter type and app_config.dart is
  /// pure Dart.
  const Curve motionCurve = Curves.easeOutCubic;

  /// Animates [child]'s height when its content changes, from the top edge, so
  /// new content unfolds below what caused it and collapses back the same way.
  /// A change mid-animation continues from the current on-screen size. With
  /// the system's reduce-motion setting on, changes are instant.
  ///
  /// Wrap a whole card, once. Never nest one inside another: the outer one
  /// would chase the inner one's animated size.
  class MotionSize extends ConsumerWidget {
    const MotionSize({super.key, required this.child});

    final Widget child;

    @override
    Widget build(BuildContext context, WidgetRef ref) {
      final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      return AnimatedSize(
        duration: reduceMotion
            ? Duration.zero
            : ref.watch(uiMotionDurationProvider),
        curve: motionCurve,
        alignment: Alignment.topCenter,
        child: child,
      );
    }
  }
  ```

- [ ] **Step 5: Run the motion tests and see them pass**

  Run: `flutter test test/core/motion_test.dart`
  Expected: 4 tests pass. If "reduce motion" or "zero duration" fails because the height lags one frame,
  don't loosen the test: `AnimatedSize` with `Duration.zero` must settle in the same layout. Check that the
  duration really is zero on that path.

- [ ] **Step 6: Default tests to zero motion.** In `integration_test/fakes/test_app.dart`, add the import
  `package:sg_smart_commute/core/ui/motion.dart`, the parameter and the override:

  ```dart
    Clock? clock,
    Duration motionDuration = Duration.zero,
  }) {
  ```

  ```dart
        clockProvider.overrideWithValue(clock ?? () => fakeNow),
        uiMotionDurationProvider.overrideWithValue(motionDuration),
  ```

  `test/features/environment/data_gov_sg_rate_limit_widget_test.dart` builds its own `ProviderScope` around
  `SmartCommuteApp` (around line 71): add
  `uiMotionDurationProvider.overrideWithValue(Duration.zero),` to its `overrides` list and the same import.
  Then check that nothing else builds the app outside `buildTestApp`:

  ```bash
  grep -rn "SmartCommuteApp()" test integration_test
  ```

  Expected: only `integration_test/fakes/test_app.dart` and the rate-limit test.

- [ ] **Step 7: Write the failing structural test.** In `test/features/journey/journey_widget_test.dart`,
  add the import `package:sg_smart_commute/core/ui/motion.dart` and, inside `main()`, after the
  `'no journey card, and no bus data load, until both ends exist'` test:

  ```dart
  testWidgets('the journey card unfolds inside one MotionSize', (tester) async {
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await tester.pump();
    expect(
      find.ancestor(
        of: find.byKey(const Key('journey-card')),
        matching: find.byType(MotionSize),
      ),
      findsOneWidget,
    );
  });
  ```

  Run: `flutter test test/features/journey/journey_widget_test.dart --plain-name "unfolds inside one MotionSize"`
  Expected: FAIL, found 0 widgets.

- [ ] **Step 8: Wrap the journey card.** In `lib/app/home_screen.dart`, import `../core/ui/motion.dart` and
  change the first column's children:

  ```dart
                  children: [
                    OriginCard(),
                    DestinationCard(),
                    MotionSize(child: JourneyCard()),
                  ],
  ```

  `JourneyCard` returns `SizedBox.shrink()` until both ends exist, so wrapping it from outside animates its
  entrance as well as every later change in its height (loading → result, steps opening in Task 6).

- [ ] **Step 9: Run the test, then the whole suite**

  Run: `flutter test test/features/journey/journey_widget_test.dart` then `flutter test`
  Expected: all pass.

- [ ] **Step 10: Commit**

  ```bash
  git add lib/core/config/app_config.dart lib/core/ui/motion.dart lib/app/home_screen.dart \
    integration_test/fakes/test_app.dart test/core/motion_test.dart \
    test/features/environment/data_gov_sg_rate_limit_widget_test.dart \
    test/features/journey/journey_widget_test.dart
  git commit -m "feat(ui): animate card height changes with MotionSize"
  ```

---

### Task 3: One route card (origin + destination) with plain wording

**Files:**
- Create: `lib/app/route_card.dart`
- Modify: `lib/features/origin/presentation/origin_card.dart`,
  `lib/features/destination/presentation/destination_card.dart`, `lib/app/home_screen.dart`
- Test (wording updates): `test/features/places/place_search_widget_test.dart`, `test/widget_test.dart`,
  `integration_test/fallback_path_test.dart`, `integration_test/happy_path_test.dart`
- Test (new): `test/features/places/place_search_widget_test.dart`

**Interfaces:**
- Consumes: `MotionSize` (Task 2).
- Produces: `RouteCard` (key `route-card` on its `Card`). Origin line text becomes `'From: ${origin.label}'`
  for both provenances (GPS: `From: Current location`).

- [ ] **Step 1: Update the pinned wording in the tests first.** The `(chosen manually)` / `(from GPS)`
  suffixes go away:

  ```bash
  sed -i -E "s/(From: [^']*) \((chosen manually|from GPS)\)/\1/g" \
    test/features/places/place_search_widget_test.dart test/widget_test.dart \
    integration_test/fallback_path_test.dart integration_test/happy_path_test.dart
  grep -rn "chosen manually\|from GPS" test integration_test
  ```

  Expected: the grep prints only comments or test names, if anything. Check each remaining hit. A string
  literal still containing the suffix means the sed missed it: edit it by hand. Example results:
  `'From: VIVOCITY'`, `'From: $hdb'`, `const tampinesHubLine = 'From: OUR TAMPINES HUB';`.

- [ ] **Step 2: Add the failing route-card test.** In `test/features/places/place_search_widget_test.dart`,
  inside `main()`, after the `'a distinct address is shown under the name in both cards'` test:

  ```dart
  testWidgets('origin and destination share one route card', (tester) async {
    await pumpApp(tester, gpsApp());
    await tester.pump();
    final card = find.byKey(const Key('route-card'));
    expect(
      find.descendant(of: card, matching: find.text('From: Current location')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text(DestinationCard.prompt)),
      findsOneWidget,
    );
  });
  ```

  Add the import `package:sg_smart_commute/features/destination/presentation/destination_card.dart` if the
  file lacks it.

- [ ] **Step 3: Run the changed tests and see them fail**

  Run: `flutter test test/features/places/place_search_widget_test.dart test/widget_test.dart`
  Expected: failures on the new wording (the app still shows `(chosen manually)`) and on `route-card` (not
  found).

- [ ] **Step 4: Origin wording and section.** In `origin_card.dart`:

  - Class doc comment: `/// The origin section of the route card (lib/app/route_card.dart): status, the manual-origin prompt and the late-fix offer (§5.1–§5.4).`
  - Replace the closing `return Card(...)` of `OriginCard.build` with:

    ```dart
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
    ```

  - In `_OriginLine.build`, delete the `how` switch and change the text to `'From: ${origin.label}'`. The
    leading icon (`Icons.my_location` for GPS, `Icons.place_outlined` for a searched place) now carries the
    provenance on its own, as in maps apps. `Origin.provenance` is unchanged in the domain (§5.4 stays
    testable there).

- [ ] **Step 5: Destination section.** In `destination_card.dart`:

  - Class doc comment: `/// The destination section of the route card (lib/app/route_card.dart), shown once an origin exists: "Where are you heading to today?" (guide v2.1 §5.5). Same search component as the manual origin.`
  - Replace the closing `return Card(...)` with a divider that separates it from the origin section:

    ```dart
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const Divider(height: 24), ...children],
    );
    ```

- [ ] **Step 6: Create** `lib/app/route_card.dart`:

  ```dart
  import 'package:flutter/material.dart';

  import '../core/ui/motion.dart';
  import '../features/destination/presentation/destination_card.dart';
  import '../features/origin/presentation/origin_card.dart';

  /// Where the trip starts and ends, as one card (guide v2.1 §16 "From: …",
  /// then "Where are you heading today?"). The origin and destination keep
  /// their own controllers; this only groups them. Search results, "Change"
  /// and the destination's arrival all resize the card, so it animates.
  class RouteCard extends StatelessWidget {
    const RouteCard({super.key});

    @override
    Widget build(BuildContext context) => const MotionSize(
      child: Card(
        key: Key('route-card'),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [OriginCard(), DestinationCard()],
          ),
        ),
      ),
    );
  }
  ```

- [ ] **Step 7: Use it on the home screen.** In `lib/app/home_screen.dart`, replace the
  `destination_card.dart` and `origin_card.dart` imports with `import 'route_card.dart';` and set the first
  column's children to:

  ```dart
                  children: [RouteCard(), MotionSize(child: JourneyCard())],
  ```

- [ ] **Step 8: Run the tests**

  Run: `flutter test`
  Expected: all pass. `conditions_grid_test.dart` measures `find.byType(Card).first`, which is now the route
  card. Its width is still `HomeLayout.contentMaxWidth`, so that test needs no edit.

- [ ] **Step 9: Commit**

  ```bash
  git add lib/app/route_card.dart lib/app/home_screen.dart \
    lib/features/origin/presentation/origin_card.dart \
    lib/features/destination/presentation/destination_card.dart \
    test/features/places/place_search_widget_test.dart test/widget_test.dart \
    integration_test/fallback_path_test.dart integration_test/happy_path_test.dart
  git commit -m "feat(ui): one route card for origin and destination, plainer From line"
  ```

---

### Task 4: Reading tiles: the number first, the band as text, "Out of date"

**Files:**
- Modify: `lib/features/environment/presentation/reading_text.dart`,
  `lib/features/environment/presentation/environment_dashboard.dart`
- Test: `test/features/environment/reading_text_test.dart`, `test/features/environment/conditions_grid_test.dart`,
  `test/widget_test.dart`, `integration_test/happy_path_test.dart`, `integration_test/fallback_path_test.dart`

**Interfaces:**
- Produces in `ReadingText`: `typedef ReadingParts = ({String value, String? band});`,
  `static ReadingParts pm25Parts(EnvironmentalReading<num> r)`,
  `static ReadingParts psiParts(EnvironmentalReading<num> r)`, `static ReadingParts uvParts(int value)`,
  `static const String staleLabel = 'Out of date'`. Removes `ReadingText.pm25` and `ReadingText.psi`
  (unused after this task). Keeps `uv`, `uvValue`, `uvNightDetail`, `forecast`, `scope`, `timestamp` and
  the four titles.

The spec label stays visible in each tile's title row (`24-hr PSI`, `1-hr PM2.5`). The tile `Card` is a
semantics container, so a screen reader reads title, value, band, scope and time as one node.

- [ ] **Step 1: Update the unit tests and add the failing ones.** In `reading_text_test.dart`, replace the
  test `'PSI is always labelled "24-hr PSI" and PM2.5 "1-hr PM2.5"'` and the test
  `'fractional values keep one decimal'` with:

  ```dart
  test('tile titles keep the spec labels', () {
    expect(ReadingText.psiTitle, '24-hr PSI');
    expect(ReadingText.pm25Title, '1-hr PM2.5');
  });

  test('PSI, PM2.5 and UV split into a value and an official band', () {
    expect(
      ReadingText.psiParts(reading<num>(54, SpatialScope.region, 'central')),
      (value: '54', band: 'Moderate'),
    );
    expect(
      ReadingText.pm25Parts(reading<num>(18, SpatialScope.region, 'central')),
      (value: '18 µg/m³', band: 'Normal'),
    );
    expect(ReadingText.uvParts(7), (value: '7', band: 'High'));
  });

  test('fractional values keep one decimal', () {
    expect(
      ReadingText.pm25Parts(reading<num>(18.24, SpatialScope.region, 'east')),
      (value: '18.2 µg/m³', band: 'Normal'),
    );
  });

  test('stale readings are marked in plain words', () {
    expect(ReadingText.staleLabel, 'Out of date');
  });
  ```

- [ ] **Step 2: Update the widget and integration tests' pinned strings.** List them:

  ```bash
  grep -rn "24-hr PSI [0-9]\|1-hr PM2.5 [0-9]\|'UV [0-9]\|'Stale'" test integration_test
  ```

  Replace each full sentence with its parts:

  | Old text | Value | Band |
  |---|---|---|
  | `'24-hr PSI 54 (Moderate)'` | `'54'` | `'Moderate'` |
  | `'24-hr PSI 61 (Moderate)'` | `'61'` | `'Moderate'` |
  | `'1-hr PM2.5 18 µg/m³ (Normal)'` | `'18 µg/m³'` | `'Normal'` |
  | `'1-hr PM2.5 13 µg/m³ (Normal)'` | `'13 µg/m³'` | `'Normal'` |
  | `'UV 7 (High)'` | `'7'` | `'High'` |
  | `'Stale'` | `'Out of date'` | — |

  Rules:
  - `expect(inTile(k, OLD), findsOneWidget)` becomes two lines:
    `expect(inTile(k, VALUE), findsOneWidget); expect(inTile(k, BAND), findsOneWidget);`
  - `expect(inTile(k, OLD), findsNothing)` becomes `expect(inTile(k, VALUE), findsNothing);`
  - `pumpUntilFound(tester, inTile(k, OLD))` and `final x = inTile(k, OLD);` use VALUE only.
  - `'Stale'` becomes `'Out of date'` everywhere, including `find.text('Stale')`. Update test names that say
    "Stale marker" to "out-of-date marker".

  Leave unchanged: `'UV not measured at night'`, every `'As of …'` string, and the expectations in
  `reading_text_test.dart` for `ReadingText.uv` and `ReadingText.uvNightDetail` (`'UV 5 (Moderate)'`,
  `'Last reading UV 0 (Low) at 12:00 SGT'`). Those functions keep their sentences; the grep lists them, but
  they are not tile text.

- [ ] **Step 3: Add the failing tile tests.** In `test/features/environment/conditions_grid_test.dart`,
  inside `main()` (it has `pumpAt` and `showGrid`):

  ```dart
  testWidgets('a tile shows its label once and its number large', (tester) async {
    await pumpAt(tester, const Size(360, 800));
    await showGrid(tester);
    expect(inTile('tile-psi', ReadingText.psiTitle), findsOneWidget);
    expect(find.descendant(
      of: find.byKey(const Key('tile-psi')),
      matching: find.textContaining('24-hr PSI 54'),
    ), findsNothing);
    final value = tester.widget<Text>(inTile('tile-psi', '54'));
    final body = Theme.of(tester.element(inTile('tile-psi', '54')))
        .textTheme
        .bodyMedium!;
    expect(value.style!.fontSize, greaterThan(body.fontSize!));
  });

  testWidgets('screen readers hear label, value, band, scope and time', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpAt(tester, const Size(360, 800));
    await showGrid(tester);
    final label = tester.getSemantics(find.byKey(const Key('tile-psi'))).label;
    for (final part in [
      '24-hr PSI', '54', 'Moderate', 'Central region', 'As of 12:00 SGT',
    ]) {
      expect(label, contains(part));
    }
    expect(
      label.indexOf('24-hr PSI'),
      lessThan(label.indexOf('54')),
    ); // label before value
    semantics.dispose();
  });
  ```

  Add the imports `package:sg_smart_commute/features/environment/presentation/reading_text.dart` and
  `package:flutter/material.dart` if missing. If the file has no `inTile` helper, add
  `Finder inTile(String key, String text) => find.descendant(of: find.byKey(Key(key)), matching: find.text(text));`
  at top level.

- [ ] **Step 4: Run and see them fail**

  Run: `flutter test test/features/environment/`
  Expected: compile errors (`psiParts`, `staleLabel` undefined) or failures on the new strings.

- [ ] **Step 5: Implement the parts.** In `reading_text.dart`, delete `pm25(...)` and `psi(...)` and add,
  inside `ReadingText`:

  ```dart
  /// Shown for a reading older than its dataset's threshold (§6.3).
  static const String staleLabel = 'Out of date';

  /// The number shown large on a tile, and its official band (null when no
  /// NEA band applies). The metric label is the tile title, shown once.
  static ReadingParts pm25Parts(EnvironmentalReading<num> r) =>
      (value: '${_number(r.value)} µg/m³', band: pm25Band(r.value));

  static ReadingParts psiParts(EnvironmentalReading<num> r) =>
      (value: _number(r.value), band: psiBand(r.value));

  static ReadingParts uvParts(int value) =>
      (value: '$value', band: uvBand(value));
  ```

  and at top level, after the imports:

  ```dart
  /// A reading split for display: [value] large, [band] as a text pill.
  typedef ReadingParts = ({String value, String? band});
  ```

  Update the class doc comment: "Pure, so the exact wording — especially the "24-hr PSI" / "1-hr PM2.5" titles — is unit-tested."

- [ ] **Step 6: Implement the tile layout.** In `environment_dashboard.dart`:

  a. The UV, PM2.5 and PSI builders pass parts; forecast and UV-at-night pass a sentence:

  ```dart
        builder: (s, _) {
          final r = EnvironmentLocator.uv(s);
          final night = isUvNight(now);
          final parts = ReadingText.uvParts(r.value);
          return _ReadingView(
            headline: night ? ReadingText.uv(r, now) : null,
            value: night ? null : parts.value,
            band: night ? null : parts.band,
            scope: ReadingText.scope(r),
            detail: ReadingText.uvNightDetail(r, now),
            timestamp: ReadingText.timestamp(r.observedAt, now),
            stale: r.isStale(now),
          );
        },
  ```

  PM2.5 tile (`tile-pm25`):

  ```dart
        builder: (s, p) {
          final r = EnvironmentLocator.regional(s, p!);
          final parts = ReadingText.pm25Parts(r);
          return _ReadingView(
            value: parts.value,
            band: parts.band,
            scope: ReadingText.scope(r),
            timestamp: ReadingText.timestamp(r.observedAt, now),
            stale: r.isStale(now),
          );
        },
  ```

  PSI tile (`tile-psi`):

  ```dart
        builder: (s, p) {
          final r = EnvironmentLocator.regional(s, p!);
          final parts = ReadingText.psiParts(r);
          return _ReadingView(
            value: parts.value,
            band: parts.band,
            scope: ReadingText.scope(r),
            timestamp: ReadingText.timestamp(r.observedAt, now),
            stale: r.isStale(now),
          );
        },
  ```

  The forecast builder needs no change: its `headline:`, `icon:`, `scope:`, `detail:`, `timestamp:` and
  `stale:` arguments all still exist on the new `_ReadingView`.

  b. Replace `_ReadingView` with:

  ```dart
  class _ReadingView extends StatelessWidget {
    const _ReadingView({
      required this.scope,
      required this.timestamp,
      required this.stale,
      this.value,
      this.band,
      this.headline,
      this.detail,
      this.icon,
    }) : assert((value == null) != (headline == null));

    /// The reading shown large ("54", "18 µg/m³", "7"); null when [headline]
    /// is used instead.
    final String? value;

    /// The official band of [value], shown as text (never colour alone, §7).
    final String? band;

    /// A sentence instead of a number: the forecast condition, or UV at night.
    final String? headline;
    final String scope;
    final String timestamp;
    final String? detail;
    final bool stale;
    final IconData? icon;

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      final small = theme.textTheme.bodySmall;
      const tabular = [FontFeature.tabularFigures()];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (value != null)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  value!,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: tabular,
                  ),
                ),
                if (band != null) _BandPill(band!),
              ],
            )
          else
            Row(
              children: [
                if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
                Flexible(
                  child: Text(headline!, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
          const SizedBox(height: 4),
          Text(scope),
          if (detail != null) Text(detail!, style: small),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                timestamp,
                style: small?.copyWith(fontFeatures: tabular),
              ),
              // Text, not colour alone (§7, accessibility).
              if (stale)
                Text(
                  ReadingText.staleLabel,
                  style: small?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      );
    }
  }

  /// A band as a small pill. One neutral colour for every band: the word is
  /// the meaning, so no colour scale implies thresholds NEA did not define.
  class _BandPill extends StatelessWidget {
    const _BandPill(this.band);

    final String band;

    @override
    Widget build(BuildContext context) {
      final scheme = Theme.of(context).colorScheme;
      return DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(
            band,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSecondaryContainer,
            ),
          ),
        ),
      );
    }
  }
  ```

  c. In `_SnapshotTile.build`, change `return Card(` to `return Card.outlined(` (keep
  `margin: EdgeInsets.zero` and the child). Outlined tiles read as lighter than the elevated route and
  journey cards: Conditions are ambient information, the trip is the task.

- [ ] **Step 7: Run the tests**

  Run: `flutter test`
  Expected: all pass, including the existing 1-column large-text cases in `conditions_grid_test.dart`
  (Review Focus 1). If one of them reports a RenderFlex overflow, the `Wrap` is missing around the value
  and pill.

- [ ] **Step 8: Commit**

  ```bash
  git add lib/features/environment/presentation/ test/ integration_test/
  git commit -m "feat(environment): tiles lead with the number and show the band as text"
  ```

---

### Task 5: Refresh button beside the Conditions heading

**Files:**
- Modify: `lib/app/home_screen.dart`
- Test: `test/widget_test.dart` (one new test)

**Interfaces:**
- Produces: private `_RefreshConditionsButton` (key `refresh-conditions`, tooltip `Refresh conditions`).
  `HomeScreen` becomes a `StatelessWidget`.

- [ ] **Step 1: Write the failing test.** In `test/widget_test.dart`, inside `main()`:

  ```dart
  testWidgets('the conditions refresh sits beside the Conditions heading', (
    tester,
  ) async {
    await pumpApp(
      tester,
      buildTestApp(
        location: FakeLocationService(access: LocationAccess.denied),
        environment: FakeEnvironmentRepository(),
      ),
    );
    await tester.pump();
    final button = find.byKey(const Key('refresh-conditions'));
    expect(
      find.descendant(of: find.byType(AppBar), matching: button),
      findsNothing,
    );
    final heading = tester.getRect(find.text('Conditions'));
    final rect = tester.getRect(button);
    expect((rect.center.dy - heading.center.dy).abs(), lessThan(24));
    expect(rect.left, greaterThan(heading.right));
  });
  ```

- [ ] **Step 2: Run and see it fail**

  Run: `flutter test test/widget_test.dart --plain-name "beside the Conditions heading"`
  Expected: FAIL, the button is a descendant of `AppBar`.

- [ ] **Step 3: Move the button.** In `lib/app/home_screen.dart`:

  - Remove `actions:` from the `AppBar` (keep `title: const AppTitle()`).
  - Change `HomeScreen` to `extends StatelessWidget` with `Widget build(BuildContext context)`.
  - Replace the `Text('Conditions', …)` child with:

    ```dart
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Conditions',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        const _RefreshConditionsButton(),
                      ],
                    ),
    ```

  - Add at the end of the file, moving the old `onPressed` body over unchanged:

    ```dart
    /// Refreshes the four Conditions datasets (with the cooldown in
    /// [EnvironmentRefresher]). It sits beside the heading of what it
    /// refreshes; the tiles' own spinners show the progress right below it.
    class _RefreshConditionsButton extends ConsumerWidget {
      const _RefreshConditionsButton();

      @override
      Widget build(BuildContext context, WidgetRef ref) => IconButton(
        key: const Key('refresh-conditions'),
        tooltip: 'Refresh conditions',
        icon: const Icon(Icons.refresh),
        onPressed: () {
          final note = switch (ref
              .read(environmentRefresherProvider.notifier)
              .refreshAll()) {
            RefreshAllResult.started => null,
            RefreshAllResult.stillRefreshing =>
              'Conditions are still refreshing.',
            RefreshAllResult.justUpdated =>
              'Conditions were just updated. Try again shortly.',
          };
          if (note != null) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(note)));
          }
        },
      );
    }
    ```

- [ ] **Step 4: Run the tests**

  Run: `flutter test`
  Expected: all pass. The existing refresh tests tap by key on a 1080 × 4000 test view, so the button is
  built. If an integration test taps it, use `scrollToAndTap` from `integration_test/support.dart`; the list
  is lazy.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/app/home_screen.dart test/widget_test.dart
  git commit -m "feat(ui): put the conditions refresh beside the Conditions heading"
  ```

---

### Task 6: Journey options: summary first, steps below, alternatives collapsible

**Files:**
- Modify: `lib/features/journey/presentation/journey_card.dart`,
  `lib/features/bus_arrival/presentation/option_arrivals.dart`
- Test: `test/features/journey/journey_widget_test.dart` (new tests)

**Interfaces:**
- Consumes: `OptionArrivals` (unchanged API), `MotionSize` around `JourneyCard` (Task 2).
- Produces: `_Option({required DirectBusOptions plan, required BusOption option, String? heading, bool collapsible = false})`,
  private `_ServiceBadge`, `_Steps`, `_Step`; toggle labels `Show steps` / `Hide steps`.

Every pinned text stays identical: `Take Bus F20 toward VivoCity (fake)`, `2 stops`, `1 stop`,
`Alight at …`, `… to Bus Stop …`, `… to destination`, `Next buses: …`, `Suggested`, `Alternatives`. New
layout of one option:

```text
Suggested
[F20]  Take Bus F20 toward VivoCity            ← badge + direction
       Next buses: Arr · 7 min · 19 min        ← live times, emphasised
  🚶   ~2 min walk (est.) to Bus Stop BSH2 — …  ← steps, rider order
  🚌   2 stops
  📍   Alight at VIV1 — VivoCity (fake)
  🚶   ~1 min walk (est.) to destination
```

The suggestion is always open. An alternative shows the badge, direction and live times, with
`Show steps` below. Steps are in rider order (walk, ride, alight, walk). The bus is named once, in the
summary, so the "2 stops" row is the ride.

- [ ] **Step 1: Write the failing tests.** In `journey_widget_test.dart`, inside `main()`:

  ```dart
  testWidgets('alternatives show their bus and live times; steps open on '
      'demand', (tester) async {
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await tester.pump();
    await tester.pump();

    const alt = 'journey-alternative-1';
    Finder inAlt(Finder f) =>
        find.descendant(of: find.byKey(const Key(alt)), matching: f);
    expect(inKey(alt, 'Take Bus F10 toward VivoCity (fake)'), findsOneWidget);
    // Live times stay in the collapsed summary (whatever their load state).
    expect(inAlt(find.byKey(const Key('arrivals-BSH1-F10'))), findsOneWidget);
    expect(inAlt(find.textContaining('to Bus Stop')), findsNothing);

    await tester.tap(inKey(alt, 'Show steps'));
    await tester.pump();
    expect(inAlt(find.textContaining('to Bus Stop BSH1')), findsOneWidget);
    expect(inKey(alt, 'Hide steps'), findsOneWidget);

    await tester.tap(inKey(alt, 'Hide steps'));
    await tester.pump();
    expect(inAlt(find.textContaining('to Bus Stop')), findsNothing);

    // The suggestion is always open and has no toggle.
    expect(inKey('journey-suggested', 'Show steps'), findsNothing);
    expect(inKey('journey-suggested', 'Hide steps'), findsNothing);
  });

  testWidgets('each option leads with a service badge', (tester) async {
    await pumpApp(tester, gpsApp());
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await tester.pump();
    await tester.pump();
    // The badge is the service number on its own.
    expect(inKey('journey-suggested', 'F20'), findsOneWidget);
    expect(inKey('journey-alternative-1', 'F10'), findsOneWidget);
  });
  ```

- [ ] **Step 2: Run and see them fail**

  Run: `flutter test test/features/journey/journey_widget_test.dart --plain-name "alternatives show their bus"`
  Expected: FAIL, the step text is present in the alternative and `Show steps` is not found.

- [ ] **Step 3: Implement.** In `journey_card.dart`:

  a. In `_Plan`, the `DirectBusOptions` branch builds the options like this (the rest of that `Column`, the
  `Alternatives` heading and `ArrivalsFooter`, stays):

  ```dart
            _Option(
              key: const Key('journey-suggested'),
              plan: direct,
              option: direct.options.first,
              heading: 'Suggested',
            ),
            if (direct.options.length > 1) ...[
              const SizedBox(height: 12),
              Text('Alternatives', style: theme.textTheme.titleSmall),
              for (var i = 1; i < direct.options.length; i++)
                // Keyed by the option itself, so an open "Show steps" never
                // carries over to a different bus at the same position.
                KeyedSubtree(
                  key: ValueKey(
                    '${direct.options[i].board.code}-'
                    '${direct.options[i].service.number}',
                  ),
                  child: _Option(
                    key: Key('journey-alternative-$i'),
                    plan: direct,
                    option: direct.options[i],
                    collapsible: true,
                  ),
                ),
            ],
  ```

  b. Replace `_Option` with:

  ```dart
  /// One direct-bus option: which bus and when (the summary) first, then the
  /// steps in the order the rider does them. A [collapsible] option (an
  /// alternative) starts with its steps hidden behind "Show steps".
  class _Option extends StatefulWidget {
    const _Option({
      super.key,
      required this.plan,
      required this.option,
      this.heading,
      this.collapsible = false,
    });
    final DirectBusOptions plan;
    final BusOption option;
    final String? heading;
    final bool collapsible;

    @override
    State<_Option> createState() => _OptionState();
  }

  class _OptionState extends State<_Option> {
    late bool _expanded = !widget.collapsible;

    @override
    Widget build(BuildContext context) {
      final theme = Theme.of(context);
      final o = widget.option;
      final loop = o.isLoop ? ' (loop service)' : '';
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.heading != null)
              Text(widget.heading!, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ServiceBadge(o.service.number),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Take Bus ${o.service.number} toward '
                        '${o.towardName}$loop',
                        style: theme.textTheme.titleSmall,
                      ),
                      OptionArrivals(
                        key: Key(
                          'arrivals-${o.board.code}-${o.service.number}',
                        ),
                        plan: widget.plan,
                        option: o,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_expanded) _Steps(option: o),
            if (widget.collapsible)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Hide steps' : 'Show steps'),
                ),
              ),
          ],
        ),
      );
    }
  }

  /// The service number as a solid badge, the first thing the eye finds.
  /// Decorative for screen readers: the line beside it says "Take Bus N".
  class _ServiceBadge extends StatelessWidget {
    const _ServiceBadge(this.number);
    final String number;

    @override
    Widget build(BuildContext context) {
      final scheme = Theme.of(context).colorScheme;
      return ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minWidth: 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            number,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
    }
  }

  /// Walk, ride, alight, walk: the rider's order (§5.6).
  class _Steps extends StatelessWidget {
    const _Steps({required this.option});
    final BusOption option;

    @override
    Widget build(BuildContext context) {
      final o = option;
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Step(
              Icons.directions_walk,
              '${o.walkToStop.label} to Bus Stop ${o.board.code} — '
              '${o.board.name}',
            ),
            _Step(
              Icons.directions_bus_outlined,
              '${o.stops} ${o.stops == 1 ? 'stop' : 'stops'}',
            ),
            _Step(
              Icons.place_outlined,
              'Alight at ${o.alight.code} — ${o.alight.name}',
            ),
            _Step(Icons.directions_walk, '${o.walkFromStop.label} to destination'),
          ],
        ),
      );
    }
  }

  class _Step extends StatelessWidget {
    const _Step(this.icon, this.text);
    final IconData icon;
    final String text;

    @override
    Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
  ```

  Don't add a `MotionSize` here: the one around `JourneyCard` (Task 2) already animates the card when steps
  open, and nesting is forbidden (Global Constraints).

  c. In `option_arrivals.dart`, `_loaded`, change the `Next buses` style to make the live times the
  emphasis, with digits that don't shift as they count down:

  ```dart
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
  ```

- [ ] **Step 4: Run the journey and arrival tests**

  Run: `flutter test test/features/journey/ test/features/bus_arrival/`
  Expected: all pass. `arrivals_widget_test.dart` "screen readers hear the ETAs in words" still passes: the
  alternatives' `Next buses` stay visible when collapsed, and the badge is excluded from semantics.

- [ ] **Step 5: Check no test relied on an alternative's steps being visible**

  ```bash
  grep -rn "journey-alternative" test integration_test
  ```

  Expected: every hit asserts only `Take Bus …`, key presence, or `arrivals-…` text. A hit that asserts
  `to Bus Stop`, `stops`, `Alight at` or `to destination` inside an alternative must first tap
  `Show steps` (scoped to that alternative).

- [ ] **Step 6: Run the whole unit and widget suite** (the device and Web integration runs come in
  Task 8):

  Run: `flutter test`
  Expected: all pass.

- [ ] **Step 7: Add the dark, large-text, small-phone regression test** (Review Focus 1 and 4). In
  `journey_widget_test.dart`, inside `main()`, and add the import
  `package:sg_smart_commute/core/ui/motion.dart` if Task 2 did not:

  ```dart
  testWidgets('dark theme, 2× text, 320 dp: the whole journey renders '
      'without overflow, with one MotionSize per animated card', (tester) async {
    tester.view.physicalSize = const Size(320, 8000);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(gpsApp());
    await tester.pump();
    await searchAndPick(tester, destinationField, 'VivoCity', 'VIVOCITY');
    await tester.pump();
    await tester.pump();
    final show = inKey('journey-alternative-1', 'Show steps');
    await tester.ensureVisible(show);
    await tester.tap(show);
    await tester.pump();

    expect(tester.takeException(), isNull); // no RenderFlex overflow
    expect(find.byKey(const Key('journey-suggested')), findsOneWidget);
    expect(find.byType(MotionSize), findsNWidgets(2)); // route + journey
    expect(
      find.descendant(
        of: find.byType(MotionSize),
        matching: find.byType(MotionSize),
      ),
      findsNothing,
    );
  });
  ```

  Run: `flutter test test/features/journey/journey_widget_test.dart`
  Expected: all pass. On an overflow, wrap the offending `Row` child in `Expanded`/`Flexible` or switch it
  to a `Wrap`; never shrink the text scale.

- [ ] **Step 8: Commit**

  ```bash
  git add lib/features/journey/presentation/journey_card.dart \
    lib/features/bus_arrival/presentation/option_arrivals.dart \
    test/features/journey/journey_widget_test.dart
  git commit -m "feat(journey): lead each option with its bus and live times; collapse alternatives"
  ```

---

### Task 7: Search field: clear button and a selection haptic

**Files:**
- Modify: `lib/features/places/presentation/place_search_field.dart`
- Test: `test/features/places/place_search_widget_test.dart`

**Interfaces:**
- Produces: `PlaceSearchField.clearTooltip = 'Clear search'`.

- [ ] **Step 1: Write the failing tests.** In `place_search_widget_test.dart`, add the import
  `package:flutter/services.dart` and, inside `main()` (it has `pumpApp`, `deniedApp`, `type`, `pick`,
  `originField`, `originOf`):

  ```dart
  testWidgets('the clear button empties the field and its results and '
      'selects nothing', (tester) async {
    await pumpApp(tester, deniedApp());
    final clear = find.descendant(
      of: find.byKey(originField),
      matching: find.byTooltip(PlaceSearchField.clearTooltip),
    );
    expect(clear, findsNothing); // empty field: no button

    await type(tester, originField, '098585');
    expect(find.text('1 match. Tap it to confirm.'), findsOneWidget);
    expect(clear, findsOneWidget);

    await tester.tap(clear);
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(originField));
    expect(field.controller!.text, isEmpty);
    expect(find.text('1 match. Tap it to confirm.'), findsNothing);
    expect(clear, findsNothing);
    expect(originOf(tester).origin, isNull);
  });

  testWidgets('choosing a place gives one selection click; typing gives none', (
    tester,
  ) async {
    final haptics = <Object?>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add(call.arguments);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpApp(tester, deniedApp());
    await type(tester, originField, '098585');
    expect(haptics, isEmpty);

    await pick(tester, 'VIVOCITY');
    expect(haptics, ['HapticFeedbackType.selectionClick']);
  });
  ```

- [ ] **Step 2: Run and see them fail**

  Run: `flutter test test/features/places/place_search_widget_test.dart`
  Expected: compile error (`clearTooltip` undefined).

- [ ] **Step 3: Implement.** In `place_search_field.dart`:

  - Add `import 'package:flutter/services.dart';`.
  - In `PlaceSearchField`, add `static const String clearTooltip = 'Clear search';`.
  - In `_PlaceSearchFieldState`, add:

    ```dart
    /// Empties the field and its results; nothing is selected, and focus
    /// stays so the user can type again at once.
    void _clear() {
      _controller.clear();
      _session.clear();
      _focus.requestFocus();
    }
    ```

  - In `_select`, add `HapticFeedback.selectionClick();` as the first line. It confirms the commit
    moment only. On Web it does nothing.
  - Wrap the `TextField` in a builder so the suffix follows the text, and add the suffix:

    ```dart
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => TextField(
              key: widget.fieldKey,
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              maxLength: PlaceSearchConfig.maxQueryLength,
              decoration: InputDecoration(
                labelText: widget.label,
                hintText: PlaceSearchField.hint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: value.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: PlaceSearchField.clearTooltip,
                        icon: const Icon(Icons.clear),
                        onPressed: _clear,
                      ),
                border: const OutlineInputBorder(),
                counterText: '', // the limit is generous; no visible counter
              ),
              onChanged: (text) {
                widget.onEditingStarted?.call();
                _session.onChanged(text);
              },
              onSubmitted: _session.submit,
            ),
          ),
    ```

- [ ] **Step 4: Run the tests**

  Run: `flutter test`
  Expected: all pass.

- [ ] **Step 5: Commit**

  ```bash
  git add lib/features/places/presentation/place_search_field.dart \
    test/features/places/place_search_widget_test.dart
  git commit -m "feat(places): clear button and a selection haptic in place search"
  ```

---

### Task 8: Docs, full gates, visual check, PR

**Files:**
- Modify: `docs/assumptions.md`, `docs/architecture.md`, `docs/testing.md`, `CLAUDE.md`

- [ ] **Step 1: `docs/assumptions.md`.** Add rows to the table (same columns:
  `| Area | Assumption | Value | Source / note |`):

  | Area | Assumption | Value | Source / note |
  |---|---|---|---|
  | Motion | Cards (route, journey) animate their height when content changes, from the top edge, decelerating with no overshoot (`Curves.easeOutCubic`). A change mid-animation continues from the current size. The system reduce-motion setting makes changes instant. One `MotionSize` per card, never nested. Tests run with zero duration (`buildTestApp(motionDuration:)`) | 250 ms (`AppMotion.resize`) | UI polish; Apple design guidance (critically damped spring, response 0.3–0.4 s) |
  | Theme | Light and dark themes from one teal seed; follows the system setting. Colours only from the scheme | — | UI polish |
  | Origin line | "From: <label>" for both provenances (GPS: "From: Current location"); the icon shows GPS vs a searched place. Provenance stays in the domain (§5.4) | — | UI polish; matches §16 "From: Current location" |
  | Reading tiles | The metric label is the tile title, shown once; the value is large; the band is a text pill in one neutral colour; each tile keeps its own scope and timestamp (§7). Out-of-threshold readings say "Out of date" | — | UI polish |
  | Journey options | Each option leads with its service badge, "Take Bus N toward X" and the live times; then the steps in rider order. Alternatives' steps are collapsed behind "Show steps". No total journey time is shown: there is no in-vehicle time, so it would be invented | — | UI polish |
  | Place search | A clear (×) button empties the field and its results and selects nothing. Choosing a result gives one selection haptic (no-op on Web) | — | UI polish |

  Also update the existing **UI tick** row: "the Stale marker" → "the Out-of-date marker".

- [ ] **Step 2: `docs/architecture.md`.** Where it says "`OriginCard` is the UI" and describes
  `DestinationCard`, add that both render as sections of `RouteCard` (`lib/app/route_card.dart`), and list
  `lib/core/ui/motion.dart` (`MotionSize`) beside `status_rows.dart` if the doc lists `core/ui`.

- [ ] **Step 3: `CLAUDE.md`.** In *Testing*, add `uiMotionDurationProvider` to the list of test seams
  overridden via providers, with: "`buildTestApp` defaults it to zero, so layout changes land in one frame;
  `test/core/motion_test.dart` covers the animated path."

- [ ] **Step 4: Run every quality gate** (guide §19):

  ```bash
  dart format --set-exit-if-changed .
  flutter analyze
  flutter test
  flutter build web
  flutter build apk --debug
  flutter test integration_test -d <android-device-id>
  ```

  Then Web integration, one file per run (needs chromedriver matching Chrome on port 4444; see
  `docs/testing.md`):

  ```bash
  flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_boot_test.dart -d web-server --browser-name=chrome --profile
  flutter drive --driver=test_driver/integration_test.dart --target=integration_test/happy_path_test.dart -d web-server --browser-name=chrome --profile
  flutter drive --driver=test_driver/integration_test.dart --target=integration_test/fallback_path_test.dart -d web-server --browser-name=chrome --profile
  ```

  Expected: every command passes. If no Android device or chromedriver is available, don't claim a pass:
  log it **Not run** with the reason.

- [ ] **Step 5: Visual check in Chrome** (`flutter run -d chrome`). Look at each and note what you saw:
  - Light and dark (DevTools → Rendering → "Emulate CSS prefers-color-scheme").
  - A 360 px window and 2× text (Chrome font size "Very large").
  - Pick a destination: the journey card unfolds instead of popping in. Show and hide an alternative's steps
    quickly: no jump.
  - Reduced motion: DevTools → Rendering → "Emulate CSS prefers-reduced-motion: reduce". If Flutter Web
    doesn't pick this up, check on Android instead: Settings → Accessibility → "Remove animations".

  If you cannot run a browser, log the visual check as **Not run**.

- [ ] **Step 6: Log the run** in the run log of `docs/testing.md`, one row per command:
  `| <date> | UI polish | <command> | <real result, e.g. "Pass, 312/312"> |`. Use the real counts from
  your output.

- [ ] **Step 7: Commit the docs**

  ```bash
  git add docs/assumptions.md docs/architecture.md docs/testing.md CLAUDE.md
  git commit -m "docs: record the UI polish decisions, test seam and gate results"
  ```

- [ ] **Step 8: Open the PR** (never push to `main`):

  ```bash
  git push -u origin feat/ui-polish
  gh pr create --base main --title "UI polish: glanceable journey and readings, motion, dark mode" \
    --body-file <file with: summary per task, the design-brief table, gates with real results, Not-run items>
  ```

---

## Self-review record (done by the plan author)

- **Brief coverage:** items 1–7 → Tasks 1–7; docs and gates → Task 8. The "Not taken" items are named, so
  an executor doesn't add them.
- **Spec checks:** the §6.1 labels stay as tile titles (Task 4, title test); §7 keeps per-tile scope and
  timestamp (`_ReadingView` keeps both); bands are text (`_BandPill`); "Suggested" kept; nothing is invented
  (no total time).
- **Consistency:** `MotionSize`, `uiMotionDurationProvider`, `AppMotion.resize`, `ReadingParts`,
  `psiParts`/`pm25Parts`/`uvParts`, `staleLabel`, `clearTooltip` and `collapsible` are each defined once and
  used with the same names in later tasks.
- **Known gap, accepted:** the `KeyedSubtree` that stops an open alternative carrying over to a different
  bus has no dedicated test. The fake network has no two destinations that both have alternatives, and a
  new fake network for one guard line is not worth its weight.
