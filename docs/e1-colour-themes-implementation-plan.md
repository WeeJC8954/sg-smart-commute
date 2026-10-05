# E1 Selectable Colour Themes: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** approved 2026-10-05; decisions D1–D12 frozen. This document is added by a docs-only plan PR, and
implementation starts only after that PR is merged (D10). The discovery ran against the final
`main` @ `db604d0`. Every measured claim below comes from runs in a **throwaway copy** of that commit (`git archive`
into the session scratchpad); the repository was not touched. E1 is a **post-submission enhancement**, not part of
the submitted Phase 1/2 scope.

**Goal:** the user picks one of five curated colour palettes (Teal, Blue, Rose, Purple, Orange) from the app bar. The
operating system still picks light or dark. The choice applies at once and is remembered on the device.

**Architecture:** a new feature, `lib/features/appearance/`, with four separate parts:
- a pure palette definition: `domain/app_palette.dart`, the `AppPalette` enum with a stable id, a name and one
  Material seed;
- persistence: the `domain/palette_store.dart` interface and the `data/shared_preferences_palette_store.dart`
  implementation;
- the selected palette's state: `appearance_providers.dart`, where `paletteProvider` is the **one** source of truth;
- presentation: `presentation/palette_theme.dart` and `presentation/palette_menu_button.dart`.

`SmartCommuteApp` watches `paletteProvider` and passes the palette's generated light and dark themes to
`MaterialApp`, still with `ThemeMode.system`. The stored palette is read once, before `runApp`. That read is capped at
500 ms, never throws, and falls back to Teal.

**Tech Stack:** Flutter 3.47.2 (Dart 3.13.2), Material 3, Riverpod 3, **`shared_preferences` 2.5.5** (the one new
dependency), `flutter_test`, `integration_test`, `fake_async`.

**Spec:** the user's E1 brief (2026-10-05) and the frozen decisions D1–D12 (§22). Project rules: `CLAUDE.md`.

---

## 1. Goal and user-visible behaviour

- The app bar gets a palette icon button. Its accessible name and tooltip identify the current choice, for example
  **"Colour theme: Teal"**.
- Tapping it opens a compact Material `MenuAnchor` menu with five choices in this order: **Teal, Blue, Rose, Purple,
  Orange**.
  - Each choice has a radio mark showing the single selection, its name, and a round swatch of that palette's
    primary colour in the current brightness.
  - Choosing one applies it at once and closes the menu.
  - The app recolours with Material's standard theme cross-fade, the same 200 ms one used today when the system
    switches light/dark. Under the system's reduce-motion setting the change lands without in-between frames
    (measured, §5).
- The system decides light or dark. There's no manual light/dark toggle and no hamburger or drawer.
- The choice survives an Android restart and a Web reload. Teal is the default and the fallback.
- Nothing else changes. A palette change while the map is open only recolours it (§10, the map-state contract).

## 2. Current theme architecture (findings on `main` @ `db604d0`)

- **Theme construction.** `lib/app/app.dart` (`SmartCommuteApp`, a `StatelessWidget`) holds two `static final
  ThemeData`s built from `ColorScheme.fromSeed(seedColor: Colors.teal, brightness: …)`. It passes them as `theme` and
  `darkTheme` with `themeMode: ThemeMode.system`, and Material 3 is on by default.
- **Entry point.** `lib/main.dart` calls `runApp(const ProviderScope(retry: noAutomaticRetry, child: SmartCommuteApp()))`.
  Nothing is awaited first.
- **App bar.** `lib/app/home_screen.dart` has `AppBar(title: const AppTitle())` with no actions. `AppTitle` is the logo
  plus the name, and the name ellipsizes.
- **Persistence.** None. The dependencies are `http`, `flutter_riverpod`, `geolocator`, `clock`, `flutter_map`,
  `latlong2`, `url_launcher`, plus the dev-only `fake_async`. None of them stores key-value data on both Android and
  Web.
- **Colour guard.** `test/app/app_theme_test.dart` has a line-scan guard that allows exactly one fixed colour in `lib/`:
  `Colors.teal` in `lib/app/app.dart`.
- **Map.** `JourneyMap` reads `Theme.of(context)`.
  - The tile URL template comes from the brightness only: `basemapTemplateFor(brightness)` gives OneMap Default for
    light and Night for dark.
  - The colours come from the scheme: `surfaceContainerHighest`, `primary`, `tertiary`, `secondary` and `surface`.
  - The camera is refitted only when the `MapScene` changes. `MapScene` has value equality.
  - There's one `TileProvider` for each map opening.
- **Test harness.** `buildTestApp` (`integration_test/fakes/test_app.dart`) builds the real app with every external
  seam faked. No integration test runs the real `main()`.
