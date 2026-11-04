# E7 Keyboard Focus Visibility: Implementation Plan

**Status:** approved. The owner approved the E7 name and scope, ruled D1–D5 (§2) and gave final approval of this
plan on 2026-11-04. Implementation starts only on the owner's explicit approval of that step. The PR that adds this
document changes no production code, test, dependency or build configuration.

**Baseline:** written on `cc1db3a` (merge of PR #77, E2); updated to `main` = `2eb8541` (merge of PR #78, E2
close-out: docs and one test, nothing this plan changes).

**What E7 is.** A post-submission enhancement, outside the milestones, like E1–E4 and E2. It makes keyboard focus
visible: every focusable control shows a ring of at least 3:1 contrast against its neighbours, in all ten themes
(five palettes × light and dark), while the app looks exactly as it does today for touch use and for any control
without focus. (As built, a desktop mouse click that moves focus in code also shows the ring: D1, §10.)

**Sources:**
- the E1 known limitation in `docs/testing.md` ("Open acceptance items", E1): the palette button's keyboard focus
  is Material 3's default state layer, about 1.17:1 (e.g. `#ede6e5` on `#fff8f7` in Rose);
- Flutter 3.47.2's own source (`packages/flutter/lib/src/material/`, tag `3.47.2`): `ink_well.dart`,
  `button_style_button.dart`, `text_button.dart`, `outlined_button.dart`, `icon_button.dart`, `menu_anchor.dart`,
  `chip.dart`, `list_tile.dart`, `input_decorator.dart`, `card.dart`, `dialog.dart`, `app_bar.dart`;
- a contrast probe run on real Flutter 3.47.2 in CI (§1.3);
- a read-only inventory of every focusable control in `lib/` (§1.4).

Targets: WCAG 2.2 SC 1.4.11 Non-text Contrast (3:1 against adjacent colours) and SC 2.4.7 Focus Visible (AA).
SC 2.4.13 Focus Appearance (AAA) is not a target, but the 2 px ring was chosen with it in mind.

---

## 1. Findings

### 1.1 Why the current focus fails

Every Material control in the app uses the stock Material 3 focus cue: a 10 % state layer over the control
(`primary`, `onSurface` or `onSurfaceVariant` at opacity 0.1, by control). A 10 % layer cannot reach 3:1 against
its own backdrop: even black over white gives about 1.25:1. Measured on the app's own themes (§1.3), the stock
cue is **1.14–1.31:1** in every theme on every surface the controls sit on. New seeds cannot fix this. The app
needs a drawn indicator.

The app already has one: `FocusRing` in `lib/core/ui/focus_landing.dart` (a 2 px `colorScheme.primary` border
drawn in the foreground, radius 4, shown only when `FocusManager.instance.highlightMode` is `traditional`). It is
used by `FocusLanding` (the focus targets for controls that remove themselves) and by the map. No Material control
uses it. E7 extends this existing indicator to the Material controls and does not invent a second style.

### 1.2 How Flutter 3.47.2 reports focus (it decides the design)

