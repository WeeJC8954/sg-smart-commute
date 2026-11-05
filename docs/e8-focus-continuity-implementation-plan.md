# E8 Focus Continuity: Implementation Plan

**Status:** approved and implemented on `feat/e8-focus-continuity`. The owner approved decisions D1–D3 (§2), this
plan and the O1 ruling (§3.3, option A) on 2026-11-05, then the implementation, then, after T81-7 found a defect, a
narrow exception to D3 (§3.4). What was built, and how it differs from this plan: §10.

**Baseline:** `main` = `600944c` (merge of PR #85, E7 close-out). CI on it: run 42016401482, `flutter test`
**937 passed**, Chrome step **32 passed**.

**What E8 is.** A post-submission enhancement, outside the milestones, like E1–E4, E2 and E7. It fixes two keyboard
focus losses that E7's inventory found (E7 D5) and kept out of E7: issue **#80** (the "Use my current location" chip)
and issue **#81** (the manual-origin "Try location again"). Each fix is small and follows the CLAUDE.md rule that a
control that removes or disables itself when pressed hands focus on. The two issues stay separate in tests, commits
and docs.

## 1. Findings

Both controls are in `lib/features/origin/presentation/origin_card.dart` (at `600944c`). Neither hands focus on. When
a focused node is unmounted or can no longer take focus, Flutter 3.47.2 moves focus to an earlier node in the
scope's focus history. So where focus lands depends on how the user got to the control. A throwaway widget probe
(`test/e8_probe_test.dart`, run locally on 2026-11-05 and deleted, never committed) confirmed this:

### 1.1 #80: "Use my current location" chip

`ActionChip` `use-current-location`, `onPressed: controller.useCurrentLocation`. The press applies the offered fix
(`_setGpsOrigin`), so the origin turns GPS, the phase turns `ready`, and the chip is unmounted. The chip is offered
in two layouts:

| Path (probe) | Focus after the press | Next Tab |
|---|---|---|
| Normal view (manual origin set), Tab from "Change" → "Try location again" → chip | "Change" (still in the focus history) | destination field |
| "Change" open (search field shown), Tab to the chip | the route's scope: **focus lost** | **About** (top of page) |

The first row works only because "Change" was focused earlier. Any other route to the chip (e.g. Shift+Tab from the
destination field) leaves focus on whatever came before it. The issue text says focus always returns to the top;
in fact, it depends on what had focus before.

### 1.2 #81: manual-origin "Try location again"

`TextButton` `retry-location`, `onPressed: state.locatingInBackground ? null : controller.retryLocation`. The press
starts a background attempt and disables the button for up to about 20 s (the 10 s permission bound, then the 10 s
fix timeout). A disabled button cannot keep focus.

| Path (probe) | Focus after the press | Next Tab |
|---|---|---|
| Tab from "Change" to the button | "Change" | the destination field |
| Shift+Tab from the destination field to the button | **the destination field** | conditions Refresh |

The second row moves focus into a text field the user did not choose; on a phone that can open the soft keyboard
unasked.

### 1.3 Existing infrastructure that fixes both

- `_focusChangeAfterRebuild()`: requests focus on `_changeButton` in a post-frame callback. Already used after
  picking a place and "Keep this origin".
- `_section`: the origin card's `FocusLanding` (E7-ringed, `skipTraversal`, no semantics node of its own). Already the
  hand-off target of the location fallback's "Try location again" (#65). The probe showed: from the landing, Tab →
  "Change"; Shift+Tab → the previous control before the route card.

No custom focus tracker, no new widget and no new semantics node is needed.

## 2. Decisions (owner rulings, 2026-11-05)

| ID | Ruling |
|---|---|
| D1 (#80) | After "Use my current location", focus goes to the existing "Change" once the UI has updated, in both layouts (normal view and "Change" open). The next Tab moves to the destination search field. |
| D2 (#81) | Before "Try location again" disables, focus goes to the origin section's existing `FocusLanding`. The next Tab moves to "Change". Focus stays put when the attempt succeeds, fails or times out. The destination field is never focused, and no keyboard opens. #57 announcements unchanged. |
| D3 | The hand-off runs on every activation (keyboard, touch, mouse), not only when the control has focus, as for the existing hand-offs (#56, #65, picking a place). No custom focus tracker, no new semantics node, no unintended touch or mouse appearance change; no focus movement caused only by a rebuild or an asynchronous state update. E7's ring rules are unchanged (D1 of E7: in traditional mode a code-driven focus move after a mouse click shows the ring; in touch mode no ring). |

## 3. Design

### 3.1 #80

```dart
onPressed: () {
  controller.useCurrentLocation();
  _focusChangeAfterRebuild();
},
```

Post-frame, because in the "Change open" layout "Change" does not exist until the rebuild. `useCurrentLocation` is
unchanged (a no-op without an offer; the callback then focuses the existing "Change", which is still a defined place).

### 3.2 #81

```dart
void _retryInBackground() {
  _section.requestFocus(); // before the button disables (#81)
  ref.read(originControllerProvider.notifier).retryLocation();
}
```

Synchronous, like `_retryFromFallback`, so Flutter never falls back to the focus history. Unlike that method it does
**not** set `_announceFix`: a fix from a background attempt is only offered by the chip (already announced, #57),
never applied. The controller, its states and the announcements are unchanged.

### 3.3 O1: the button disabled again without a press (ruled: option A)

The background attempt can disable the button again **without a press**: when the permission prompt is answered after
its 10 s bound, `resumeIfAnsweredLate` sets `locatingInBackground` back to true. If the user has meanwhile tabbed back
to the re-enabled button, Flutter moves focus to the focus history again. In the common case (the section, then Tab
to "Change", then the button) that history is inside the origin card; it is not proven for every path. D3 forbids a
focus move caused by an asynchronous update. Options were:

- **(a)** No code for it. Test T81-7 reproduces both keyboard paths and checks where focus goes.
- **(b)** Keep the button enabled while busy and ignore presses. This changes how it looks and how it is announced
  (today a screen reader hears it as disabled while busy).

**Owner ruling (2026-11-05): option A.** No production change for this case in E8. T81-7 must check that focus
stays in a meaningful place in the origin section: the section's `FocusLanding` or "Change"; never a scope node,
the destination field, any control outside the origin card, or a visible text input. Focus that escapes is a
defect even if Flutter does it today; the test is not weakened to match. If T81-7 fails on a path: record the
observed behaviour in `docs/testing.md`, do not commit the failing test, change nothing in the UI or the button's
enabled/disabled behaviour, and report to the owner for a separate decision. E8 scope does not grow.

**Outcome:** T81-7 failed on the Shift+Tab path (§3.4), so option A led to a separate ruling.

### 3.4 T81-7 finding and the narrow exception to D3 (owner ruling, 2026-11-05)

**Finding.** The steps are:
1. Location is denied at launch. The user picks a place as the origin.
2. The user presses "Try location again" by Tab and Enter; focus goes to the landing.
3. The permission prompt stays unanswered for 10 s. The note shows and the button is enabled again.
4. The user reaches the button again: by Tab, or by Shift+Tab from the destination field.
5. The permission answer arrives late. The attempt runs again and disables the button without a press.

On the Tab path, Flutter's focus history put focus on "Change" (inside the card). On the Shift+Tab path it put
focus on the **destination search field**, and a text input opened (a phone's soft keyboard, unasked). E8's press
hand-off cannot help: there is no press. Run log: `docs/testing.md`, 2026-11-05.

**Ruling: a guarded hand-off, a narrow exception to D3.** It is necessary because only an asynchronous update
disables the button here, and Flutter's fallback can then move focus out of the origin card. The rule:

- The trigger is an asynchronous location update that is about to disable the manual-origin "Try location again".
- If that button has focus, focus goes to the origin section's `FocusLanding` before the button is disabled.
- If the button does not have focus, nothing moves. Focus that the user moved elsewhere stays there.
- A rebuild or a GPS state change alone moves nothing.
- The button's enabled/disabled behaviour and the #57 announcements are unchanged.
- It uses the existing `FocusLanding` plus one dedicated `FocusNode` on that button (disposed with the state). There
  is no global tracker, no new semantics node and no controller change.

## 4. Files (implementation PR, not this plan PR)

| File | Change |
|---|---|
| `lib/features/origin/presentation/origin_card.dart` | §3.1 and §3.2 only, with comments citing #80 / #81 |
| `test/app/focus_continuity_test.dart` (new) | T80-*, T81-* |
| `integration_test/fallback_path_test.dart` | one keyboard case per issue (§5.3) |
| `docs/assumptions.md` | "Screen readers and focus" row: the chip → "Change", the manual-origin "Try location again" → the origin section |
| `CLAUDE.md` | the enhancement list gains E8 with this plan's path |
| `README.md` | Documentation list: this plan |
| `docs/testing.md` | run log rows; Open acceptance items: E8, with Not run lines |

## 5. Test-first sequence (each RED commit is pushed alone and seen failing in CI, as in E2 and E7)

Tests use `buildTestApp` with `FakeLocationService`, real Tab / Shift+Tab / Enter key events
(`tester.sendKeyEvent`), so focus traversal and the highlight mode are real.

### 5.1 #80 (`group('#80 ...')`)

- **T80-1** Normal view, Tab to the chip, Enter → `primaryFocus` is "Change"; one Tab → the destination field.
  (Guard: passes today by focus history, §1.1.)
- **T80-2 (RED)** Normal view, Shift+Tab from the destination field to the chip, Enter → "Change"; Tab → the
  destination field.
- **T80-3 (RED)** "Change" open, Tab to the chip, Enter → "Change" (the new one); Tab → the destination field;
  never the About button or a scope node.
- **T80-4 (RED)** The launch fallback while typing (a late fix offered during manual entry), chip → "Change".
- **T80-5** Touch: a tap in touch mode leaves "Change" focused and paints no ring (E7 rule).
- **T80-6** Semantics: the chip is still a live-region button "Use my current location" (#57); after the press the
  origin line is not a live region (no new announcement); the focused flag is on the existing "Change" node.

### 5.2 #81 (`group('#81 ...')`)

- **T81-1 (RED)** Tab path: Enter on the button → `primaryFocus` is the origin section's landing (`focusedAt` the
  "Finding your location…" row, not a `FocusScopeNode`); Tab → "Change"; Shift+Tab from the landing → the control
  before the route card.
- **T81-2 (RED)** Shift+Tab path from the destination field: Enter → the landing; the destination field is not
  focused and `tester.testTextInput.isVisible` is false.
- **T81-3 (RED)** Focus stays on the landing after each outcome, each in its own test:
  - success: granted + fix, so the chip is offered;
  - failure: denied, so the failure note shows;
  - permission timeout: unanswered for 10 s;
  - fix timeout: granted, no fix for 10 s.

  In each, the #57 live regions are unchanged (the failure note's text; the chip).
- **T81-4** Touch: a tap leaves the landing focused, with no ring.
- **T81-5** Semantics: the landing adds no node (the focused flag is on the existing route-card node, as for #65);
  "Try location again" is still disabled while busy (`isEnabled: false`, as today).
- **T81-6** After a background fix and the chip press, the origin line is not announced (pins that #81 does not set
  `_announceFix`).
- **T81-7** O1 (§3.3, option A): after the permission timeout re-enables the button, the user reaches it by Tab
  (from the landing via "Change") and, in a second test, by Shift+Tab from the destination field; then the late
  permission answer disables it again. Focus must be on the section's landing or "Change", and no text input is
  shown. A failure is reported, not committed or weakened (§3.3).

### 5.3 Integration (Android and Web, fakes only, deterministic)

`fallback_path_test.dart` gains two cases: the #81 Tab path (landing, then Tab → "Change") and the #80 "Change open"
path (chip → "Change"). The three integration files pass on `emulator-5554` and on Web through `flutter drive`.

### 5.4 Mutation checks (each a throwaway `mut/e8-<id>` branch from a GREEN head, pushed alone, CI run recorded,
deleted; none merged)

| ID | Mutation | Must fail |
|---|---|---|
| m80a | chip without `_focusChangeAfterRebuild` | T80-2, T80-3, T80-4 |
| m80b | `_changeButton.requestFocus()` synchronously, not post-frame | T80-3 |
| m81a | `_retryInBackground` without `_section.requestFocus()` | T81-1, T81-2, T81-3 |
| m81b | `_retryInBackground` sets `_announceFix = true` | T81-6 |
| m81c | hand-off to "Change" instead of the landing | T81-1 |

### 5.5 Guards that stay green

`test/app/accessibility_test.dart` (#56, #57, #65), `test/app/focus_ring_app_test.dart` (the chip ring, D1 of E7),
`test/app/focus_mode_invariants_test.dart`, `test/widget_test.dart` (late fix, chip), the E7 scope tests.

## 6. Verification (recorded in `docs/testing.md`; anything not run is logged as **Not run** with the reason)

- **Gates:**
  - CI on every pushed head, local `dart format --set-exit-if-changed .`, `flutter analyze` and `flutter test`;
  - `flutter build web --release` and `flutter build apk --debug`;
  - Android integration on `emulator-5554` and Web integration through `flutter drive`, three files each.

  The test count rises from 937 by the number of new tests; the Chrome step stays 32 (no pure-Dart file changes).
- **Web live check:**
  - setup: a release build, headless Chrome over WebDriver/CDP, location denied then granted through CDP, as in
    the E7 chip check;
  - both issues on the Tab and the Shift+Tab path;
  - screenshots of where the ring is after each press and after each outcome;
  - a mouse click and an emulated touch;
  - 0 CSP violations.
- **Expected Not run** (the evidence that stands in is in brackets):
  - Android hardware-keyboard Tab walk: `adb shell input keyevent` is ignored for the highlight mode, and the
    emulator's hardware keys did not reach the app in E7. (Widget tests; Android integration with synthetic key
    events; the Web live check.)
  - A real phone or tablet with a keyboard and a mouse: no hardware.
  - Android live location and journey: the emulator's HTTPS fails on this PC (Avast). (Integration with fakes.)
  - TalkBack, VoiceOver and NVDA: no screen reader run is possible here. (T80-6, T81-5: semantics flags.)

## 7. Commit boundaries (branch `feat/e8-focus-continuity`, after this plan is approved and merged)

1. `test(e8): #80 focus after "Use my current location" (RED)`
2. `fix(origin): hand focus to Change after the chip (#80)`
3. `test(e8): #81 focus after the manual-origin "Try location again" (RED)`
4. `fix(origin): hand focus to the origin section before the retry disables (#81)`
5. Integration cases.
6. Docs (assumptions row, CLAUDE.md, README).
7. Run log and evidence.

The PR body says "Closes #80, closes #81", so both close only when the owner merges it. No merge without the
owner's approval.

## 8. Risks and stop conditions

Stop and ask the owner if:

- a fix needs a controller, provider or state change;
- a fix needs a new widget, a new focus node outside `_OriginCardState`, or a semantics node;
- T81-7 shows focus can leave the origin section (§3.3: report, no change);
- an existing guard (§5.5) must change;
- the CI count changes other than by the new tests.

## 9. Out of scope

Any other focus behaviour, the D4 licence page (E7), new announcements, visual changes, the controller's attempt
logic, issue #82 and the repository secret, E5 and the next-phase roadmap
(`docs/sg-smart-commute-next-phase-master-plan.md`).

## 10. Implementation notes (2026-11-05)

All runs and their CI run ids are in the `docs/testing.md` run log.

**As built** (`lib/features/origin/presentation/origin_card.dart` only):
- #80: the chip's `onPressed` calls `useCurrentLocation()`, then `_focusChangeAfterRebuild()` (§3.1).
- #81: `_retryInBackground()` requests the landing, then calls `retryLocation()` (§3.2).
- The T81-7 guard (§3.4):
  - `ref.listen` on `locatingInBackground` (false → true) schedules a microtask.
  - The microtask moves focus to the landing only if the widget is still mounted, the attempt is still running and
    `_retryButton` still has focus.
  - Riverpod notifies listeners synchronously. The microtask runs before the rebuild that disables the button, so
    focus moves first and Flutter's fallback never runs.
  - The re-check (independent review, I1) covers a late *failure* answer. That answer turns the flag on and off in
    one turn, and the button stays enabled and keeps focus.

**Differences from §5:**
- **Mouse T81-4 (review M1).** A mouse click in traditional mode does not focus the button, so the press hand-off
  alone moves focus. This test is what kills m81a. The guard also covers a keyboard press, so the keyboard tests
  alone no longer catch m81a.
- **Four tests added to T81-7:**
  - a late *failure* answer leaves focus on the button, which stays enabled (review I1; RED first);
  - focus elsewhere (the destination field) is left alone: this one pins the guard's own condition;
  - touch keeps its focus and touch mode;
  - both keyboard paths now require the landing, the next Tab on "Change" and the destination field never focused.
- **Integration.** The landing is matched by the `FocusLanding`'s node, not `debugLabel`, which is debug-only. The Web
  runs use a profile build.
- **m80b survives, and it is an equivalent mutant.** Flutter keeps a focus request on a node that is not attached yet
  (`_requestFocusWhenReparented`, `focus_manager.dart`) and applies it when the node is attached. So a synchronous
  request also works with "Change" open. §3.1's "post-frame, because" is too strong; the chip keeps the shared helper.

**Mutation results** (final code, `afefae6`):

| ID | Mutation | Result |
|---|---|---|
| m80a | no chip hand-off | killed: T80-2, T80-3, T80-4 |
| m80b | synchronous request | survives (equivalent, above) |
| m81a | no press hand-off | killed: T81-4 touch and mouse |
| m81b | the retry sets `_announceFix` | killed: T81-6 |
| m81c | press hand-off to "Change" | killed: T81-1 to T81-5 (10 tests) |
| m81d | guard hand-off removed | killed: T81-7 both keyboard paths |
| m81e | guard without the re-check | killed: T81-7 late failure answer |

**Test count.** CI: 937 at the baseline, then 959 on `afefae6` (22 new widget tests). The Chrome step stays 32.