- **Baseline:** 645 tests, 133 Dart files formatted, analyze clean (PR #48/#49 runs at this code).

## 3. Selector (D3, frozen)

**An AppBar palette icon that opens a `MenuAnchor` of five `RadioMenuButton`s.** There's no hamburger or drawer, and
the button could open a future settings surface instead.

I compared four alternatives:
- `PopupMenuButton` + `CheckedPopupMenuItem`: a checked state, but not a mutually-exclusive group, and it's the older
  API.
- A bottom sheet: odd on wide Web, and it needs closing.
- A dialog: modal, more taps.
- A drawer: unjustified for one setting.

Measured in the prototype, with the VM widget tests running under the android and windows platform variants:

**Semantics.** Each option exposes:
- `hasCheckedState` and `isChecked` (only the selected one);
- `isInMutuallyExclusiveGroup`;
- `hasEnabledState`/`isEnabled` and `isFocusable`;
- the tap and focus actions;
- the palette name as its label. The swatch adds nothing.

The button is a focusable button, named by its tooltip ("Colour theme: Teal"), the same pattern as the existing
"Refresh conditions" button. Plain Material exposed no open/closed state in the prototype. T4 tests it first, and adds
`MergeSemantics(Semantics(expanded:))` only if that test fails with plain Material. No other semantics or focus code
is added.

**Keyboard**
- The palette button is the first Tab stop on Home.
- Enter or Space opens the menu, and focus stays on the button.
- Arrow Down and Arrow Up move through the options, starting from the first, with no wrap.
- Enter selects, closes the menu and returns focus to the button.
- Escape closes the menu with no change and returns focus to the button.
- Arrow Down on the closed button doesn't open it.

**Web.** The real browser keyboard path isn't exercised by VM tests. Task 8 verifies it in Chrome. If Web differs, stop
and report rather than patching ad hoc.

**360 × 780 dp at 2× text:** no overflow. The button is 48 × 48 and fully visible, and the title ellipsizes. All five
options show on screen without scrolling.

## 4. The five palettes and their seeds (D1, D2, D12, frozen)

| Order | Id (stored) | Name | Seed | Light `primary` | Dark `primary` |
|---|---|---|---|---|---|
| 1 | `teal` | Teal (default) | `Color(0xFF009688)` | `#006A60` | `#82D5C8` |
| 2 | `blue` | Blue | `Color(0xFF0288D1)` | `#2E628C` | `#9BCBFA` |
| 3 | `rose` | Rose | `Color(0xFFE91E63)` | `#8E4957` | `#FFB2BE` |
| 4 | `purple` | Purple | `Color(0xFF9C27B0)` | `#7B4E7F` | `#EBB5ED` |
| 5 | `orange` | Orange | `Color(0xFFFF9800)` | `#855318` | `#FDB975` |

- **Teal is unchanged.** `Color(0xFF009688)` is `Colors.teal`'s value, and `ColorScheme.fromSeed` uses only the ARGB
  value. I measured `ColorScheme.fromSeed(seedColor: Color(0xFF009688)) == ColorScheme.fromSeed(seedColor: Colors.teal)`
  as true in light and dark, and Task 1 pins it with a test.
- **Distinctness** (perceptual ΔE in CIELAB between the primaries, measured):
  - The closest pair is **Rose–Purple, 25.3 (light) / 25.6 (dark)**. The previous Blue–Indigo pair was about 15.
  - The others are 32–75. The light-mode values are teal–blue 36.6, blue–purple 31.9, rose–orange 38.7, blue–rose
    47.6, and teal–rose 59.6.
- **Orange (D2).** It's derived from the seed only, with no hand-tuned roles. Material 3's light scheme turns it a
  golden brown (`#855318`), which is accepted.
- **Every scheme comes from its seed alone.** The default `tonalSpot` variant is used, and no Material role is
  overridden.

## 5. Contrast and motion findings (measured, final set)

Contrast was computed for each pair from `ColorScheme.fromSeed` for all five palettes, light and dark. Text needs 4.5:1
and non-text UI needs 3:1.

| Pair (where it's used) | Light (5 palettes) | Dark (5 palettes) |
|---|---|---|
| `onPrimary` / `primary` (the service badge) | 6.47–6.50 | 7.70–7.76 |
| `primary` / `surfaceContainerLow` (the "Selected" mark and text buttons on cards: "Show steps", "Refresh arrivals", "Change", attribution links) | 5.84–5.89 | 10.03–10.12 |
| `primary` / `surface` | 6.15–6.19 | 10.83–10.94 |
| `onPrimaryContainer` / `primaryContainer` | 7.22–7.26 | 7.22–7.26 |
| `onSecondaryContainer` / `secondaryContainer` (Conditions band chips, tonal buttons) | 7.22–7.25 | 7.22–7.25 |
| `onTertiaryContainer` / `tertiaryContainer` | 7.20–7.25 | 7.20–7.25 |
| `error` / `surfaceContainerLow` ("Out of date") | 5.82–5.85 | 10.08–10.12 |
| `onSurfaceVariant` / `surfaceContainerHighest` (search hints) | 7.20–7.23 | 7.23–7.29 |
| `onSurfaceVariant` / `surfaceContainerLow` (secondary text on cards) | 8.39–8.45 | 10.06–10.12 |
| `outline` / `surfaceContainerLow` (outlined "Select" and "Show map" borders, 3:1) | **4.03–4.07** | 5.39–5.41 |
| `primary`, `tertiary`, `secondary` / `surface` (map pins on their surface disc; the route and walk lines inside their surface halo, 3:1) | 6.11–6.19 | 10.83–10.96 |
| `onSurface` / `surface` (the app bar and body text) | 16.26–16.38 | 14.28–14.38 |

**Result: 0 failures across the 14 tested pairs × 5 palettes × light/dark.** The minimum observed ratio is 4.03:1,
against its 3:1 target (Purple, light, an outline on a card), and every text pair is 5.8:1 or higher. Rose introduces
no failing pair, and nothing is hand-tuned.

**Motion (D8).** The palette change uses `MaterialApp`'s existing `AnimatedTheme`. This was measured in the prototype
with 16 ms frames after a change to Rose:
- **Normal motion:** 12 in-between colour frames; the new colour is reached about 14 frames (≈220 ms) after the change.
- **Reduce motion** (`disableAnimations`): **0 in-between frames.** The frames are old then new. Flutter shortens
  implicit animations under that setting, so no custom handling is needed. Task 3 pins both.

## 6. State ownership (D9)

There is **exactly one** source of truth: `paletteProvider` (`NotifierProvider<PaletteController, AppPalette>`).
- `SmartCommuteApp` (a `ConsumerWidget`) is its only theme consumer.
- The menu reads it and calls `PaletteController.select`. The menu holds no palette state.
- `initialPaletteProvider` (`Provider<AppPalette>`, default Teal) seeds `build()`. `main()` and `buildTestApp` override
  it.
- `paletteStoreProvider` (`Provider<PaletteStore>`) is the persistence seam: the real store in production and
  `FakePaletteStore` in `buildTestApp`.
- Every other widget keeps reading `Theme.of(context).colorScheme`.

`palette × system brightness → paletteTheme(palette, brightness)`. Brightness is never stored and never set by this
feature.

## 7. Persistence (D4, D12, frozen)

**Dependency.** `shared_preferences: 2.5.5`, pinned exactly in `pubspec.yaml`. It resolves offline from the local cache, together with
_android 2.4.23, _web 2.4.3, _platform_interface 2.4.2, _foundation 2.5.6, _linux 2.4.1 and _windows 2.4.1. There's no
new dev_dependency.

**API.** `SharedPreferencesAsync`. It's created lazily inside the async calls: without a platform implementation (a
plain `flutter test`) its constructor throws, and lazy creation turns that into a failed Future that the callers
handle. This was measured.

**Where the value lives**
- **Android:** app-private storage, through the plugin's DataStore-backed async implementation. It's cleared by
  uninstall or "Clear storage". Auto Backup may restore it after a reinstall, which is harmless.
- **Web:** `window.localStorage` for the page's origin. Each origin has its own, a private window forgets it on close,
  and if the browser blocks storage the read or write fails (§9).
- Nothing else: no network, no new host, no CSP change, no account, no cloud sync, no secret.

**The contract (D12)**
- Key: `colour_palette`.
- Value: one id, `teal`, `blue`, `rose`, `purple` or `orange`.
- Never stored: the display names, seed integers, `ThemeData` or the brightness.

**Testing.** Every app test uses `FakePaletteStore` in memory, through the `buildTestApp` default, so no test touches
real storage. The real store has one test, which needs no extra dependency: without a platform implementation its calls
fail as Futures and startup falls back to Teal.

## 8. Startup (D5, frozen)

```text
main()
  WidgetsFlutterBinding.ensureInitialized()
  palette = await loadInitialPalette(SharedPreferencesPaletteStore())   // ≤ AppearanceConfig.paletteLoadTimeout (500 ms), never throws
  runApp(ProviderScope(overrides: [initialPaletteProvider.overrideWithValue(palette)], child: SmartCommuteApp()))
```

- **No Teal → saved-palette flash.** The first frame is already in the saved palette, while the native splash or the
  Flutter Web loader covers the read.
- **Bounded.** `store.read().timeout(timeout)`. On a timeout the result is Teal, and the startup future completes at
  500 ms.
- **A late result can't recolour the running session.** It goes to an abandoned future that nothing listens to, and
  the running app never reads the store again; only startup does. Measured: a read completed with `purple` after the
  timeout leaves startup on Teal and the running app Teal. The stored value is picked up on the next launch.
- **Deterministic.** The timeout is a parameter (default `AppearanceConfig.paletteLoadTimeout`, in `app_config.dart`).
  Tests drive it with `fakeAsync` and a controllable `Completer` in `FakePaletteStore`.
- **No splash or loading screen** is added.

## 9. Storage failure behaviour (D5, D6, frozen)

| Case | Behaviour |
|---|---|
| Nothing stored | Teal |
| A stored valid id | That palette from the first frame |
| An unknown or old id (for example `indigo`, `magenta`, or a name such as `Purple`) | Teal. The stored value is left alone until the user chooses |
| The read throws | Teal; the app starts normally (debug log only) |
| The read hangs | Teal after 500 ms; a late result is ignored for that session |
| The write throws | **Silent** (D6): no SnackBar. The chosen palette stays active for the session and the app stays usable. Nothing claims it was saved. The next launch shows whatever storage actually holds (the previous palette, or Teal). Choosing again retries the write |
| No platform implementation | The same as "the read throws" and "the write throws" |

## 10. Map-state contract (measured in the prototype; Task 5 pins it)

Changing the palette while the map is open must preserve:
- the map's expanded state;
- the selected bus option;
- the current `FlutterMap` (and `JourneyMap`) `State`;
- the camera centre and zoom, including a manual pan;
- the planner result, which is the same plan object;
- the arrival state;
- the loaded route geometry.

A palette change causes:
- **0** new journey plans;
- **0** arrival refetches;
- **0** extra `routes.min.json` loads;
- **0** map refits;
- **0** new tile requests.

**The basemap follows brightness only:** system light gives Default and system dark gives Night. Teal → Rose in light
mode stays on Default on every cross-fade frame, and a palette change in dark mode stays on Night.

Why no map change is needed:
- A theme change keeps every element and `State`.
- `JourneyMap.didUpdateWidget` calls `_fitLatest()`, which returns early because the `MapScene` is equal.
- The `TileLayer` template doesn't change with the palette.
- No provider depends on the palette.

Prototype measurements (Teal → Purple, map open, panned 80 px):

| | Result |
|---|---|
| `FlutterMap` / `JourneyMap` `State` | Identical |
| Camera | Unchanged |
| Tiles | 28 → 28 |
| Loads (bus, arrivals, geometry) | (1, 2, 1) → (1, 2, 1) |
| Selection and map card | Kept |
| Cross-fade frames | 15, with no exception |
| Then light → dark | Night tiles (28 → 56, a full Night set) with the same `State` and camera |

If an implementation step shows the architecture breaking this contract, **stop and report** rather than changing the
map.

## 11. Colour guard (frozen approach)

The existing line-scan guard is updated, not removed, and it adds no parser or dependency.

**Allowed.** A fixed colour only on a seed line in `lib/features/appearance/domain/app_palette.dart`, matching
`<value>('<id>', '<label>', Color(0xAARRGGBB)),` for a value that compiles. There are **exactly five** such seeds, and
`AppPalette.values` has length 5.

**Rejected anywhere else in `lib/`:** any `Colors.*`, `Color(…)` or `Color.from…(…)`. There's no `Colors.*` left in
`lib/` at all; even Teal becomes `Color(0xFF009688)`.

**Pinned by tests** (Task 1):
- the exact id list `teal, blue, rose, purple, orange`;
- the ids are unique;
- the exact approved seed values.

**The guard's self-checks**, run on a copy of `lib/`, must catch:
- G1: a fixed colour in the palette file off a seed line;
- G2: `Colors.teal` reintroduced in `app.dart`;
- G3: a seed-like line for a value that isn't in the enum;
- G4: a stray `Color(` in `home_screen.dart` (the seed count stays 5).

## 12. Files and dependencies expected to change

| File | Change | Task |
|---|---|---|
| `pubspec.yaml`, `pubspec.lock` | `shared_preferences: 2.5.5` (pinned exactly; the only dependency change) | 2 |
| `lib/core/config/app_config.dart` | `AppearanceConfig.paletteLoadTimeout = Duration(milliseconds: 500)` | 2 |
| `lib/features/appearance/domain/app_palette.dart` | **Create** | 1 |
| `lib/features/appearance/domain/palette_store.dart` | **Create** | 2 |
| `lib/features/appearance/data/shared_preferences_palette_store.dart` | **Create** | 2 |
| `lib/features/appearance/appearance_providers.dart` | **Create**: `loadInitialPalette` (Task 2); the providers and `PaletteController` (Task 3) | 2, 3 |
| `lib/features/appearance/presentation/palette_theme.dart` | **Create** | 1 |
| `lib/features/appearance/presentation/palette_menu_button.dart` | **Create** | 4 |
| `lib/app/app.dart` | Themes from `paletteTheme`; the static themes removed (Task 1); a `ConsumerWidget` watching `paletteProvider` (Task 3) | 1, 3 |
| `lib/main.dart` | Async `main`: the bounded read, then the override | 3 |
| `lib/app/home_screen.dart` | `AppBar(actions: const [PaletteMenuButton()])` | 4 |
| `integration_test/fakes/fake_palette_store.dart` | **Create** | 2 |
| `integration_test/fakes/test_app.dart` | `paletteStore` (default `FakePaletteStore()`) and `palette` (default Teal) | 3 |
| `test/features/appearance/app_palette_test.dart` | **Create** | 1 |
| `test/app/app_theme_test.dart` | Rewritten: per-palette themes, Teal unchanged, the new guard and its self-checks | 1 |
| `test/features/appearance/load_initial_palette_test.dart` | **Create** | 2 |
| `test/features/appearance/palette_controller_test.dart` | **Create** | 3 |
| `test/app/palette_app_test.dart` | **Create** | 3 |
| `test/features/appearance/palette_menu_button_test.dart` | **Create** | 4 |
| `test/features/appearance/palette_change_invariants_test.dart` | **Create** | 5 |
| `README.md`, `CLAUDE.md`, `docs/architecture.md`, `docs/assumptions.md` | §17 | 6 |
| `docs/testing.md` | Run-log rows; an E1 open-items entry | 0–8 |
| `docs/e1-colour-themes-implementation-plan.md` | This plan, in the docs-only plan PR (D10) | plan PR |

**Unchanged:**
- `web/index.html` (CSP);
- everything in the journey, map, bus_arrival, environment, places, origin and destination features;
- `lib/core/http` and `lib/core/location`;
- the integration test files (only the shared fakes change);
- every historical plan document.

## 13. Types, providers and interfaces

```dart
// domain/app_palette.dart (imports only dart:ui Color)
enum AppPalette { teal, blue, rose, purple, orange } // String id, String label, Color seed
static const AppPalette fallback = AppPalette.teal;
static AppPalette fromId(String? id);               // unknown or null → fallback

// domain/palette_store.dart
abstract interface class PaletteStore { Future<String?> read(); Future<void> write(String id); }

// data/shared_preferences_palette_store.dart
class SharedPreferencesPaletteStore implements PaletteStore { static const String key = 'colour_palette'; }

// appearance_providers.dart
Future<AppPalette> loadInitialPalette(PaletteStore store, {Duration timeout = AppearanceConfig.paletteLoadTimeout});
final initialPaletteProvider = Provider<AppPalette>(...);   // default AppPalette.fallback
final paletteStoreProvider = Provider<PaletteStore>(...);   // default SharedPreferencesPaletteStore()
final paletteProvider = NotifierProvider<PaletteController, AppPalette>(PaletteController.new);
class PaletteController extends Notifier<AppPalette> { Future<void> select(AppPalette palette); }

// presentation/palette_theme.dart
ThemeData paletteTheme(AppPalette palette, Brightness brightness); // built once per pair

// presentation/palette_menu_button.dart
class PaletteMenuButton extends ConsumerWidget { static String tooltipFor(AppPalette p); } // 'Colour theme: <label>'
class PaletteSwatch extends StatelessWidget { final Color color; }

// core/config/app_config.dart
abstract final class AppearanceConfig { static const Duration paletteLoadTimeout = Duration(milliseconds: 500); }

// integration_test/fakes/fake_palette_store.dart
class FakePaletteStore implements PaletteStore {
  String? stored; bool failRead; bool failWrite; Completer<String?>? pendingRead; int reads; List<String> writes;
}
```

The keys are `palette-button` and `palette-option-<id>`. `RadioMenuButton` passes its key on to its inner
`MenuItemButton`, so tests use `.first`.

---

## Global Constraints

- **The palette set (D1).** Teal `0xFF009688`, Blue `0xFF0288D1`, Rose `0xFFE91E63`, Purple `0xFF9C27B0`, Orange
  `0xFFFF9800`, in that order. No Indigo. Teal is the default and reproduces today's scheme exactly.
- **Schemes (D2).** Derived from the seed only, through `ColorScheme.fromSeed` (default variant), with no Material role
  hand-tuned.
- **One new dependency (D4):** `shared_preferences` 2.5.5. No backend, account, network request, new host, CSP change,
  cloud sync or secret.
- **Storage (D12).** Key `colour_palette`; ids `teal`, `blue`, `rose`, `purple`, `orange`. Never store names, seeds,
  `ThemeData` or the brightness.
- **Brightness is the system's** (`ThemeMode.system`). There's no manual light/dark control and no hamburger or drawer.
- **Startup (D5).** A bounded 500 ms read before `runApp`; never throws; Teal on a missing or unknown value, an error or
  a timeout. A late result never recolours the running session. No splash or loading screen.
- **A failed write (D6)** is silent. The in-memory choice stays for the session, and nothing claims it was saved.
- **Announcements (D7).** No extra live-region announcement: the radio's checked state and the button's updated name
  carry it.
- **The transition (D8):** `MaterialApp`'s existing theme cross-fade. No custom colour animation. Under reduce motion
  there are no in-between frames.
- **One source of truth (D9):** `paletteProvider` in `lib/features/appearance/`. The domain, persistence, state and
  presentation stay separate.
- **The colour guard** stays and tightens (§11): exactly the five seed lines; every other fixed colour in `lib/` fails.
- **The map-state contract** (§10): no map architecture change. If the contract fails, stop and report.
- Don't change the planner, scoring, arrivals, walking estimates, MRT, option selection, map scene or data flow, route
  geometry, map loading, session caching, routing, or any provider outside `features/appearance/`. Keep every existing
  widget `Key` and every P2-M3, P2-M4 and accessibility behaviour.
- **Tests.** The starting point is the existing **645**, and it stays green. `app_theme_test.dart` is rewritten to cover
  more, not less. No test touches real device or browser storage or calls a live API.
- **No TalkBack pass is required (D11).** The evidence is deterministic semantics tests plus the Web keyboard and
  semantics checks.
- **Evidence rule.** Log every command and its real result in `docs/testing.md`. Anything not run is **Not run**, with
  the reason.
- **Git (D10).** The docs-only plan PR is reviewed and merged first. Then `feat/e1-colour-themes` from `origin/main`.
  Small commits, never to `main`, no force-push or amend. Every commit ends with `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>`.
- **Host.** Long runs go in the foreground with `timeout 590`. Before an Android run, check host memory (about 3 GB or
  more free) and the emulator's health. Never touch `emulator-5554`. Ask before stopping a process or rebooting.

## Review Focus

1. **A palette change while the map is open and panned, in light then dark:** nothing is re-planned, refetched,
   reloaded or refitted, and only the colours change. Pinned by Task 5 (mutations M6, M7, M10).
2. **A stored id that no longer exists (for example `indigo`), or storage that's blocked, slow or late:** the app
   starts in Teal, without a hang beyond 500 ms, and a late value never recolours it. Pinned by Task 2 and Task 3.
3. **A failed write:** the choice stays for the session, the app stays usable, and a restart shows what storage really
   holds. Pinned by Task 3 (M1).
4. **The system switching light or dark after a palette was chosen:** the palette is kept, and only the brightness and
   tiles change. Pinned by Task 3 and Task 5.
5. **Keyboard and screen-reader users, at 2× text on a 360 dp phone:** the button is named and exposes open/closed,
   the radio states are exposed, the menu is operable by keyboard, and nothing overflows. Pinned by Task 4, and on Web
   by Task 8.

---

## 14. Task sequence (test-first)

**Expected test counts are estimates, not gates.** They're worked out from the tests below. Each task's gate is
"the full suite passes", and the real count from each run is what goes in `docs/testing.md`.

| After | Tests (expected estimate) |
|---|---|
| T0 baseline | 645 |
| T1 | 656 (+5 in `app_palette_test`; `app_theme_test` goes from 4 to 10 tests, +6) |
| T2 | 667 (+11) |
| T3 | 689 (+3 controller, +19 app) |
| T4 | 696 (+7: the keyboard test counts twice, for the android and windows variants) |
| T5 | 698 (+2) |

### Task 0: Baseline (after the plan PR is merged)

**Files:** `docs/testing.md` (one row).

- [ ] **Step 1:** Prepare the branch.
  ```bash
  git fetch --prune origin
  git switch main && git merge --ff-only origin/main
  git status --porcelain                 # expect: empty
  git switch -c feat/e1-colour-themes origin/main && git branch --unset-upstream
  flutter pub get
  ```
- [ ] **Step 2:** Run the gates in the foreground: `dart format --set-exit-if-changed .`, `flutter analyze` and
  `timeout 590 flutter test`. Expect 133 files with 0 changed, no issues, and **645/645**. If anything fails, stop and
  report.
- [ ] **Step 3:** Log the row ("E1 T0: baseline on `feat/e1-colour-themes` from `origin/main` `<sha>`"), then commit:
  `git commit -m "docs(testing): E1 baseline" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"`.

### Task 1: Palettes, their themes and the colour guard

**Files:**
- Create: `lib/features/appearance/domain/app_palette.dart`, `lib/features/appearance/presentation/palette_theme.dart`,
  `test/features/appearance/app_palette_test.dart`
- Modify: `lib/app/app.dart`, `test/app/app_theme_test.dart`

**Interfaces:** produces `AppPalette` (`id`, `label`, `seed`, `fallback`, `fromId`) and
`paletteTheme(AppPalette, Brightness) → ThemeData`.

- [ ] **Step 1: Write the failing tests.** `test/features/appearance/app_palette_test.dart`:

  ```dart
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';

  void main() {
    test('the stored ids are stable and in menu order', () {
      // Stored on devices: never rename or reuse one.
      expect(AppPalette.values.map((p) => p.id), [
        'teal',
        'blue',
        'rose',
        'purple',
        'orange',
      ]);
    });

    test('the stored ids are unique', () {
      expect(
        AppPalette.values.map((p) => p.id).toSet(),
        hasLength(AppPalette.values.length),
      );
    });

    test('each palette has its display name', () {
      expect(AppPalette.values.map((p) => p.label), [
        'Teal',
        'Blue',
        'Rose',
        'Purple',
        'Orange',
      ]);
    });

    test('the seeds are exactly the five approved values', () {
      expect(AppPalette.values.map((p) => p.seed.toARGB32()), [
        0xFF009688,
        0xFF0288D1,
        0xFFE91E63,
        0xFF9C27B0,
        0xFFFF9800,
      ]);
    });

    test('fromId: each stored id; teal for nothing, an unknown id or a name', () {
      for (final p in AppPalette.values) {
        expect(AppPalette.fromId(p.id), p);
      }
      expect(AppPalette.fallback, AppPalette.teal);
      expect(AppPalette.fromId(null), AppPalette.teal);
      expect(AppPalette.fromId('indigo'), AppPalette.teal, reason: 'never shipped');
      expect(AppPalette.fromId('magenta'), AppPalette.teal);
      expect(AppPalette.fromId('Purple'), AppPalette.teal, reason: 'a name is not an id');
    });
  }
  ```

  Replace `test/app/app_theme_test.dart` with:

  ```dart
  import 'dart:io';

  import 'package:flutter/material.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sg_smart_commute/app/home_screen.dart';
  import 'package:sg_smart_commute/core/location/location_service.dart';
  import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
  import 'package:sg_smart_commute/features/appearance/presentation/palette_theme.dart';

  import '../../integration_test/fakes/fake_environment_repository.dart';
  import '../../integration_test/fakes/fake_location_service.dart';
  import '../../integration_test/fakes/test_app.dart';

  const paletteFile = 'features/appearance/domain/app_palette.dart';

  /// Fixed colours in the .dart files under [lib], as `lib/<path>:<line> <match>`.
  /// Colors.x, Color(…) and Color.from…(…) in code; text after `//` is dropped
  /// as a comment. ponytail: a line scan, not a Dart parser — `//` inside a
  /// string hides the rest of that line, and a /* block */ comment is scanned.
  /// Add a parser only if that ever misleads.
  List<String> fixedColours(Directory lib) {
    final fixed = RegExp(r'Colors\s*\.\s*\w+|\bColor\s*(?:\.\s*from\w*\s*)?\(');
    final found = <String>[];
    for (final file in lib.listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final code = file
          .readAsLinesSync()
          .map((line) => line.split('//').first)
          .join('\n');
      final path = 'lib/${file.path.substring(lib.path.length + 1)}'
          .replaceAll(r'\', '/');
      for (final m in fixed.allMatches(code)) {
        final line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
        found.add('$path:$line ${m[0]}');
      }
    }
    return found;
  }

  /// The seeds: one `Color(0x…)` on each compiled AppPalette value's own line
  /// in [paletteFile]; everything else is a stray fixed colour.
  ({List<String> seeds, List<String> others}) splitSeeds(Directory lib) {
    final lines = File('${lib.path}/$paletteFile').readAsLinesSync();
    final at = RegExp('^lib/${RegExp.escape(paletteFile)}:(\\d+) Color\\(\$');
    bool isSeed(String found) {
      final m = at.firstMatch(found);
      if (m == null) return false;
      final line = lines[int.parse(m[1]!) - 1].trim();
      return AppPalette.values.any(
        (p) => RegExp(
          "^${p.name}\\('${p.id}', '${RegExp.escape(p.label)}', "
          r'Color\(0x[0-9A-F]{8}\)\)[,;]$',
        ).hasMatch(line),
      );
    }

    final found = fixedColours(lib);
    return (
      seeds: found.where(isSeed).toList(),
      others: found.where((f) => !isSeed(f)).toList(),
    );
  }

  /// A copy of lib/ in a temporary directory, for the guard's own checks.
  Directory copyOfLib() {
    final tmp = Directory.systemTemp.createTempSync('lib-copy');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final lib = Directory('${tmp.path}/lib');
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File) continue;
      final to = File('${lib.path}/${f.path.substring('lib'.length + 1)}');
      to.parent.createSync(recursive: true);
      f.copySync(to.path);
    }
    return lib;
  }

  void main() {
    test('every palette: light and dark schemes from its one seed', () {
      for (final p in AppPalette.values) {
        for (final b in Brightness.values) {
          final theme = paletteTheme(p, b);
          expect(theme.brightness, b);
          expect(
            theme.colorScheme,
            ColorScheme.fromSeed(seedColor: p.seed, brightness: b),
          );
          expect(identical(theme, paletteTheme(p, b)), isTrue, reason: 'built once');
        }
      }
    });

    test("the default palette is today's teal theme, unchanged", () {
      for (final b in Brightness.values) {
        expect(
          paletteTheme(AppPalette.fallback, b).colorScheme,
          ColorScheme.fromSeed(seedColor: Colors.teal, brightness: b),
        );
      }
    });

    test('the five palettes look different in light and dark', () {
      for (final b in Brightness.values) {
        expect(
          AppPalette.values.map((p) => paletteTheme(p, b).colorScheme.primary).toSet(),
          hasLength(AppPalette.values.length),
        );
      }
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
        expect(
          Theme.of(context).colorScheme,
          paletteTheme(AppPalette.teal, brightness).colorScheme,
        );
      });
    }

    test('lib/ takes its colours from the theme scheme; the five palette seeds '
        'are the only fixed colours', () {
      final split = splitSeeds(Directory('lib'));
      expect(AppPalette.values, hasLength(5));
      expect(split.seeds, hasLength(5), reason: 'one seed declaration per palette');
      expect(
        split.others,
        isEmpty,
        reason: 'take colours from Theme.of(context).colorScheme',
      );
    });

    group('the colour guard catches', () {
      test('a fixed colour in the palette file off a seed line', () {
        final lib = copyOfLib();
        File('${lib.path}/$paletteFile').writeAsStringSync(
          '\nconst extra = Color(0xFF000000);\n',
          mode: FileMode.append,
        );
        expect(splitSeeds(lib).others, hasLength(1));
      });

      test('Colors.teal brought back into app.dart', () {
        final lib = copyOfLib();
        File('${lib.path}/app/app.dart').writeAsStringSync(
          '\nconst seed = Colors.teal;\n',
          mode: FileMode.append,
        );
        expect(splitSeeds(lib).others, [matches(r'^lib/app/app\.dart:\d+ Colors\.teal$')]);
      });

      test('a seed-like line for a value that is not in the enum', () {
        final lib = copyOfLib();
        File('${lib.path}/$paletteFile').writeAsStringSync(
          "\n  indigo('indigo', 'Indigo', Color(0xFF3F51B5)),\n",
          mode: FileMode.append,
        );
        expect(splitSeeds(lib).others, hasLength(1));
      });

      test('a stray Color( elsewhere in lib/', () {
        final lib = copyOfLib();
        File('${lib.path}/app/home_screen.dart').writeAsStringSync(
          '\nconst stray = Color(0xFF123456);\n',
          mode: FileMode.append,
        );
        final split = splitSeeds(lib);
        expect(split.others, [matches(r'^lib/app/home_screen\.dart:\d+ Color\($')]);
        expect(split.seeds, hasLength(5));
      });
    });
  }
  ```

  The guard's self-checks append text, some of it not valid Dart, to a temporary copy of `lib/`. Nothing compiles the
  copy.

- [ ] **Step 2: See them fail.** Run `timeout 590 flutter test test/features/appearance/app_palette_test.dart
  test/app/app_theme_test.dart`. Expect a compile failure, because the two new library files don't exist yet.

- [ ] **Step 3: Implement.** `lib/features/appearance/domain/app_palette.dart`:

  ```dart
  import 'dart:ui' show Color;

  /// The curated colour palettes (E1). Material 3 generates each one's light
  /// and dark schemes from its seed alone; the system still picks the
  /// brightness. The seeds are the only fixed colours in lib/
  /// (test/app/app_theme_test.dart).
  enum AppPalette {
    teal('teal', 'Teal', Color(0xFF009688)),
    blue('blue', 'Blue', Color(0xFF0288D1)),
    rose('rose', 'Rose', Color(0xFFE91E63)),
    purple('purple', 'Purple', Color(0xFF9C27B0)),
    orange('orange', 'Orange', Color(0xFFFF9800));

    const AppPalette(this.id, this.label, this.seed);

    /// What is stored on the device. Never rename or reuse one: a stored id
    /// that matches no palette becomes [fallback].
    final String id;

    /// The name shown in the selector; free to change.
    final String label;

    /// The Material 3 seed (teal is `Colors.teal`'s value, so the default
    /// theme is unchanged).
    final Color seed;

    /// The default, and what any unknown or unreadable stored value becomes.
    static const AppPalette fallback = teal;

    static AppPalette fromId(String? id) {
      for (final p in values) {
        if (p.id == id) return p;
      }
      return fallback;
    }
  }
  ```

  `lib/features/appearance/presentation/palette_theme.dart`:

  ```dart
  import 'package:flutter/material.dart';

  import '../domain/app_palette.dart';

  final _themes = <(AppPalette, Brightness), ThemeData>{};

  /// The app theme for [palette] in [brightness]: the Material 3 scheme from
  /// the palette's one seed (no role tuned by hand), built once each. Widgets
  /// take colours only from the scheme, never fixed values.
  ThemeData paletteTheme(AppPalette palette, Brightness brightness) =>
      _themes[(palette, brightness)] ??= ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: palette.seed,
          brightness: brightness,
        ),
      );
  ```

  In `lib/app/app.dart`:
  - import `../features/appearance/domain/app_palette.dart` and `../features/appearance/presentation/palette_theme.dart`;
  - delete `lightTheme`, `darkTheme` and `_theme`;
  - in `build`, pass `theme: paletteTheme(AppPalette.fallback, Brightness.light)` and
    `darkTheme: paletteTheme(AppPalette.fallback, Brightness.dark)`;
  - keep `themeMode: ThemeMode.system`.

- [ ] **Step 4: See them pass.** Run the two files (PASS), then the full gates: format, analyze and `timeout 590
  flutter test`. The expected count is about 656 (an estimate); record the real one.
- [ ] **Step 5: Mutation G0.** Temporarily put `Colors.teal` back as the seed in `app.dart`; the guard test must FAIL.
  Restore it, then check that `git diff --stat` lists only this task's files.
- [ ] **Step 6: Log and commit:** `feat(appearance): five curated palettes, each theme generated from one seed`.

### Task 2: Remembering the palette, with a bounded startup read

**Files:**
- Create: `lib/features/appearance/domain/palette_store.dart`,
  `lib/features/appearance/data/shared_preferences_palette_store.dart`,
  `lib/features/appearance/appearance_providers.dart`, `integration_test/fakes/fake_palette_store.dart`,
  `test/features/appearance/load_initial_palette_test.dart`
- Modify: `pubspec.yaml`, `pubspec.lock` (`flutter pub add shared_preferences:2.5.5`, pinned exactly),
  `lib/core/config/app_config.dart`

**Interfaces:** consumes `AppPalette`. Produces `PaletteStore`, `SharedPreferencesPaletteStore`,
`loadInitialPalette(PaletteStore, {Duration timeout})`, `AppearanceConfig.paletteLoadTimeout` and `FakePaletteStore`.

- [ ] **Step 1: Write the failing tests.** `test/features/appearance/load_initial_palette_test.dart`:

  ```dart
  import 'dart:async';

  import 'package:fake_async/fake_async.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sg_smart_commute/core/config/app_config.dart';
  import 'package:sg_smart_commute/features/appearance/appearance_providers.dart';
  import 'package:sg_smart_commute/features/appearance/data/shared_preferences_palette_store.dart';
  import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';

  import '../../../integration_test/fakes/fake_palette_store.dart';

  void main() {
    for (final p in AppPalette.values) {
      test('stored ${p.id} → ${p.label}', () async {
        expect(await loadInitialPalette(FakePaletteStore(stored: p.id)), p);
      });
    }

    test('nothing stored → teal', () async {
      expect(await loadInitialPalette(FakePaletteStore()), AppPalette.teal);
    });

    test('an unknown id → teal, and the stored value is left alone', () async {
      final store = FakePaletteStore(stored: 'indigo');
      expect(await loadInitialPalette(store), AppPalette.teal);
      expect(store.stored, 'indigo');
      expect(store.writes, isEmpty);
    });

    test('a failing read → teal, no exception', () async {
      expect(await loadInitialPalette(FakePaletteStore(failRead: true)), AppPalette.teal);
    });

    test('a read that never completes → teal at the timeout, not before', () {
      expect(AppearanceConfig.paletteLoadTimeout, const Duration(milliseconds: 500));
      fakeAsync((async) {
        AppPalette? got;
        loadInitialPalette(
          FakePaletteStore(pendingRead: Completer<String?>()),
        ).then((p) => got = p);
        async.elapse(const Duration(milliseconds: 499));
        expect(got, isNull);
        async.elapse(const Duration(milliseconds: 1));
        expect(got, AppPalette.teal);
      });
    });

    test('a read that completes after the timeout does not change the result', () {
      fakeAsync((async) {
        final lateRead = Completer<String?>();
        AppPalette? got;
        loadInitialPalette(FakePaletteStore(pendingRead: lateRead)).then((p) => got = p);
        async.elapse(const Duration(milliseconds: 500));
        expect(got, AppPalette.teal);
        lateRead.complete('purple'); // arrives too late
        async.elapse(const Duration(seconds: 1));
        expect(got, AppPalette.teal);
      });
    });

    test('the shared_preferences store without a platform implementation: its '
        'calls fail as Futures, so startup falls back to teal', () async {
      final store = SharedPreferencesPaletteStore(); // must not throw here
      await expectLater(store.read(), throwsA(anything));
      await expectLater(store.write('blue'), throwsA(anything));
      expect(await loadInitialPalette(store), AppPalette.teal);
    });
  }
  ```

- [ ] **Step 2: See them fail** (compile errors: the files don't exist yet). Run
  `timeout 590 flutter test test/features/appearance/load_initial_palette_test.dart`.
- [ ] **Step 3: Implement.** Run `flutter pub add shared_preferences:2.5.5`, then check that `pubspec.yaml` reads
  `shared_preferences: 2.5.5` and record the resolved versions in `pubspec.lock`. If anything other than 2.5.5 resolves,
  stop and report.

  In `app_config.dart`, after `AppMotion`:

  ```dart
  abstract final class AppearanceConfig {
    /// The longest startup waits for the stored colour palette (E1) before it
    /// shows the default. The read is local, normally a few milliseconds.
    static const Duration paletteLoadTimeout = Duration(milliseconds: 500);
  }
  ```

  `lib/features/appearance/domain/palette_store.dart`:

  ```dart
  /// Where the chosen palette's id is kept between launches (E1): on this
  /// device only; the value is not sensitive.
  abstract interface class PaletteStore {
    /// The stored id, or null if none was stored.
    Future<String?> read();

    Future<void> write(String id);
  }
  ```

  `lib/features/appearance/data/shared_preferences_palette_store.dart`:

  ```dart
  import 'package:shared_preferences/shared_preferences.dart';

  import '../domain/palette_store.dart';

  /// [PaletteStore] on shared_preferences: app storage on Android, the
  /// browser's localStorage on Web. Nothing leaves the device.
  class SharedPreferencesPaletteStore implements PaletteStore {
    static const String key = 'colour_palette';

    // Created on first use, inside the async calls: without a platform
    // implementation the constructor throws, which then surfaces as a failed
    // Future that every caller already handles.
    late final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

    @override
    Future<String?> read() async => _prefs.getString(key);

    @override
    Future<void> write(String id) async => _prefs.setString(key, id);
  }
  ```

  `lib/features/appearance/appearance_providers.dart`, with Task 2's part only:

  ```dart
  import 'package:flutter/foundation.dart';

  import '../../core/config/app_config.dart';
  import 'domain/app_palette.dart';
  import 'domain/palette_store.dart';

  /// The stored palette for startup: [AppPalette.fallback] when nothing is
  /// stored, the id is unknown, the read fails or it takes longer than
  /// [timeout]. Never throws, so storage can never stop or stall the app; a
  /// result that arrives after [timeout] is ignored (it goes to an abandoned
  /// future), so it never recolours the session that already started.
  Future<AppPalette> loadInitialPalette(
    PaletteStore store, {
    Duration timeout = AppearanceConfig.paletteLoadTimeout,
  }) async {
    try {
      return AppPalette.fromId(await store.read().timeout(timeout));
    } catch (e) {
      debugPrint('Colour palette not loaded: $e');
      return AppPalette.fallback;
    }
  }
  ```

  `integration_test/fakes/fake_palette_store.dart`:

  ```dart
  import 'dart:async';

  import 'package:sg_smart_commute/features/appearance/domain/palette_store.dart';

  /// The palette store in memory. [failRead] / [failWrite] make those calls
  /// throw; with [pendingRead] a read waits for that completer (never
  /// completed: a hang; completed later: a late result).
  class FakePaletteStore implements PaletteStore {
    FakePaletteStore({
      this.stored,
      this.failRead = false,
      this.failWrite = false,
      this.pendingRead,
    });

    String? stored;
    bool failRead;
    bool failWrite;
    Completer<String?>? pendingRead;
    int reads = 0;
    final List<String> writes = [];

    @override
    Future<String?> read() async {
      reads++;
      if (pendingRead case final pending?) return pending.future;
      if (failRead) throw StateError('read failed (fake)');
      return stored;
    }

    @override
    Future<void> write(String id) async {
      if (failWrite) throw StateError('write failed (fake)');
      writes.add(id);
      stored = id;
    }
  }
  ```

- [ ] **Step 4: See them pass,** then run the full gates. The expected count is about 667 (an estimate); record the real one.
- [ ] **Step 5: Mutations** (temporary; restore each):
  - **M3:** remove `.timeout(timeout)`. The never-completes test must fail.
  - **M3b:** make `_prefs` a plain `final`. The real-store test must fail.
- [ ] **Step 6: Log and commit:** `feat(appearance): remember the palette on the device (shared_preferences)`.

### Task 3: One selected palette drives the app theme

**Files:**
- Modify: `lib/features/appearance/appearance_providers.dart`, `lib/app/app.dart`, `lib/main.dart`,
  `integration_test/fakes/test_app.dart`
- Create: `test/features/appearance/palette_controller_test.dart`, `test/app/palette_app_test.dart`

**Interfaces:** produces `initialPaletteProvider`, `paletteStoreProvider`, `paletteProvider` and
`PaletteController.select(AppPalette)`. `buildTestApp` gains `PaletteStore? paletteStore` (default
`FakePaletteStore()`) and `AppPalette palette` (default `AppPalette.teal`).

- [ ] **Step 1: Write the failing tests.** `test/features/appearance/palette_controller_test.dart`:

  ```dart
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sg_smart_commute/features/appearance/appearance_providers.dart';
  import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';

  import '../../../integration_test/fakes/fake_palette_store.dart';

  void main() {
    ProviderContainer container(FakePaletteStore store, [AppPalette? start]) {
      final c = ProviderContainer(
        overrides: [
          paletteStoreProvider.overrideWithValue(store),
          if (start != null) initialPaletteProvider.overrideWithValue(start),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('starts from the initial palette, teal by default', () {
      expect(container(FakePaletteStore()).read(paletteProvider), AppPalette.teal);
      expect(
        container(FakePaletteStore(), AppPalette.rose).read(paletteProvider),
        AppPalette.rose,
      );
    });

    test('select applies at once, then stores the id', () async {
      final store = FakePaletteStore();
      final c = container(store);
      final pending = c.read(paletteProvider.notifier).select(AppPalette.blue);
      expect(c.read(paletteProvider), AppPalette.blue, reason: 'before the write');
      await pending;
      expect(store.writes, ['blue']);
    });

    test('a failed write keeps the selection, throws nothing, stores nothing', () async {
      final store = FakePaletteStore(failWrite: true);
      final c = container(store);
      await c.read(paletteProvider.notifier).select(AppPalette.orange);
      expect(c.read(paletteProvider), AppPalette.orange);
      expect(store.stored, isNull);
      expect(store.writes, isEmpty);
    });
  }
  ```

  `test/app/palette_app_test.dart`:

  ```dart
  import 'dart:async';

  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sg_smart_commute/app/home_screen.dart';
  import 'package:sg_smart_commute/core/location/location_service.dart';
  import 'package:sg_smart_commute/features/appearance/appearance_providers.dart';
  import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
  import 'package:sg_smart_commute/features/appearance/presentation/palette_theme.dart';

  import '../../integration_test/fakes/fake_environment_repository.dart';
  import '../../integration_test/fakes/fake_location_service.dart';
  import '../../integration_test/fakes/fake_palette_store.dart';
  import '../../integration_test/fakes/test_app.dart';

  Widget app(FakePaletteStore store, AppPalette palette) => buildTestApp(
    location: FakeLocationService(access: LocationAccess.denied),
    environment: FakeEnvironmentRepository(),
    paletteStore: store,
    palette: palette,
  );

  ColorScheme scheme(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(HomeScreen))).colorScheme;

  Color primaryOf(AppPalette p) => paletteTheme(p, Brightness.light).colorScheme.primary;

  Future<void> select(WidgetTester tester, AppPalette p) async {
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    await c.read(paletteProvider.notifier).select(p);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // theme cross-fade
  }

  /// The primary colour on each of 16 frames of 16 ms after choosing [p].
  Future<List<Color>> framesAfterChoosing(WidgetTester tester, AppPalette p) async {
    final c = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    await c.read(paletteProvider.notifier).select(p);
    final seen = <Color>[];
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      seen.add(scheme(tester).primary);
    }
    return seen;
  }

  void setBrightness(WidgetTester tester, Brightness b) {
    tester.platformDispatcher.platformBrightnessTestValue = b;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  void main() {
    for (final p in AppPalette.values) {
      for (final b in Brightness.values) {
        testWidgets('stored ${p.id}: the app starts in ${p.label}, ${b.name}', (
          tester,
        ) async {
          setBrightness(tester, b);
          final store = FakePaletteStore(stored: p.id);
          await tester.pumpWidget(app(store, await loadInitialPalette(store)));
          await tester.pump();
          expect(scheme(tester), paletteTheme(p, b).colorScheme);
        });
      }
    }

    testWidgets('nothing stored, or a failing read: teal, and the app starts', (
      tester,
    ) async {
      for (final store in [FakePaletteStore(), FakePaletteStore(failRead: true)]) {
        await tester.pumpWidget(app(store, await loadInitialPalette(store)));
        await tester.pump();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(scheme(tester).primary, primaryOf(AppPalette.teal));
        await tester.pumpWidget(const SizedBox());
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('each palette can be chosen and recolours the app', (tester) async {
      await tester.pumpWidget(app(FakePaletteStore(), AppPalette.teal));
      await tester.pump();
      for (final p in AppPalette.values.reversed) {
        await select(tester, p);
        expect(scheme(tester), paletteTheme(p, Brightness.light).colorScheme, reason: p.id);
      }
    });

    testWidgets('the system switching to dark keeps the chosen palette', (
      tester,
    ) async {
      setBrightness(tester, Brightness.light);
      await tester.pumpWidget(app(FakePaletteStore(), AppPalette.teal));
      await tester.pump();
      await select(tester, AppPalette.purple);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(scheme(tester), paletteTheme(AppPalette.purple, Brightness.dark).colorScheme);
    });

    testWidgets('a restart restores the chosen palette', (tester) async {
      final store = FakePaletteStore();
      await tester.pumpWidget(app(store, await loadInitialPalette(store)));
      await tester.pump();
      await select(tester, AppPalette.rose);
      expect(store.stored, 'rose');

      await tester.pumpWidget(const SizedBox()); // the old ProviderScope is gone
      await tester.pumpWidget(app(store, await loadInitialPalette(store)));
      await tester.pump();
      expect(scheme(tester).primary, primaryOf(AppPalette.rose));
    });

    testWidgets('a failed write keeps the palette and the app usable', (tester) async {
      await tester.pumpWidget(app(FakePaletteStore(failWrite: true), AppPalette.teal));
      await tester.pump();
      await select(tester, AppPalette.rose);
      expect(scheme(tester).primary, primaryOf(AppPalette.rose));
      await tester.enterText(find.byKey(const Key('destination-field')), 'Vivo');
      await tester.pump();
      expect(find.text('Vivo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('after a failed write, a restart shows what storage really '
        'holds', (tester) async {
      final store = FakePaletteStore(stored: 'blue', failWrite: true);
      await tester.pumpWidget(app(store, await loadInitialPalette(store)));
      await tester.pump();
      expect(scheme(tester).primary, primaryOf(AppPalette.blue));
      await select(tester, AppPalette.orange);
      expect(scheme(tester).primary, primaryOf(AppPalette.orange), reason: 'kept in memory');
      expect(store.stored, 'blue', reason: 'nothing pretends it was saved');

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(app(store, await loadInitialPalette(store)));
      await tester.pump();
      expect(scheme(tester).primary, primaryOf(AppPalette.blue));
    });

    testWidgets('a read that completes after startup never recolours the '
        'running app', (tester) async {
      final lateRead = Completer<String?>();
      final store = FakePaletteStore(pendingRead: lateRead);
      // Startup timed out (Task 2's fakeAsync test): the app runs in teal.
      await tester.pumpWidget(app(store, AppPalette.teal));
      await tester.pump();
      lateRead.complete('purple');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(scheme(tester).primary, primaryOf(AppPalette.teal));
      expect(store.reads, 0, reason: 'only startup reads the store');
    });

    testWidgets('normal motion: the palette change cross-fades (Material '
        'default)', (tester) async {
      await tester.pumpWidget(app(FakePaletteStore(), AppPalette.teal));
      await tester.pump();
      final seen = await framesAfterChoosing(tester, AppPalette.rose);
      final between = seen.where(
        (c) => c != primaryOf(AppPalette.rose) && c != primaryOf(AppPalette.teal),
      );
      expect(between, isNotEmpty);
      expect(seen.last, primaryOf(AppPalette.rose));
    });

    testWidgets('reduce motion: the palette change has no in-between colours', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(app(FakePaletteStore(), AppPalette.teal));
      await tester.pump();
      final seen = await framesAfterChoosing(tester, AppPalette.rose);
      expect(
        seen.where((c) => c != primaryOf(AppPalette.rose) && c != primaryOf(AppPalette.teal)),
        isEmpty,
      );
      expect(seen.skip(1), everyElement(primaryOf(AppPalette.rose)));
    });
  }
  ```

- [ ] **Step 2: See them fail** (compile errors: the providers and the new `buildTestApp` parameters don't exist yet).
- [ ] **Step 3: Implement.**

  Append to `appearance_providers.dart`, adding `import 'package:flutter_riverpod/flutter_riverpod.dart';` and
  `import 'data/shared_preferences_palette_store.dart';`:

  ```dart
  /// The palette read before the first frame; main() overrides it (E1).
  final initialPaletteProvider = Provider<AppPalette>(
    (ref) => AppPalette.fallback,
  );

  /// Where the choice is remembered. Tests use a fake (buildTestApp).
  final paletteStoreProvider = Provider<PaletteStore>(
    (ref) => SharedPreferencesPaletteStore(),
  );

  /// The one source of truth for the selected palette. Brightness stays the
  /// system's; this only picks the colours.
  final paletteProvider = NotifierProvider<PaletteController, AppPalette>(
    PaletteController.new,
  );

  class PaletteController extends Notifier<AppPalette> {
    @override
    AppPalette build() => ref.watch(initialPaletteProvider);

    /// Applies [palette] at once, then stores it. If the write fails the
    /// palette stays for this session; it is only not remembered (silent:
    /// a storage problem never interrupts the journey).
    Future<void> select(AppPalette palette) async {
      state = palette;
      try {
        await ref.read(paletteStoreProvider).write(palette.id);
      } catch (e) {
        debugPrint('Colour palette not saved: $e');
      }
    }
  }
  ```

  In `lib/app/app.dart`:
  - `SmartCommuteApp` becomes a `ConsumerWidget`; import `flutter_riverpod` and the appearance providers;
  - `build(BuildContext context, WidgetRef ref)` reads `final palette = ref.watch(paletteProvider);` and passes
    `theme: paletteTheme(palette, Brightness.light)` and `darkTheme: paletteTheme(palette, Brightness.dark)`;
  - keep `themeMode: ThemeMode.system`;
  - add the comment "The palette is the user's; the brightness stays the system's."

  `lib/main.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  import 'app/app.dart';
  import 'features/appearance/appearance_providers.dart';
  import 'features/appearance/data/shared_preferences_palette_store.dart';

  export 'app/app.dart' show SmartCommuteApp, noAutomaticRetry;

  Future<void> main() async {
    // The stored palette is read before the first frame, so a chosen palette
    // never shows the default first (E1). The read is bounded and never
    // throws: on any problem the app starts in the default palette.
    WidgetsFlutterBinding.ensureInitialized();
    final palette = await loadInitialPalette(SharedPreferencesPaletteStore());
    runApp(
      ProviderScope(
        retry: noAutomaticRetry,
        overrides: [initialPaletteProvider.overrideWithValue(palette)],
        child: const SmartCommuteApp(),
      ),
    );
  }
  ```

  In `integration_test/fakes/test_app.dart`:
  - import the providers, `AppPalette`, `PaletteStore` and `fake_palette_store.dart`;
  - add the parameters `PaletteStore? paletteStore,` and `AppPalette palette = AppPalette.teal,`;
  - add the overrides `paletteStoreProvider.overrideWithValue(paletteStore ?? FakePaletteStore()),` and
    `initialPaletteProvider.overrideWithValue(palette),`;
  - extend the doc comment: "…and the palette store is a fake: no test touches device or browser storage."

- [ ] **Step 4: See them pass,** then run the full gates. The expected count is about 689 (an estimate); record the real one.
- [ ] **Step 5: Mutations** (temporary; restore each):
  - **M1:** move `state = palette;` after the awaited write, inside the `try`. The failed-write tests must fail.
  - **M4:** make `paletteTheme` ignore the palette (always the teal seed). The per-palette tests must fail.
  - **M5:** set `themeMode: ThemeMode.light`. The dark tests must fail.
  - **M11:** pass `themeAnimationStyle: AnimationStyle.noAnimation` to `MaterialApp`. The normal-motion test must fail.
    This proves the test pins the default cross-fade.
- [ ] **Step 6: Log and commit:** `feat(appearance): one selected palette drives the app theme`.

### Task 4: The colour theme menu in the app bar

**Files:**
- Create: `lib/features/appearance/presentation/palette_menu_button.dart`,
  `test/features/appearance/palette_menu_button_test.dart`
- Modify: `lib/app/home_screen.dart`

**Interfaces:** consumes `paletteProvider`, `PaletteController.select` and `paletteTheme`. Produces `PaletteMenuButton`
(keys `palette-button`, `palette-option-<id>`), `PaletteMenuButton.tooltipFor` and `PaletteSwatch`.

- [ ] **Step 1: Write the failing tests.** `test/features/appearance/palette_menu_button_test.dart`:

  ```dart
  import 'package:flutter/foundation.dart';
  import 'package:flutter/material.dart';
  import 'package:flutter/services.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sg_smart_commute/app/home_screen.dart';
  import 'package:sg_smart_commute/core/location/location_service.dart';
  import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
  import 'package:sg_smart_commute/features/appearance/presentation/palette_menu_button.dart';
  import 'package:sg_smart_commute/features/appearance/presentation/palette_theme.dart';

  import '../../../integration_test/fakes/fake_environment_repository.dart';
  import '../../../integration_test/fakes/fake_location_service.dart';
  import '../../../integration_test/fakes/fake_palette_store.dart';
  import '../../../integration_test/fakes/test_app.dart';

  const button = Key('palette-button');

  /// RadioMenuButton passes its key on to its MenuItemButton: two matches.
  Finder option(AppPalette p) => find.byKey(Key('palette-option-${p.id}')).first;

  bool menuOpen() => find.byKey(const Key('palette-option-teal')).evaluate().isNotEmpty;

  Widget app(FakePaletteStore store) => buildTestApp(
    location: FakeLocationService(access: LocationAccess.denied),
    environment: FakeEnvironmentRepository(),
    paletteStore: store,
  );

  ColorScheme scheme(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(HomeScreen))).colorScheme;

  /// The palette option that has keyboard focus, 'button', or 'other'.
  String focused() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return 'none';
    String? found;
    void check(Element e) {
      if (e.widget.key == button) found ??= 'button';
      final w = e.widget;
      if (w is RadioMenuButton<AppPalette>) found ??= 'option:${w.value.id}';
    }

    check(context as Element);
    context.visitAncestorElements((e) {
      check(e);
      return found == null;
    });
    return found ?? 'other';
  }

  Future<void> pumpTall(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.pump();
  }

  /// Choosing applies after the frame that closes the menu, then cross-fades.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  void main() {
    for (final b in Brightness.values) {
      testWidgets('${b.name}: five named options, each with its own swatch', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = b;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await pumpTall(tester, app(FakePaletteStore()));
        await tester.tap(find.byKey(button));
        await tester.pump();
        for (final p in AppPalette.values) {
          expect(find.descendant(of: option(p), matching: find.text(p.label)), findsOneWidget);
          final swatch = tester.widget<PaletteSwatch>(
            find.descendant(of: option(p), matching: find.byType(PaletteSwatch)),
          );
          expect(swatch.color, paletteTheme(p, b).colorScheme.primary, reason: p.id);
        }
      });
    }

    testWidgets('semantics: a named button with its open state; radio options', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpTall(tester, app(FakePaletteStore()));
      expect(
        tester.getSemantics(find.byKey(button)),
        isSemantics(
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          tooltip: 'Colour theme: Teal',
          hasExpandedState: true,
          isExpanded: false,
        ),
      );
      await tester.tap(find.byKey(button));
      await tester.pump();
      expect(
        tester.getSemantics(find.byKey(button)),
        isSemantics(hasExpandedState: true, isExpanded: true),
      );
      for (final p in AppPalette.values) {
        expect(
          tester.getSemantics(option(p)),
          matchesSemantics(
            label: p.label,
            hasCheckedState: true,
            isChecked: p == AppPalette.teal,
            isInMutuallyExclusiveGroup: true,
            hasEnabledState: true,
            isEnabled: true,
            isFocusable: true,
            hasTapAction: true,
            hasFocusAction: true,
          ),
          reason: p.id,
        );
      }
      semantics.dispose();
    });

    testWidgets('choosing applies at once, stores the id, closes the menu and '
        'renames the button', (tester) async {
      final store = FakePaletteStore();
      await pumpTall(tester, app(store));
      await tester.tap(find.byKey(button));
      await tester.pump();
      await tester.tap(option(AppPalette.rose));
      await settle(tester);
      expect(scheme(tester), paletteTheme(AppPalette.rose, Brightness.light).colorScheme);
      expect(store.writes, ['rose']);
      expect(menuOpen(), isFalse);
      expect(
        tester.widget<IconButton>(find.byKey(button)).tooltip,
        PaletteMenuButton.tooltipFor(AppPalette.rose),
      );
      // The newly selected option now carries the checked state.
      await tester.tap(find.byKey(button));
      await tester.pump();
      final semantics = tester.ensureSemantics();
      expect(tester.getSemantics(option(AppPalette.rose)), isSemantics(isChecked: true));
      expect(tester.getSemantics(option(AppPalette.teal)), isSemantics(isChecked: false));
      semantics.dispose();
    });

    testWidgets('keyboard: Tab, Enter, arrows, Enter; Space then Escape', (
      tester,
    ) async {
      final store = FakePaletteStore();
      await pumpTall(tester, app(store));
      Future<void> key(LogicalKeyboardKey k) async {
        await tester.sendKeyEvent(k);
        await tester.pump();
      }

      await key(LogicalKeyboardKey.tab);
      expect(focused(), 'button', reason: 'the first Tab stop');
      await key(LogicalKeyboardKey.enter);
      expect(menuOpen(), isTrue);
      await key(LogicalKeyboardKey.arrowDown);
      expect(focused(), 'option:teal');
      await key(LogicalKeyboardKey.arrowDown);
      expect(focused(), 'option:blue');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(scheme(tester), paletteTheme(AppPalette.blue, Brightness.light).colorScheme);
      expect(menuOpen(), isFalse);
      expect(focused(), 'button', reason: 'focus returns to the button');

      await key(LogicalKeyboardKey.space);
      expect(menuOpen(), isTrue);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 300));
      expect(menuOpen(), isFalse);
      expect(store.writes, ['blue'], reason: 'Escape changes nothing');
      expect(focused(), 'button');
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({TargetPlatform.android, TargetPlatform.windows}));

    testWidgets('360 × 780 dp at 2× text: app bar and open menu fit', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(app(FakePaletteStore()));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final screen = Offset.zero & const Size(360, 780);
      bool onScreen(Rect r) => screen.contains(r.topLeft) && screen.contains(r.bottomRight - const Offset(1, 1));
      final b = tester.getRect(find.byKey(button));
      expect(onScreen(b), isTrue);
      expect(b.width, greaterThanOrEqualTo(48));
      expect(tester.getRect(find.text('Singapore Smart Commute')).right, lessThanOrEqualTo(b.left));

      await tester.tap(find.byKey(button));
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final p in AppPalette.values) {
        expect(onScreen(tester.getRect(option(p))), isTrue, reason: p.id);
      }
    });
  }
  ```

  The `foundation.dart` import is for `TargetPlatform`. If `flutter analyze` reports it as unnecessary, because
  `material.dart` already exports it, drop it.

- [ ] **Step 2: See them fail** (compile error: `palette_menu_button.dart` doesn't exist).
- [ ] **Step 3: Implement.** `lib/features/appearance/presentation/palette_menu_button.dart`:

  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  import '../appearance_providers.dart';
  import '../domain/app_palette.dart';
  import 'palette_theme.dart';

  /// The app-bar control for the colour palette (E1): a menu of the curated
  /// palettes, each named, with a radio mark and a swatch of its primary
  /// colour in the current brightness. Choosing one applies it at once. It
  /// holds no palette state of its own: it reads and sets paletteProvider.
  class PaletteMenuButton extends ConsumerWidget {
    const PaletteMenuButton({super.key});

    static String tooltipFor(AppPalette palette) => 'Colour theme: ${palette.label}';

    @override
    Widget build(BuildContext context, WidgetRef ref) {
      final current = ref.watch(paletteProvider);
      final brightness = Theme.of(context).brightness;
      return MenuAnchor(
        menuChildren: [
          for (final p in AppPalette.values)
            RadioMenuButton<AppPalette>(
              key: Key('palette-option-${p.id}'),
              value: p,
              groupValue: current,
              onChanged: (p) {
                if (p != null) ref.read(paletteProvider.notifier).select(p);
              },
              trailingIcon: PaletteSwatch(paletteTheme(p, brightness).colorScheme.primary),
              child: Text(p.label),
            ),
        ],
        builder: (context, controller, _) => IconButton(
          key: const Key('palette-button'),
          tooltip: tooltipFor(current),
          icon: const Icon(Icons.palette_outlined),
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
        ),
      );
    }
  }

  /// A round preview of a palette's primary colour. Decorative: each option
  /// is named, so colour is never the only cue.
  class PaletteSwatch extends StatelessWidget {
    const PaletteSwatch(this.color, {super.key});

    final Color color;

    @override
    Widget build(BuildContext context) => SizedBox.square(
      dimension: 18,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
        ),
      ),
    );
  }
  ```

  In `lib/app/home_screen.dart`, import `../features/appearance/presentation/palette_menu_button.dart` and change the
  app bar to `appBar: AppBar(title: const AppTitle(), actions: const [PaletteMenuButton()]),`.

  This is plain Material: no custom focus or semantics code, no `FocusNode`, no `Shortcuts`, no traversal policy.