- `InkWell.handleFocusUpdate` sets `WidgetState.focused` whenever the control **has** focus, whatever the highlight
  mode (`ink_well.dart`: "states include WidgetState.focused if the InkWell _has_ the focus, rather than if it's
  showing the focus per FocusManager.instance.highlightMode"). Only the stock state layer is gated by the
  highlight mode.
- So a style that only keys on `WidgetState.focused` would also draw a ring for touch users whenever the app moves
  focus in code. The app does this often: "Select" → the "Selected" mark, Show/Hide map, "Keep this origin" →
  "Change", and the Retry landings.
- `FocusHighlightMode.traditional` is not keyboard-only. *Corrected 2026-11-04 (§10):* in Flutter 3.47.2 a key
  event makes it traditional and a touch makes it touch, but a mouse or trackpad leaves it as it is, and desktop
  (including desktop Web) starts traditional. So on desktop a mouse click that moves focus in code shows the ring,
  where mouse users see only a faint tint today; after a touch it does not. The owner accepted this (D1).
- The stock `OutlinedButton` already changes its 1 px border from `outline` to `primary` when focused, also
  ungated by highlight mode.
- Stock `TextField` focus is a 2 px `primary` `OutlineInputBorder`, which already passes (§1.3).
- `ListTile` and a bare `InkWell` have no focused-state border at all. Their only focus cue is the fill.

### 1.3 Contrast, measured on Flutter 3.47.2

A throwaway probe test (`test/e7_contrast_probe_test.dart` on branch `probe/e7-contrast`, commit `0c7e467`, never
merged) printed each theme's `ColorScheme` from the app's own `paletteTheme`, plus WCAG contrast ratios. It ran in
CI run 41821865017 (Ubuntu, Flutter 3.47.2, all steps green). The relevant surfaces come from the inventory
(§1.4): `surface` (app bar, page, condition tiles), `surfaceContainerLow` (cards), `surfaceContainer` (the palette
menu), `surfaceContainerHigh` (the About dialog) and `surfaceContainerHighest` (the map when tiles are missing).

`colorScheme.primary` as the ring, against each surface:

| Theme | surface | Low | Container | High | Highest | Worst, with the 10 % layer inside |
|---|---|---|---|---|---|---|
| Teal light | 6.19 | 5.89 | 5.58 | 5.32 | 5.03 | 4.15 |
| Teal dark | 10.83 | 10.03 | 9.59 | 8.44 | 7.22 | 5.52 |
| Blue light | 6.15 | 5.84 | 5.58 | 5.29 | **5.00** | **4.12** |
| Blue dark | 10.85 | 10.05 | 9.61 | 8.44 | 7.23 | 5.53 |
| Rose light | 6.18 | 5.86 | 5.58 | 5.28 | 5.01 | 4.13 |
| Rose dark | 10.94 | 10.12 | 9.68 | 8.43 | 7.29 | 5.58 |
| Purple light | 6.16 | 5.85 | 5.58 | 5.29 | 5.01 | 4.13 |
| Purple dark | 10.90 | 10.09 | 9.65 | 8.48 | 7.25 | 5.55 |
| Orange light | 6.16 | 5.85 | 5.55 | 5.26 | 5.02 | 4.13 |
| Orange dark | 10.92 | 10.12 | 9.66 | 8.52 | 7.27 | 5.56 |

"Worst, with the 10 % layer inside" is the ring against the control's own interior: each surface with a 10 %
`primary`, `onSurface` or `onSurfaceVariant` layer blended on it (the stock focus layer stays). Results:

- `primary` passes 3:1 everywhere, with at least 5.00:1 outside and 4.12:1 inside.
- The stock cue is 1.14–1.22:1 in light themes and 1.21–1.31:1 in dark themes.
- Other candidates: `onSurface` ≥ 9.52:1, `onSurfaceVariant` ≥ 7.20:1, `secondary` ≥ 4.98:1, `tertiary` ≥ 4.96:1.
  `outline` fails (2.85:1 inside, Purple light), so it is not a candidate.

These are measurements of the current Flutter version, not a property of Material 3. E7's automated test (§5, T1)
re-checks them in every CI run, so an SDK or seed change that breaks 3:1 fails the build.

**Not covered by the probe:** the map's OneMap tiles. They are imagery, not scheme colours (§2, D2).

### 1.4 Inventory of focusable controls (`lib/`, at `cc1db3a`)

| Control | Sites | Where (examples) | Sits on | Stock focus cue |
|---|---|---|---|---|
| `TextButton` (+ `.icon`) | 13 sources; the `ErrorRetryRow` Retry is used in 6 places | Change, Keep this origin/destination, Try location again, Open settings, Show/Hide steps, Refresh arrivals, Hide map, every Retry, About dialog's View licenses and Close | cards (`surfaceContainerLow`), condition tiles (`surface`), dialog (`surfaceContainerHigh`) | 10 % `primary` layer |
| `IconButton` | 4 | About and palette (app bar), Refresh conditions (page), Clear search (inside the field) | `surface`, `surfaceContainerLow` | 10 % `onSurfaceVariant` layer |
| `OutlinedButton` (+ `.icon`) | 2 | Select (journey card), Show map (page) | `surfaceContainerLow`, `surface` | 10 % layer + 1 px `primary` border |
| `RadioMenuButton` | 5 (one per palette) | palette menu | `surfaceContainer` | 10 % `onSurface` layer |
| `ActionChip` | 1 | "Use my current location" | `surfaceContainerLow` | 10 % layer |
| `ListTile` | 1 builder (each search result) | place-search results | `surfaceContainerLow` | focus fill |
| `InkWell` | 1 builder (2 links) | "OneMap", "Singapore Land Authority" attribution links | `surfaceContainerLow` | focus fill, rectangular |
| `TextField` | 1 builder (origin, destination) | place search | `surfaceContainerLow` | 2 px `primary` border (passes) |
| `FocusLanding` | 8 | section titles, option title, "Selected" mark, the origin section | as its section | the existing `FocusRing` |
| Map (`KeyboardOptions` focus node) | 1 | journey map | OneMap tiles | the existing `FocusRing` |

The app has no `FilledButton`, `ElevatedButton`, other chips, `SubmenuButton`, `PopupMenuButton`, dropdowns,
switches, sliders, `SegmentedButton`, FAB or tab bar, and no `GestureDetector`. Framework-owned UI reached from the
app: Flutter's licence page (`showLicensePage`, from About), with an `IconButton` back button and `ListTile`s. No
`SnackBar` has an action.

---

## 2. Decisions (owner rulings, 2026-11-04)

| # | Decision | Status |
|---|---|---|
| **D1** | **When the ring shows.** The ring shows on the focused control while Flutter's `FocusManager.instance.highlightMode` is `FocusHighlightMode.traditional`, the same rule the existing `FocusRing` already uses. The app listens through `FocusManager.instance.addHighlightModeListener`. There is no custom last-input tracker. **Consequence** (wording corrected 2026-11-04, §10)**:** a mouse keeps the mode it finds, and desktop starts traditional. So on desktop, after a mouse click that moves focus in code ("Select" → the "Selected" mark, Show/Hide map, "Keep this origin/destination" → "Change", a Retry → its landing), the newly focused control shows the ring. That is where mouse users already see a `FocusLanding` ring or the stock focus tint today. With the mouse, nothing changes on an unfocused control or on hover or press. Touch mode shows no ring | **Approved 2026-11-04**, including the mouse consequence. Requirements: keyboard focus shows the ring; mouse-triggered code-driven focus may show it; hover alone never shows it; touch keeps today's look; unfocused, hovered and pressed controls are unchanged (T2–T4) |
| **D2** | **The map's ring over tile imagery.** Tiles are arbitrary colours, so a single `primary` ring cannot be guaranteed 3:1 on them. The map alone gets a two-colour ring: 2 px `primary` outside, with a 2 px `surface` band inside it. The `primary`/`surface` pair has at least 6.15:1 in every theme, so the ring contrasts with the band beside it whatever the tile, and the card outside is ≥ 5.84:1. Other controls keep the single ring | **Approved in principle 2026-11-04**, subject to T1 (the pair ≥ 3:1 in all 10 themes) and the Web live check over real OneMap Default and Night tiles (§6) |
| **D3** | "While the highlight mode is traditional (D1), a focused `OutlinedButton` ('Select', 'Show map') shows the shared 2 px `primary` ring in place of Flutter's stock 1 px `primary` focused border. In touch mode the button is unchanged from today, including the stock 1 px `primary` border Flutter draws whenever the button holds focus." One indicator for keyboard users; the touch look stays exactly as it is | **Approved 2026-11-04** |
| **D4** | "Flutter's licence page (About → View licenses) is framework UI. E7 does not restyle it. Its back button is an `IconButton` under the app theme, so it gets the ring. The package list keeps Flutter's stock focus fill, which is below 3:1. This is recorded as a known limitation in `docs/assumptions.md` and `docs/testing.md`, and T7 pins both halves." Fixing the list means re-implementing a framework page, which is out of E7's scope. The limitation is never described as resolved or as meeting WCAG | **Approved 2026-11-04 with this documented limitation** |
| **D5** | **Focus hand-off gaps** the inventory found: "Use my current location" disappears, and the ready-phase "Try location again" disables itself, with no focus hand-off. (The place-search Retry is the documented exception.) | **Ruled 2026-11-04:** out of E7; two separate GitHub issues |

Fixed by the approved scope (not questions): ring colour `colorScheme.primary` (measured, §1.3), width 2 px, no
new dependency, no `Colors.*`, no change to any unfocused, hover, pressed or touch appearance.

---

## 3. Design

### 3.1 One signal: Flutter's focus highlight mode (D1)

No custom tracker. A small widget in `lib/core/ui/` (no package) exposes Flutter's own signal:

```text
FocusHighlightScope (InheritedWidget, installed once in MaterialApp.builder)
  value: FocusManager.instance.highlightMode == FocusHighlightMode.traditional
  rebuilds on FocusManager.instance.addHighlightModeListener (removed on dispose)
```

- It covers every route, dialog and menu.
- Flutter switches to traditional on a hardware key event and to touch on a touch or stylus pointer; a mouse or
  trackpad, and an Android soft-keyboard key event, leave it as it is (corrected 2026-11-04, §10). Its default
  strategy (`FocusHighlightStrategy.automatic`) is kept.
- Tests drive it the Flutter way: a key event (`tester.sendKeyEvent`) or a pointer of a given kind.

### 3.2 One look: the shared ring

`FocusRing` keeps its look (2 px `primary`, foreground, radius 4) and its rule (traditional mode). It now reads
`FocusHighlightScope`, so it rebuilds when the mode changes; today it does not listen to highlight-mode changes.
For the Material controls the same colour and width are set through component themes, applied **only in
traditional mode**:

```text
MaterialApp.builder
  FocusHighlightScope
    Theme(data: traditional ? withFocusRings(Theme.of(context)) : Theme.of(context))
      child (Navigator: every page, dialog and menu)
```

`withFocusRings` is a pure function: it copies the theme with one added `side` for `WidgetState.focused` (2 px
`colorScheme.primary`) and `null` for every other state, so all other states fall through to the stock defaults.

- **In touch mode:** the theme is today's `paletteTheme` object, unchanged. The touch look is identical by
  construction, and a regression test checks that (§5).
- **In traditional mode:** only the focused state differs. Unfocused, hover and pressed states resolve to the stock
  values, for mouse and keyboard alike (T2).
- **A plain `Theme`, not `AnimatedTheme`:** a mode change is instant, and the E1 palette animation inside
  `MaterialApp` is untouched.
- **Palette or brightness change:** `Theme.of(context)` is already the new theme, so the ring follows the new
  `primary` at once.

### 3.3 Per control

| Control | Mechanism | Notes |
|---|---|---|
| `TextButton`, `IconButton`, `OutlinedButton` | `textButtonTheme`, `iconButtonTheme`, `outlinedButtonTheme`: `ButtonStyle(side: focused → 2 px primary)` | `ButtonStyleButton` resolves widget → theme → default per state, so `null` keeps the stock value. The side is painted on the existing shape: no size change. `OutlinedButton`'s stock focused border is replaced (D3) |
| `RadioMenuButton` | `menuButtonTheme`, same `side` | Covers the palette menu; the menu opens and closes by keyboard as today |
| `ActionChip` | `chipTheme.side`: a `WidgetStateBorderSide` (focused → 2 px primary, else `null`) | `null` falls back to the chip's default side (`chip.dart` `_getShape`). *As built: `FocusRingWithin` (§10, owner decision 1)* |
| `ListTile` (search results) | wrap in `FocusRing` driven by the tile's `onFocusChange` | `ListTile` has no state-resolved border. The ring follows the tile's shape. *As built: `FocusRingWithin`, a non-focusable `Focus` wrapper that tracks focus within (§10)* |
| `InkWell` links (attribution) | wrap in `FocusRing` driven by `onFocusChange` | Rectangle to radius 4, as `FocusRing` already draws. *As built: `FocusRingWithin` (§10)* |
| `TextField` | none | Stock 2 px `primary` border passes (≥ 5.84:1 on the card). Pinned by a test |
| `FocusLanding` (8) | existing `FocusRing`, new signal | Look unchanged |
| Map | existing `FocusRing`, new signal, two-tone (D2) | A `FocusRing(twoTone: true)` parameter, used only by the map |

No semantics node is added. `FocusRing` is a `DecoratedBox` and the component themes change only paint. This
keeps the "Screen readers and focus" rule in `docs/assumptions.md`.

---

## 4. Files (implementation PR, not this plan PR)

| File | Change |
|---|---|
| `lib/core/ui/focus_highlight_scope.dart` | **New**: `FocusHighlightScope` (Flutter's highlight mode, D1) |
| `lib/core/ui/focus_landing.dart` | `FocusRing` reads the scope and rebuilds on change; optional two-tone |
| `lib/features/appearance/presentation/focus_ring_theme.dart` | **New**: pure `withFocusRings(ThemeData)` |
| `lib/app/app.dart` | `MaterialApp.builder`: the scope and the traditional-mode `Theme` |
| `lib/features/places/presentation/place_search_field.dart` | Result `ListTile`s in `FocusRing` |
| `lib/features/map/presentation/basemap.dart` | Attribution links in `FocusRing` |
| `lib/features/map/presentation/journey_map.dart` | Map ring two-tone |
| tests (§5), `docs/architecture.md`, `README.md`, `CLAUDE.md` | as listed |
| `docs/assumptions.md` | An E7 row: D1–D4 as ruled, including the licence page's package list as a known limitation below 3:1 (D4) |
| `docs/testing.md` | Run log and evidence; under "Open acceptance items", the D4 package-list focus contrast as an open known limitation, not resolved |

Not changed: `paletteTheme`, `app_palette.dart`, every provider, the planner, arrivals, the map's scene and camera,
any host, the CSP, `pubspec.yaml`.

---

## 5. Test-first task sequence (`tdd` skill: each RED test is committed and seen failing in CI first)

**Automated, in `flutter test` (CI):**

- **T1 Contrast (automated accessibility check).** For all 10 themes: `primary` ≥ 3:1 against `surface`,
  `surfaceContainerLow`, `surfaceContainer`, `surfaceContainerHigh` and `surfaceContainerHighest`, and against each
  of those with a 10 % `primary`/`onSurface`/`onSurfaceVariant` layer. Also the map's two-tone pair ≥ 3:1.
  Ratios come from `Color.computeLuminance` (WCAG relative luminance).
- **T2 Touch mode is today's theme.** In touch mode, the theme under `MaterialApp` equals
  `paletteTheme(palette, brightness)` for all 10 themes, and `withFocusRings` leaves every non-focused state's
  resolved style (unfocused, hovered, pressed) equal to the stock one.
- **T3 Each control shows the ring in traditional mode.** One widget test per control type in §3.3: Tab to the
  control, then read the painted indicator (the resolved `Material.shape.side`, or `FocusRing`'s border) and check
  2 px and the theme's `primary`.
- **T4 Touch and mouse (D1).** For each code-driven focus move (Select → Selected, Show/Hide map, Keep this
  origin → Change, a Retry landing): after a touch tap the newly focused control shows no ring and its shape equals
  stock; after a mouse click on desktop it shows the ring (the D1 consequence, pinned), and after a touch followed
  by a mouse click it does not (corrected 2026-11-04, §10). With the mouse, unfocused, hovered and
  pressed controls equal stock. Hover alone (a mouse over an unfocused control, no click) shows no ring. A touch
  pointer down hides the ring; a key event shows it again. In touch mode a focused `OutlinedButton` keeps Flutter's
  stock 1 px `primary` border (D3).
- **T5 Mode signal.** `FocusHighlightScope` follows `FocusManager.instance.highlightMode` and rebuilds its
  dependants on every change; the listener is removed on dispose. No key event is consumed (Tab still moves
  focus).
- **T6 Menus.** Keyboard-open the palette menu, arrow through the five items (each ringed), Escape: focus and the
  ring return to the palette button.
- **T7 Dialogs.** Keyboard-open About, Tab to View licenses and Close (each ringed), close: the About button is
  focused with the ring. From View licenses, the licence page's back button shows the ring (D4). Its package list
  keeps Flutter's stock focus fill: the test pins that as the D4 limitation, not as a pass.
- **T8 Theme changes.** Choosing a palette by keyboard, and switching light ↔ dark, keep the focused control's
  ring in the new theme's `primary`, in one frame.
- **T9 Invariants.** A mode change requests nothing and keeps the map state, camera, plan, arrivals, geometry and
  selection, like `palette_change_invariants_test.dart`. No size change: focused and unfocused sizes are equal.
  360 px with 2× text: no overflow. Semantics trees with and without the ring are equal.
- **T10 Existing guards stay green.** `app_theme_test.dart` (no `Colors.*` in `lib/`), the E1 palette tests and the
  accessibility tests.

**Mutation checks** (each on a throwaway `mut/e7-<id>` branch, CI run recorded, branch deleted, as in E2):
- ring in `outline` (T1 fails);
- 1 px (T3);
- no highlight-mode gate (T4);
- `menuButtonTheme` dropped (T6);
- a ring on every state (T2);
- the scope not rebuilding on a mode change (T5).

**Integration** (Android and Web, `integration_test/`, deterministic): `app_boot_test` gains a Tab walk through
the app bar with the ring asserted. The three files pass on both platforms.

## 6. Manual verification (recorded in `docs/testing.md`; anything not run is logged as **Not run**)

- **Web (Chrome, release build, WebDriver):**
  - Tab through the whole page in all 10 themes, with a screenshot of each ring.
  - Sample the pixel contrast of the ring against its neighbours, including the map over real OneMap Default and
    Night tiles (D2).
  - Click with the mouse: no ring on unfocused, hovered or pressed controls; on desktop the ring after the
    code-driven focus moves (D1).
  - Emulated touch.
  - Palette menu and About dialog by keyboard.
  - 360 px with 2× text.
  - 0 CSP violations.
- **Android (emulator):**
  - `adb shell input keyevent KEYCODE_TAB` walk with screenshots, in light and dark.
  - Touch use: no ring. The soft keyboard in a search field, then a code-driven focus move: record whether a ring
    appears (§8).
- **Expected Not run:**
  - a physical keyboard on a physical phone (no hardware);
  - TalkBack, VoiceOver and NVDA (E7 changes paint only; semantics are covered by T9);
  - Android in every palette (the Web runs all 10, and T1/T3 cover all 10).

## 7. Commit boundaries (branch `feat/e7-keyboard-focus-visibility`, after this plan is approved and merged)

1. RED: T1, T2, T5 (pure).
2. GREEN: `FocusHighlightScope` + `withFocusRings`.
3. RED: T3, T4, T6–T8 (widgets).
4. GREEN: wiring in `app.dart`, `FocusRing`, `ListTile`/`InkWell` wrappers, map two-tone.
5. T9 invariants.
6. Integration.
7. Docs.
8. Run log and evidence.

The PR goes up for review; it is not merged without the owner's approval.

## 8. Risks and stop conditions

- **A soft keyboard sends key events** (some Android IMEs do, for Enter or Backspace). Flutter then switches to
  traditional mode, so a touch user could see a ring on the next code-driven focus move until their next tap. The
  existing `FocusRing` already behaves this way. The Android soft-keyboard check (§6) looks for it; if seen, it is
  recorded for an owner ruling, not worked around with a custom tracker (D1).
- **A framework widget ignores the component theme.** Stop and report rather than restyle it by hand.
- **Contrast drops below 3:1 after an SDK change.** T1 fails the build; the fix is a ruling, not a lint suppression.
- **Stop if** the design needs a dependency, a change to `paletteTheme`, a provider, the planner, arrivals or the
  map scene, or any change to the touch appearance or to unfocused, hovered or pressed controls.

## 9. Out of scope

- The focus hand-off gaps (D5).
- The licence page's `ListTile`s (D4).
- Hover and pressed styles.
- A focus-order change.
- E5.

## 10. Implementation notes (2026-11-04)

Found while implementing on `feat/e7-keyboard-focus-visibility`. The rulings in §2 are unchanged; these correct facts
or mechanisms above. Rationale: `docs/architecture.md`, ADRs E7-1 to E7-5.

| Where | Planned | As built, and why |
|---|---|---|
| §1.2, D1 consequence | A mouse or trackpad switches Flutter to traditional mode | Flutter 3.47.2 leaves the mode as it is on a mouse or trackpad; a key makes it traditional, a touch makes it touch, and desktop (including desktop Web) starts traditional. So a mouse click that moves focus in code shows the ring in traditional mode, and not after a touch. D1's requirements hold. **Accepted by the owner on 2026-11-04 (decision 2)**; no custom input tracker. §1.2, the D1 row, §3.1, T4 and §6 are corrected in place |
| §3.3, chip | `chipTheme.side` as a `WidgetStateBorderSide` | `FocusRingWithin` (radius 8; on Android and iOS the ring goes around the chip's 48 dp touch target). This changed the approved per-control mechanism without a prior ruling (§8 said to stop and report). **Approved by the owner on 2026-11-04 (decision 1)** with conditions: the 48 dp touch target unchanged; no clipping, overlap, hit-testing change or layout shift; the touch look and focus behaviour kept. `test/app/focus_ring_app_test.dart`, "the chip ring (decision 1)", pins them. In 3.47.2 `ChipThemeData._lerpSides` throws on a state side that is null at rest, and each button's own `AnimatedTheme` lerps the theme on every theme change; T8 caught focus being dropped |
| §3.3, menu items | `menuButtonTheme` rings `RadioMenuButton` | Kept, but `MenuItemButton` draws through a `TextButton` in 3.47.2, so `textButtonTheme` also rings it; the mutation without `menuButtonTheme` is caught by T2, not T6 |
| §4, files | `lib/features/appearance/presentation/focus_ring_theme.dart` | `lib/core/ui/focus_ring_theme.dart` (with the `FocusRingTheme` widget), next to `focus_highlight_scope.dart` as planned: `FocusRing` in `core/` shares its colour and width, and `core/` must not import a feature. No `buildTestApp` seam: tests drive Flutter's mode with real key, touch and mouse events |
| §3.3, ListTile and InkWell | `FocusRing` driven by the control's `onFocusChange` | One shared `FocusRingWithin` (a `Focus` with `canRequestFocus: false`, `skipTraversal: true`, `includeSemantics: false`) for the ListTile, the links and the chip: no Tab stop, no semantics node |
| Final review I1 | — | On a phone Flutter's mode is the platform default until the first touch or key, and that default turns traditional while a mouse is connected without notifying highlight-mode listeners. `FocusHighlightScope` also listens to `MouseTracker` and re-reads the mode; still no custom tracker (D1) |
| §5, T6 and T8 | — | T8 skips the one frame in which the menu hands focus back (a post-frame callback), as for Flutter's own focus highlight. The #58 map test now expects two bordered boxes (the two-colour ring) |

