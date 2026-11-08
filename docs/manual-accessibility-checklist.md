# Manual accessibility and physical-device checklist

**Status:** prepared 2026-11-08 (owner approval), nothing run yet. Baseline: `main` at `901007f` (D1 and D2 merged);
row C2 needs a build from `1ff243e` or later (PR #121).
Every row starts as **Not run**. Record each as **Pass**, **Fail**, **Blocked** or **Not run**, with a note. A result
counts only when a person did the check on the device; never copy a result from the automated tests (the widget and
integration tests, or a `uiautomator` tree), which cannot hear what TalkBack says.

## 0. Setup

| ID | Step | Result | Notes |
|---|---|---|---|
| S1 | Build the synthetic APK from the baseline: `flutter build apk --debug -t integration_test/demo/synthetic_demo_app.dart` (the entry point comes with the synthetic demo APK PR; how-to in `docs/testing.md`). Record the commit and the APK's SHA-256 | Not run | |
| S2 | Record the device: model, Android version, TalkBack version, display size, font size, dark theme on/off, "Remove animations" on/off | Not run | |
| S3 | Turn on airplane mode (Wi-Fi off too) so no request can leave the device. Install the APK (`adb install -r …`); it replaces the real app (same package id) | Not run | |
| S4 | Open the app, then About: the version reads **9.8.7 (42)**, so this is the synthetic build. The origin reads "From: Current location"; the Conditions show "Bishan area" | Not run | |

Synthetic places to search: **Bay Mall** (main journey: Bus F20 suggested, F10 and F30 too), **City Tower**, **East
Hub** (use as a manual origin), **North MRT** (two results; walk-only). Links never open a browser in this build: an
activated link shows "Couldn't open <host>.", which confirms it was activated.

## A. TalkBack reading order (home screen)

Swipe right through the home screen from the top with TalkBack on.

| ID | Check | Expected | Result | Notes |
|---|---|---|---|---|
| A1 | Order from the top | App title → "About Singapore Smart Commute" → "Colour theme: Teal" → "From: Current location" → "Change origin" → "Where are you heading to today?" → destination field → "Conditions" → "Refresh conditions" → the four condition tiles | Not run | |
| A2 | Footer order | NEA notice → its link → MRT notice → its link → arrivals notice → its link → "Place search: OneMap © Singapore Land Authority" → "Bus data: busrouter.sg (data © LTA)" | Not run | |
| A3 | Nothing read early or twice | The two credits in A2 are **not** heard before "Conditions" (D2), and no item is read twice or merged with its neighbour | Not run | |
| A4 | Condition tiles | Each tile is read as one item: title, value, band, area, time | Not run | |

## B. Keyboard focus (hardware keyboard: Bluetooth or USB)

| ID | Check | Expected | Result | Notes |
|---|---|---|---|---|
| B1 | Tab from the top | A visible 2 px ring on each control; order as in A1, without the static texts | Not run | |
| B2 | Change → destination, page at the top | Focus on "Change", Tab → the destination field | Not run | |
| B3 | Change → destination, page scrolled (D1) | Scroll until "Change" sits just under the app bar, beside About and the palette button. Focus "Change", Tab → the destination field, **not** About; Shift+Tab → back to "Change" | Not run | |
| B4 | #80 flow | "Change" → search "East Hub" → pick it → "Use my current location" → focus lands on "Change"; Tab → the destination field | Not run | |
| B5 | Shift+Tab | Order reverses with no skipped control | Not run | |
| B6 | Touch after keyboard | After a tap, the ring disappears (touch mode) | Not run | |

## C. Credits

| ID | Check | Expected | Result | Notes |
|---|---|---|---|---|
| C1 | Footer credits | Each read on its own, last on the page (A2) | Not run | |
| C2 | Search-results credit (build from `1ff243e` or later, PR #121) | With results shown, "Place search: OneMap © Singapore Land Authority" is its own item, heard right **after** the last result, not merged into the route card's item with "From: …". On a build from before `1ff243e` it may be heard before the results: record which build you used | Not run | |
| C3 | Map credit | With the map open: "OneMap" and "Singapore Land Authority" are read as links, with the text between them | Not run | |

## D. Licence notices and links

| ID | Check | Expected | Result | Notes |
|---|---|---|---|---|
| D1 | NEA notice | The notice is read, then its own link "Singapore Open Data Licence version 1.0", announced as a link | Not run | |
| D2 | MRT notice | As D1 | Not run | |
| D3 | Arrivals notice | As D1 | Not run | |
| D4 | Activate each link (TalkBack double tap, and Enter on the keyboard) | "Couldn't open data.gov.sg." appears; focus stays near the link | Not run | |
| D5 | Map credit links | "Couldn't open www.onemap.gov.sg." / "Couldn't open www.sla.gov.sg." | Not run | |

## E. Journey and map

| ID | Check | Expected | Result | Notes |
|---|---|---|---|---|
| E1 | Search "Bay Mall" | Results announced; the result reads "BAY MALL (fake)" with its address | Not run | |
| E2 | Pick the result | The journey card: "Suggested", Bus F20, arrival times, "Estimated trip, about 35 minutes, not including waiting" | Not run | |
| E3 | "Select Bus F10" | F10 becomes selected; focus moves to its "Bus F10 selected" mark (the button's replacement), not to the top of the page | Not run | |
| E4 | "Show steps" | Steps open and are read in order | Not run | |
| E5 | "Refresh arrivals" | Times update or say they were checked; focus stays | Not run | |
| E6 | "Show map" | The map opens; focus moves to "Hide map"; the map's description names the journey | Not run | |
| E7 | "Hide map" | The map closes; focus goes to "Show map" | Not run | |
| E8 | Pan and zoom the map (touch; with TalkBack, the map's own gestures if any) | Synthetic street grid; ride line and markers stay in place | Not run | |

## F. Palette, About and focus restoration

| ID | Check | Expected | Result | Notes |
|---|---|---|---|---|
| F1 | Palette menu | Five radio items (Teal, Blue, Rose, Purple, Orange); the selected one announced as selected | Not run | |
| F2 | Pick Rose | The app recolours; the menu closes; focus returns to the palette button | Not run | |
| F3 | About | A dialog with the app name and version 9.8.7 (42); closing it returns focus to the About button | Not run | |
| F4 | Back button / Escape | Closes the menu or dialog; focus restored as in F2 and F3 | Not run | |

## G. Large text, dark mode, reduced motion

| ID | Check | Expected | Result | Notes |
|---|---|---|---|---|
| G1 | Largest font size (and display size, if offered) | No clipped or overlapping text; the footer and credits wrap and stay readable; buttons still reachable | Not run | |
| G2 | Dark theme | Dark colours everywhere; the map uses the dark synthetic tiles; text and links readable | Not run | |
| G3 | "Remove animations" on | Card size changes are instant; a map double-tap zooms at once, with no animation | Not run | |
| G4 | "Remove animations" off | Card size changes animate briefly; double-tap zoom animates | Not run | |

## H. Physical-device performance and behaviour

Needs a phone (see the requirements below). Airplane mode stays on; nothing is requested from any provider.

| ID | Check | Expected | Result | Notes |
|---|---|---|---|---|
| H1 | Cold start of the synthetic APK | Time to the home screen (stopwatch or `adb shell am start -W`) | Not run | |
| H2 | Journey planning | Search, pick, select options: no visible stutter; note any | Not run | |
| H3 | Map open, pan, pinch zoom, double-tap zoom | Smooth or note stutter; no "Map tiles are unavailable" | Not run | |
| H4 | Frame timings | `flutter drive --profile --keep-app-running -d <phone> --driver=test_driver/integration_test.dart --target=tool/map_performance_probe.dart` (synthetic tiles, no request). Record raster and build p95 and the share of frames over budget, light and dark. These are findings, not a pass mark | Not run | |
| H5 | TalkBack and keyboard on the phone | Sections A–F repeated on the phone where supported | Not run | |

## Physical-device requirements

- An Android phone with Android 7.0 (API 24) or later; record the model and version.
- To install the APK and run H4: USB debugging on (Developer options; the owner's decision, as it changes a phone
  setting), a USB cable, and this PC's `adb` and Flutter SDK. Without USB debugging, the APK can be copied and installed
  by hand ("install unknown apps" for the file manager, also a phone setting), and H4 cannot run.
- TalkBack: built into most Android phones (Android Accessibility Suite). If it is missing, installing it is new
  software and needs the owner's approval.
- A hardware keyboard (Bluetooth or USB OTG) for section B; without one, record B as Blocked.
- Airplane mode on for the whole session (Wi-Fi off), so no request can reach OneMap, busrouter, ArriveLah, data.gov.sg
  or any other provider. The synthetic build makes none anyway.
- Afterwards: uninstall the synthetic build, or install the real app over it, and restore any setting changed.

## Recording

Fill in the Result and Notes columns, then add one row to the run log in `docs/testing.md` with the date, device,
build commit and APK SHA-256, and the counts of Pass, Fail, Blocked and Not run. A Fail is reported to the owner with
the steps; no fix without approval.