- [ ] **Step 3b: Add semantics only where the tests show a need.** Run
  `timeout 590 flutter test test/features/appearance/palette_menu_button_test.dart` against the plain implementation and
  record the result.
  - **Expected** (from the prototype): everything passes except the two open/closed assertions
    (`hasExpandedState`/`isExpanded` on `palette-button`). If and only if those are the failures, wrap the builder's
    button, and add nothing else:

    ```dart
        // One node: the button, its name (tooltip) and whether the menu is
        // open (aria-expanded on Web). Added because the open/closed test
        // failed with plain Material.
        builder: (context, controller, _) => MergeSemantics(
          child: Semantics(
            expanded: controller.isOpen,
            child: IconButton(
              key: const Key('palette-button'),
              tooltip: tooltipFor(current),
              icon: const Icon(Icons.palette_outlined),
              onPressed: () => controller.isOpen ? controller.close() : controller.open(),
            ),
          ),
        ),
    ```

    Rerun the file. `tester.getSemantics` walks up through merged nodes, so the flags should land on the button's node.
  - If plain Material already passes the open/closed assertions, add no wrapper and skip M12.
  - **Stop and report, and don't add other machinery,** if any of these happens:
    - any other assertion fails with plain Material: keyboard, focus return, radio semantics, the button name, the
      layout;
    - the wrapper doesn't make the open/closed assertions pass;
    - the `MenuAnchor` builder doesn't rebuild on open and close;
    - **D7:** the selected state isn't conveyed (the checked option or the renamed button). Don't add a live-region
      announcement.
  - Record in the run log which case applied.
- [ ] **Step 4: See them pass,** then run the full gates. They include `test/app/accessibility_test.dart` and the P2-M3
  and P2-M4 groups. The expected count is about 696 (an estimate); record the real one.
- [ ] **Step 5: Mutations** (temporary; restore each):
  - **M8:** use `MenuItemButton` instead of `RadioMenuButton`. The radio semantics test must fail.
  - **M9:** give the swatch a fixed `paletteTheme(AppPalette.teal, …)` colour. The swatch test must fail.
  - **M12** (only if Step 3b added the wrapper): drop the `Semantics(expanded:)` wrapper. The expanded-state
    assertion must fail.
- [ ] **Step 6: Log and commit:** `feat(appearance): colour theme menu in the app bar`.

### Task 5: The map-state contract (a palette change only recolours)

**Files:** create `test/features/appearance/palette_change_invariants_test.dart`. No production change is expected; if
a test fails, stop and report (§10).

- [ ] **Step 1: Write the tests.** They're adapted from the prototype's `palette_map_test.dart`, which passed.

  ```dart
  // E1 map-state contract: a palette change only recolours. No re-plan,
  // refetch, reselection, refit, route-geometry load or tile request; only
  // the system brightness switches OneMap Default/Night.
  import 'package:flutter/material.dart';
  import 'package:flutter_map/flutter_map.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:sg_smart_commute/app/home_screen.dart';
  import 'package:sg_smart_commute/core/config/app_config.dart';
  import 'package:sg_smart_commute/core/geo/geo.dart';
  import 'package:sg_smart_commute/core/location/location_service.dart';
  import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
  import 'package:sg_smart_commute/features/appearance/presentation/palette_theme.dart';
  import 'package:sg_smart_commute/features/journey/journey_providers.dart';
  import 'package:sg_smart_commute/features/map/presentation/journey_map.dart';

  import '../../../integration_test/fakes/fake_bus_arrival_repository.dart';
  import '../../../integration_test/fakes/fake_bus_network.dart';
  import '../../../integration_test/fakes/fake_environment_repository.dart';
  import '../../../integration_test/fakes/fake_location_service.dart';
  import '../../../integration_test/fakes/fake_map.dart';
  import '../../../integration_test/fakes/fake_palette_store.dart';
  import '../../../integration_test/fakes/fake_place_search_repository.dart';
  import '../../../integration_test/fakes/fake_route_geometry.dart';
  import '../../../integration_test/fakes/test_app.dart';

  const bishan = LatLng(1.3508, 103.8485);

  void main() {
    late FakeBusNetworkRepository bus;
    late FakeBusArrivalRepository arrivals;
    late FakeRouteGeometryRepository geometry;
    late FakeTileProvider tiles;

    setUp(() {
      bus = FakeBusNetworkRepository();
      arrivals = FakeBusArrivalRepository();
      geometry = FakeRouteGeometryRepository();
      tiles = FakeTileProvider();
    });

    Future<void> tapVisible(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await tester.pump();
      await tester.pump();
    }

    /// Bishan by GPS → VivoCity, the F10 alternative selected.
    Future<void> journey(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        buildTestApp(
          location: FakeLocationService(access: LocationAccess.granted, position: bishan),
          environment: FakeEnvironmentRepository(),
          places: FakePlaceSearchRepository(),
          busNetwork: bus,
          busArrivals: arrivals,
          routeGeometry: geometry,
          mapTiles: () => tiles,
          paletteStore: FakePaletteStore(),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byKey(const Key('destination-field')), 'VivoCity');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.tap(find.text('VIVOCITY'));
      await tester.pump();
      await tester.pump();
      await tapVisible(tester, find.byKey(const Key('select-option-F10')));
    }

    /// Chooses [p] in the app-bar menu and steps through the cross-fade.
    Future<void> choose(
      WidgetTester tester,
      AppPalette p, {
      void Function(int frame)? eachFrame,
    }) async {
      await tester.tap(find.byKey(const Key('palette-button')));
      await tester.pump();
      await tester.tap(find.byKey(Key('palette-option-${p.id}')).first);
      await tester.pump();
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 20)); // the 200 ms cross-fade
        expect(tester.takeException(), isNull, reason: 'frame $i');
        eachFrame?.call(i);
      }
    }

    Object? plan(WidgetTester tester) => ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    ).read(journeyPlanProvider).value;

    ({int bus, int arrivals, int geometry}) loads() =>
        (bus: bus.loads, arrivals: arrivals.totalCalls, geometry: geometry.loads);

    MapCamera camera(WidgetTester tester) => MapCamera.of(tester.element(find.byType(MarkerLayer)));
    String template(WidgetTester tester) =>
        tester.widget<TileLayer>(find.byType(TileLayer)).urlTemplate!;
    Color rideColour(WidgetTester tester) => tester
        .widget<PolylineLayer>(find.byKey(const Key('map-ride-line')))
        .polylines
        .single
        .color;

    testWidgets('map closed: no tile or route-geometry request, no re-plan, no '
        'refetch, the selection kept', (tester) async {
      await journey(tester);
      final before = (plan: plan(tester), loads: loads());
      expect(before.plan, isNotNull);
      await choose(tester, AppPalette.rose);
      expect(identical(plan(tester), before.plan), isTrue, reason: '0 new plans');
      expect(loads(), before.loads);
      expect(geometry.loads, 0);
      expect(tiles.requested, isEmpty);
      expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
    });

    testWidgets('map open and panned: Teal → Rose in light keeps Default, the '
        'map, camera, tiles, plan, loads and selection; dark switches to Night '
        'only by brightness', (tester) async {
      await journey(tester);
      await tapVisible(tester, find.byKey(const Key('show-map')));
      final fitted = camera(tester).center;
      await tester.timedDrag(find.byType(FlutterMap), const Offset(-80, 0), const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 1));
      expect(camera(tester).center, isNot(fitted), reason: 'the pan moved the camera');

      final map = tester.state(find.byType(FlutterMap));
      final journeyMap = tester.state(find.byType(JourneyMap));
      final center = camera(tester).center;
      final zoom = camera(tester).zoom;
      var requested = tiles.requested.length;
      final before = (plan: plan(tester), loads: loads());
      expect(template(tester), BasemapEndpoints.defaultTiles);

      await choose(
        tester,
        AppPalette.rose,
        eachFrame: (_) => expect(template(tester), BasemapEndpoints.defaultTiles),
      );
      expect(identical(map, tester.state(find.byType(FlutterMap))), isTrue);
      expect(identical(journeyMap, tester.state(find.byType(JourneyMap))), isTrue);
      expect(camera(tester).center, center, reason: '0 refits: the pan is kept');
      expect(camera(tester).zoom, zoom);
      expect(tiles.requested.length, requested, reason: '0 new tile requests');
      expect(tiles.disposed, isFalse);
      expect(identical(plan(tester), before.plan), isTrue, reason: '0 new plans');
      expect(loads(), before.loads, reason: '0 refetches, 0 extra routes.min.json loads');
      expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
      expect(find.byKey(const Key('map-card')), findsOneWidget);
      expect(rideColour(tester), paletteTheme(AppPalette.rose, Brightness.light).colorScheme.primary);

      // Brightness, not the palette, switches the basemap.
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(template(tester), BasemapEndpoints.nightTiles);
      expect(identical(map, tester.state(find.byType(FlutterMap))), isTrue);
      expect(camera(tester).center, center);
      expect(loads(), before.loads);

      // A palette change in dark keeps Night and requests nothing new.
      requested = tiles.requested.length;
      await choose(
        tester,
        AppPalette.orange,
        eachFrame: (_) => expect(template(tester), BasemapEndpoints.nightTiles),
      );
      expect(tiles.requested.length, requested);
      expect(camera(tester).center, center);
      expect(identical(plan(tester), before.plan), isTrue);
      expect(loads(), before.loads);
      expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
      expect(rideColour(tester), paletteTheme(AppPalette.orange, Brightness.dark).colorScheme.primary);
      expect(tester.takeException(), isNull);
    });
  }
  ```

- [ ] **Step 2: Run them:** `timeout 590 flutter test test/features/appearance/palette_change_invariants_test.dart`.
  Expect PASS; if anything fails, stop and report.
- [ ] **Step 3: Mutations, which must FAIL** (temporary; restore each; `git diff --quiet -- lib` afterwards):
  - **M6:** give `FlutterMap` `key: ValueKey(theme.colorScheme.primary)` in `journey_map.dart`. The State, camera and
    tile assertions must fail.
  - **M7:** set `home: HomeScreen(key: ValueKey(palette))` in `app.dart`. The State and plan identity must fail.
  - **M10:** make `TileLayer.urlTemplate` use `nightTiles` whenever the scheme's primary isn't Teal's. The Default
    template assertion must fail.
- [ ] **Step 4: Log and commit:** `test(appearance): a palette change only recolours the journey and the open map`.
  The expected count is about 698 (an estimate); record the real one.

### Task 6: Documentation (§17)

- [ ] Make the edits listed in §17.
- [ ] Run `dart format --set-exit-if-changed .` and `flutter analyze`, and check that the links resolve.
- [ ] Commit: `docs: E1 colour themes`.

### Task 7: Full verification

- [ ] **Scope checks:**

  ```bash
  git diff --name-only origin/main...HEAD -- web/ lib/features/journey lib/features/map lib/features/bus_arrival \
    lib/features/environment lib/features/places lib/features/origin lib/features/destination lib/core/http lib/core/location
  # Expected: nothing.
  git diff origin/main...HEAD -- pubspec.yaml
  # Expected: only `shared_preferences: 2.5.5`.
  git grep -n -i "indigo" -- lib test integration_test
  # Expected: only the "never shipped" fromId check and the guard's not-in-the-enum check.
  git grep -n -E "Colors\." -- lib
  # Expected: nothing.
  ```

- [ ] **Gates** (foreground):
  - `dart format`;
  - `flutter analyze`;
  - `timeout 590 flutter test`, with about 698 expected (an estimate; record the real count);
  - `flutter build web --release`;
  - `flutter build apk --debug`;
  - `flutter build apk --release`. Record its size and SHA-256, and the size change against 53,909,630 B. Note that
    the first build after adding `shared_preferences` downloads its Android libraries.
- [ ] **Android integration** (3 files, 5 tests). Check the host memory (about 3 GB or more free) and a healthy
  emulator first. Use one emulator and never `emulator-5554`. If a file fails, rerun it once; ask before any reboot.
- [ ] **Web integration**, one file per run with the matching chromedriver. Expect 3/3, 0 CSP violations and 0 SEVERE.
- [ ] Log everything, then commit: `docs(testing): E1 gates`.

### Task 8: Live checks (§16)

- [ ] Run the checks in §16, including the **Web keyboard verification** (D3).
- [ ] Log what you see, and record every Not run with its reason. Add an open-items entry, "E1 colour themes (date)".
- [ ] Commit: `docs(testing): E1 live checks`.
- [ ] If Web keyboard or semantics behaviour differs from Task 4's widget-test results, or anything breaks the map-state
  contract, **stop and report**.

### Task 9: Final review and PR

- [ ] Run a fresh whole-branch review on the most capable model against this plan, §20, the Global Constraints and the
  Review Focus.
- [ ] Fix Critical and Important findings test-first, then re-run the affected gates.
- [ ] Freeze the head.
- [ ] Push `feat/e1-colour-themes` and open a PR to `main`. **Don't merge it.**

## 15. Mutation and regression checks

| Id | Mutation (temporary) | Must fail | Task |
|---|---|---|---|
| G0 | `Colors.teal` back as app.dart's seed | The guard on the real `lib/` | 1 |
| G1–G4 | A fixed colour off a seed line; `Colors.teal` in `app.dart`; a seed line not in the enum (`indigo`); a stray `Color(` | The guard's self-checks | 1 |
| M3 | `loadInitialPalette` without `.timeout` | The never-completes test | 2 |
| M3b | An eager `SharedPreferencesAsync()` | The real-store test | 2 |
| M1 | `state =` only after a successful write | The failed-write tests | 3 |
| M4 | `paletteTheme` ignores the palette | The per-palette tests | 3 |
| M5 | `ThemeMode.light` | The dark tests | 3 |
| M11 | `themeAnimationStyle: AnimationStyle.noAnimation` | The normal-motion cross-fade test | 3 |
| M8 | `MenuItemButton` instead of `RadioMenuButton` | The radio semantics | 4 |
| M9 | A fixed swatch colour | The swatch test | 4 |
| M12 | No `Semantics(expanded:)` (only if Step 3b added it) | The expanded-state assertion | 4 |
| M6 | `FlutterMap` keyed by `primary` | The map State, camera and tiles | 5 |
| M7 | `HomeScreen` keyed by the palette | The State and plan identity | 5 |
| M10 | The tile template depends on the palette | The Default/Night assertions | 5 |

After each mutation, restore with `git checkout -- <file>`; then `git diff --quiet -- lib` must succeed. The existing
suites stay green throughout:
- the 645 baseline tests;
- the P2-M3 selection group and the P2-M4 reduced-motion group;
- `motion_test` and `home_screen_test` (real-duration motion and the D3 diagnostic);
- `accessibility_test`;
- the CSP test.

## 16. Android and Web live checks (Task 8)

**Web** (the release build served on 127.0.0.1; headless Chrome through chromedriver and CDP; GPS at Bishan; live
providers):

1. **All five palettes** (Teal, Blue, Rose, Purple, Orange), in light and in dark (`Emulation.setEmulatedMedia`). Take a
   phone-width screenshot of each and check it's recoloured, nothing is clipped and the menu is readable.
2. **Persistence:** choose Rose, then reload. With a CDP screencast running from before the reload, check that the
   first rendered frame after the Flutter loader is already Rose, with no Teal frame. Check that `localStorage` holds
   the id.
3. **Open map:** with the map open and panned and an alternative selected, change the palette.
   - Before/after screenshots of the map region show the same view, only recoloured.
   - "Bus N selected" stays.
   - Resource timing shows **0** new requests across the change (tiles, `routes.min.json`, ArriveLah, NEA, OneMap
     search).
   - The basemap stays Default in light. Emulating dark switches it to Night, and a palette change in dark keeps Night.
4. **Keyboard, verified in the real browser (D3):**
   - Tab reaches the palette button.
   - Enter opens; so does Space.
   - Arrow Down and Up move through the options.
   - Enter selects and the theme changes.
   - Escape closes with no change.
   - Focus returns to the button after closing, and the focus ring is visible.
   - Read `flt-semantics` for the radio/checked role, `aria-checked`, the button's `aria-expanded` and its accessible
     name ("Colour theme: Rose").
   - Record exactly what happens. If anything differs from Task 4's widget tests, **stop and report**.
5. **360 px at 2× text** (`default_font_size` 32), light and dark: no overflow, and the open menu is on screen.
6. **Logs and hosts:** 0 CSP violations, 0 SEVERE, only the existing CSP hosts.

**Android** (the release APK on a healthy emulator; host memory checked first; never `emulator-5554`):

1. Read the baseline settings first; at the end, restore them and diff against the baseline.
2. Each of the five palettes in light and dark (`cmd uimode night`).
3. Choose Rose, `am force-stop`, then relaunch: still Rose. Clear the app's data: Teal again.
4. `font_scale` 2.0 and about 360 dp (`wm density`): the app bar and the menu fit.
5. Open the map, pan it, select an alternative, then change the palette: the same view, only recoloured; the selection
   kept; no Flutter error in logcat.
6. **Startup flash by eye:** Not run if no frame decoder is installed (none is installed, and ffmpeg won't be). The Web
   screencast check stands in for it.
7. **TalkBack:** not required (D11); the project's screen-reader limitation stays documented.

## 17. Documentation updates (Task 6)

This is documented as a **post-submission enhancement**. The historical milestone and UI-polish plans, and the
submitted status lines, are not rewritten.

- **`README.md`**:
  - A feature line: "Colour themes (post-submission enhancement E1): choose Teal, Blue, Rose, Purple or Orange from the
    palette button in the app bar. The app still follows your system's light or dark mode and remembers the choice on
    this device or browser."
  - Under Known limitations: "The colour theme is stored per device or browser (a private window forgets it)."
- **`CLAUDE.md`**:
  - Project: one sentence on the post-submission E1 enhancement.
  - Architecture: an "Appearance" flow covering the palette, the store, `paletteProvider` and the bounded read before
    `runApp`.
  - Testing seams: `paletteStoreProvider` (faked by `FakePaletteStore` in `buildTestApp`) and `initialPaletteProvider`.
  - The colour rule: "the five palette seeds in `lib/features/appearance/domain/app_palette.dart` are the only fixed
    colours".
  - Hard constraints: `shared_preferences` is local only (no host, no secret).
- **`docs/architecture.md`**: a new section, "Post-submission enhancement E1: colour themes", with ADRs for:
  - the one dependency;
  - the bounded read before `runApp` and its trade-off;
  - `MenuAnchor` over the alternatives;
  - palette × brightness;
  - the map-state contract and why it holds;
  - the guard;
  - the reduce-motion behaviour of the existing cross-fade.
- **`docs/assumptions.md`**:
  - Update the Theme row: the selected palette's seed, the brightness from the system, and the guard allowing exactly
    the five seeds.
  - New row "Colour palettes (E1)": the seeds, ids, default and ΔE.
  - New row "Palette persistence (E1)": the key, the platforms, the failure table and the 500 ms startup cap.
  - New row "Palette selector (E1)": the menu, the semantics, the first Tab stop, and the 200 ms cross-fade with no
    in-between frames under reduce motion.
- **`docs/testing.md`**: run-log rows for every task, and an E1 open-items entry.
- **New:** `docs/e1-colour-themes-implementation-plan.md` (this plan) via the docs-only plan PR (D10).

## 18. Commit boundaries

1. Plan PR (docs only): `docs: E1 colour themes implementation plan`.
2. `docs(testing): E1 baseline`.
3. `feat(appearance): five curated palettes, each theme generated from one seed` (includes the guard).
4. `feat(appearance): remember the palette on the device (shared_preferences)`.
5. `feat(appearance): one selected palette drives the app theme`.
6. `feat(appearance): colour theme menu in the app bar`.
7. `test(appearance): a palette change only recolours the journey and the open map`.
8. `docs: E1 colour themes`.
9. `docs(testing): E1 gates`.
10. `docs(testing): E1 live checks`.
11. Review fixes, if any.

Each feature commit is green on its own. Commits 3–6 can each be reverted alone, in reverse order.

## 19. Risks and remaining ambiguities

- **Web keyboard behaviour.** It's verified only at Task 8, because VM widget tests cover the android and windows
  platform variants, not the browser's key path. If it differs, stop and report.
- **The button's open/closed state.** The prototype measured that plain Material doesn't expose it, but not the
  `MergeSemantics` + `Semantics(expanded:)` fix. Task 4 Step 3b adds the wrapper only if the plain-Material test shows
  the need, and stops and reports if the wrapper doesn't work.
- **APK size and the first Android build.** `shared_preferences_android` adds DataStore and Kotlin libraries. Task 7
  measures the APK growth, and the first Gradle build after the change needs network to download them (build time
  only).
- **The palette button becomes the first Tab stop** on Home, before the route card. It's the natural top-right order,
  and no existing test broke in the prototype. It will be documented.
- **The cross-fade** rebuilds the tree, the open map included, on about 12–14 frames per change under normal motion.
  The prototype showed no errors. The system light/dark switch already does the same.
- **Keyboard defaults.** Arrow Down lands on the first option, not the checked one, and the menu doesn't wrap. These
  are Flutter's `MenuAnchor` defaults and are accepted.
- **Timing.** The selection lands one frame after the menu closes (`RadioMenuButton`'s `onChanged`), so tests pump
  twice.
- **Web storage** is per origin, a private window forgets it, and blocked storage gives Teal. Documented.
- **Android Auto Backup** may restore the palette after a reinstall. Harmless.
- **Old ids.** An `indigo` value was never shipped, but if any prototype build stored it, it now falls back to Teal.

## 20. In scope and out of scope

**In scope:**
- the five curated palettes, one seed each;
- the immediate theme update;
- persistence across an Android restart and a Web reload;
- Android and Web, in light and dark;
- the accessible app-bar `MenuAnchor` selector;
- the bounded startup read;
- the map-state contract tests;
- the updated colour guard;
- the documentation.

**Out of scope:**
- a manual light/dark toggle;
- a hamburger, drawer or settings screen;
- a custom colour picker or hex input;
- more palettes, and Indigo;
- Material You or dynamic colours;
- accounts or cloud sync;
- recolouring the map tiles;
- hand-tuned Material roles or per-component overrides;
- a custom colour animation;
- a splash or loading screen;
- a live-region announcement;
- a TalkBack pass as a requirement;
- a map architecture change, or any planner, arrival or map-data change;
- a home-screen redesign;
- the deferred items from earlier milestones (the simplification plan, KL1, KL2, a colour-guard parser, CI, a LICENSE);
- E2.

## 21. Future enhancement E2: static estimated journey time (recorded only; out of scope for E1)

E2 isn't researched or implemented here. The concept is a per-option estimate:

`estimated walk to the boarding stop + estimated in-bus duration + estimated walk to the destination`

These constraints apply when it's planned:
- it's visibly labelled as an estimate;
- it has no live waiting component;
- it doesn't predict traffic;
- showing it must not silently change the planner's ranking;
- before implementing, investigate defensible in-bus-duration data or a model;
- the front-end-only, no-secret architecture is preserved (no DataMall credentials or other secrets).

It needs its own discovery and plan, and no providers are researched during E1.

## 22. Frozen decisions (approved 2026-10-05)

| # | Decision |
|---|---|
| D1 | Palettes: Teal `0xFF009688` (default, today's seed exactly), Blue `0xFF0288D1`, Rose `0xFFE91E63`, Purple `0xFF9C27B0`, Orange `0xFFFF9800`. No Indigo (too close to Blue; Rose doubles the closest-pair separation) |
| D2 | Orange `0xFFFF9800`, derived from the seed only; its golden-brown light scheme is accepted; no roles hand-tuned |
| D3 | An AppBar palette icon that opens a `MenuAnchor` of `RadioMenuButton`s (radio state, name, round swatch); the button is named "Colour theme: <name>"; keyboard behaviour as specified, verified on Web; no hamburger or drawer |
| D4 | `shared_preferences` 2.5.5, only for this non-sensitive local preference; tests use the in-memory fake |
| D5 | A bounded 500 ms read before the first frame; Teal on a missing or unknown value, an error or a timeout; a late result never recolours the session; no splash screen; deterministic and testable |
| D6 | A failed write is silent; the choice stays in memory for the session; nothing pretends it was saved; a restart shows what storage holds |
| D7 | No extra live-region announcement; the radio state and the updated button name carry it; if the semantics turn out inadequate, stop and report |
| D8 | Keep Material's 200 ms theme cross-fade; no custom animation; under reduce motion there are no in-between frames (measured, pinned) |
| D9 | `lib/features/appearance/`, with the domain, persistence, state and presentation separate and one source of truth |
| D10 | A docs-only plan PR first; no implementation until it's merged |
| D11 | No TalkBack pass is required; deterministic semantics tests plus the Web keyboard and semantics checks |
| D12 | Key `colour_palette`; ids `teal`, `blue`, `rose`, `purple`, `orange`; never names, seeds, `ThemeData` or brightness |

---

## Self-review against `main` @ `db604d0` (by the plan author)

1. **Rose has replaced Indigo everywhere.**
   - It's in the enum (`teal, blue, rose, purple, orange`), the seed table (§4), the stored ids (§7, D12), the
     id/label/seed tests (Task 1), the controller, app, menu and invariant tests (Tasks 3–5), the live-check plan
     (§16), the contrast and ΔE evidence (§4–5, re-measured on the final set), the guard (exactly five seeds) and the
     docs (§17).
   - Indigo appears only as a *rejected or never-shipped* value: in the `fromId` fallback checks, the guard's
     not-in-the-enum check, §4, §19 and §20. Task 7's scope check makes sure of this.
2. **No manual light/dark toggle:** `ThemeMode.system` stays (Global Constraints, §20; mutation M5).
3. **No hamburger or drawer:** an AppBar `MenuAnchor` only (D3, §20).
4. **Exactly one new dependency,** `shared_preferences` 2.5.5, with no dev_dependency (§7, §12; Task 7's scope check).
5. **The palette and the brightness stay independent:** `paletteTheme(palette, brightness)` with the brightness from
   the system. Tested in Task 3 (dark keeps the palette) and Task 5 (the tiles follow brightness only).
6. **Loading can't stall startup:** a 500 ms `timeout` that never throws (Task 2: never-completes, mutation M3).
7. **A late read can't recolour the running theme:** Task 2 (a late completion leaves Teal) and Task 3 (the running
   app ignores it and `reads == 0`).
8. **A failed write keeps the in-memory selection:** Task 3 (controller, app, and a restart showing the real storage);
   mutation M1.
9. **A palette selection can't disturb the journey or map state:** §10 and Task 5 (0 plans, refetches, geometry loads,
   refits and tile requests; the State, camera and selection kept); mutations M6, M7 and M10.
10. **645 is the starting point** (Task 0), and the expected progression (estimates, not gates) is 656, 667, 689, 696 and
    698. The real counts are recorded from each run.
11. **E2 is future-only** (§21; listed out of scope in §20).
12. **No historical milestone is rewritten:** §17 adds a post-submission section and rows only, and leaves the
    historical plans and submitted status lines alone.

- **Placeholders:** none. The counts are expectations, replaced by the real numbers from each run (the evidence rule).
- **Consistency:** `AppPalette`, `paletteTheme`, `PaletteStore`, `SharedPreferencesPaletteStore`, `loadInitialPalette`,
  `initialPaletteProvider`, `paletteStoreProvider`, `paletteProvider`, `PaletteController.select`,
  `PaletteMenuButton.tooltipFor`, `PaletteSwatch`, `FakePaletteStore` (with `pendingRead`) and
  `AppearanceConfig.paletteLoadTimeout` match across the tasks, as do the keys `palette-button` and
  `palette-option-<id>`.
- **Evidence:** everything was measured in a throwaway copy of `db604d0`:
  - contrast and ΔE for the final set (0 failures; the closest pair Rose–Purple, 25.3 / 25.6);
  - Teal equivalence;
  - the normal and reduce-motion cross-fade (12 vs 0 in-between frames);
  - the late-read behaviour;
  - the map invariants, menu semantics, keyboard (VM variants), 2× layout, persistence fallbacks, guard and dependency
    resolution, from the prototype (its suite there was 670/670, analyze clean).

  This plan's layout (`features/appearance/`, `Color(0x…)` seeds, a `pendingRead` fake) differs from the prototype's
  only in structure and literal form. The new parts are the expanded semantics and the Web keyboard behaviour, and each
  has a stop rule.
