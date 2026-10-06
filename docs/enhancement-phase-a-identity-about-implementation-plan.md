# Enhancement Phase A (E3 App Icon Consistency, E4 About): Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task by task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** A0 discovery approved on 2026-10-06, with decisions A-Q1–A-Q6 frozen (§1). This document arrives in a
docs-only plan PR (A-Q6), and implementation starts only after that PR is merged. Three owner inputs must also be
settled before A1 starts (§1.3).

The discovery ran read-only against `main` @ `53acc19765c4a1b318ea6c28c75dc5a99b9993e9`.

E3 and E4 are **post-submission enhancements**, like E1. E2 and E5 are out of scope.

**Goal:**
- The phone launcher, Android splash, Web favicon and PWA icons show the same bus, skyline and pin artwork as the app
  bar, and Android and Web show the human name "Singapore Smart Commute".
- An app-bar About action opens a small dialog: the app name, a short description, "Author: Jaycee Wee", the version
  and build compiled in from the pubspec, "View licenses" and "Close".

**Architecture:**
- **E3 is resource-only:**
  - platform icons regenerated once from one canonical master with `flutter_launcher_icons` 0.14.4, run as a
    version-pinned global tool from a committed config, so `pubspec` is untouched;
  - plus label edits in `AndroidManifest.xml`, `web/index.html` and `web/manifest.json`.
- **E4 lives in the app shell (`lib/app/`)**, which already owns the app's identity (`SmartCommuteApp.title`,
  `AppTitle`, `AppLogo`):
  - `app_info.dart`: the `AppInfo` value, the pure `appInfoFrom`, and `appInfoProvider`, which reads Flutter's built-in
    `appBuildName`/`appBuildNumber`;
  - `about_dialog.dart`: `AboutButton` and `AboutAppDialog`.
- No feature module changes.

**Tech Stack:** Flutter 3.47.2 (Dart 3.13.2; framework commit `d3b14c87690`), Material 3, Riverpod 3,
`flutter_test`, `integration_test`. No new dependency. `flutter_launcher_icons` 0.14.4 is a dev-time global tool,
not in `pubspec`.

**Spec:**
- `docs/enhancement_phase_a_identity_about.md` (owner-provided guide; source material, not modified by this work);
- the owner's A0 approval and rulings of 2026-10-06 (§1);
- project rules in `CLAUDE.md`.

---

## 1. Decisions

### 1.1 Frozen from the guide (A-D1–A-D7)

| ID | Decision |
|---|---|
| A-D1 | About is a dedicated app-bar info action |
| A-D2 | The logo and title stay decorative identity; they are never the About trigger |
| A-D3 | Author is exactly `Jaycee Wee` |
| A-D4 | Version and build come automatically from the app's metadata |
| A-D5 | **No build date** in this phase |
| A-D6 | E1 stays intact: five palettes, Teal default, `ThemeMode.system`, 500 ms bounded read, persistence, selector, keyboard, reduce motion, map-state contract |
| A-D7 | No E2 or E5 research or implementation, no planner change, no journey-time UI, no transfer routing |

### 1.2 Owner rulings on A0 (A-Q1–A-Q6, 2026-10-06)

- **A-Q1 — Tests run in CI while Windows Smart App Control blocks `flutter_tester.exe` locally.**
  - Smart App Control is **not** disabled, and `VerifiedAndReputablePolicyState` is not touched.
  - `flutter test` evidence for RED, GREEN, the full suite and mutations comes from CI (§3).
  - A test is never reported as passing locally when it could not run.
  - Local format, analyze, builds, integration and live checks stay valid wherever the policy does not block them.
  - **There is no CI today** (§2.6), so adding it is a prerequisite that needs approval (§1.3, task A-CI).
- **A-Q2 — Version source: Flutter's built-in `appBuildName`/`appBuildNumber`.**
  - **No `package_info_plus`**, no dependency, no `pubspec.lock` change, no plugin, no async call, no Web
    `version.json` request, and no CSP change.
  - The seam is `AppInfo`, `appInfoFrom(...)` and an injectable `appInfoProvider`. Tests use the fake `9.8.7 (42)`.
  - A build with no metadata shows `Version unavailable`.
- **A-Q3 — A small custom `AlertDialog`, not `showAboutDialog`.**
  - It keeps **View licenses** and **Close**, with no separate About route or screen.
  - Content order:
    1. decorative app icon;
    2. `Singapore Smart Commute`;
    3. the description;
    4. `Author: Jaycee Wee`;
    5. `Version <version> (<build>)` or `Version unavailable`;
    6. `View licenses`;
    7. `Close`.
  - The button's accessible name is `About Singapore Smart Commute`.
- **A-Q4 — Visible names: `Singapore Smart Commute` everywhere a person sees the app's name.**
  - Places:
    - Android `android:label`;
    - Web `<title>` and `apple-mobile-web-app-title`;
    - manifest `name` and `short_name`.
  - The application ID, package, namespace and directories are unchanged.
  - Platform truncation of the launcher label is acceptable.
  - No invented abbreviation.
  - The Web App Manifest standard sets no length limit on `short_name`. Lighthouse only *advises* about 12 characters
    against truncation, so the full name stays.
- **A-Q5 — The canonical artwork is the existing bus, skyline and pin design. No redesign.**
  - A 192 px upscale is not a high-resolution master.
  - A high-resolution source (the 1254 px original, or a clean source of at least 1024 px) is requested from the owner
    before A1 (§1.3, O2).
  - The 192 px fallback needs the owner's explicit approval.
  - **Web manifest colours stay as they are** unless a colour decision is approved (§1.3, O4).
- **A-Q6 — A docs-only plan PR first** (this document plus one `docs/testing.md` planning row). Implementation starts
  only after it is merged.

### 1.3 Owner inputs still needed before A1

These were raised in the plan PR report.

| ID | Input | Default if unanswered |
|---|---|---|
| O1 | **Approve task A-CI:** add `.github/workflows/flutter-test.yml` (§3.2) in its own small PR before A1 | **A1 does not start.** There is no other approved test path |
| O2 | **Supply the high-resolution artwork** (the 1254 px original, or at least 1024 px), or explicitly approve the 192 px fallback | **A1 does not start** |
| O3 | **Adaptive-icon background colour** (§4.3). It is visible only where the master has transparent pixels inside the launcher mask. Proposed: white `#FFFFFF` | Report before choosing |
| O4 | **Web manifest `background_color`/`theme_color` `#0175C2`.** A0 identified this as Flutter's project-template blue, a template leftover rather than an app colour. Per A-Q5 it stays unchanged unless you decide otherwise | Kept as `#0175C2`, and §5.6 pins it |

## 2. A0 findings (`main` @ `53acc19`)

### 2.1 Why the launcher and the app bar look different

The platform icons were never replaced: they are Flutter's project-template icon, the Flutter logo. This was
verified visually and by PNG header.

- **Android:** `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` are the template,
  as 48/72/96/144/192 px palette PNGs of 442/544/721/1,031/1,443 B.
  - `AndroidManifest.xml` has `android:icon="@mipmap/ic_launcher"`.
  - There is **no adaptive icon** (`mipmap-anydpi-v26/`).
- **Web:** `web/icons/Icon-192.png` (5,292 B), `Icon-512.png` (8,252 B), `Icon-maskable-192.png` (5,594 B),
  `Icon-maskable-512.png` (20,998 B) and `web/favicon.png` (16 px, 917 B) are the template.
- **The app art exists only in `assets/app_icon.png`:** 192×192 RGBA, 60,839 B, a rounded tile with transparent
  superellipse corners. Only `AppLogo` uses it.
  - Commit 942283c cropped it from a **1254 px original that was never committed**.
  - A disk search found no copy: Downloads, Desktop, Pictures, Documents, OneDrive, `C:\MyCode` and the Claude temp
    folders, for 1000–1600 px PNGs.
- **Android 12+ launch splash:** it shows the launcher icon, so today the app opens on the Flutter logo too.

### 2.2 Visible names

- **Android:** `android:label="sg_smart_commute"`, and the activity sets no label of its own.
  - `aapt2 dump badging` on the E1 release APK prints `application-label:'sg_smart_commute'`.
  - That label appears in the launcher, App info and the **location-permission prompt**.
  - The Recents card uses `MaterialApp.title` ("Singapore Smart Commute"); to confirm live in A6.
- **Web:**
  - `<title>sg_smart_commute</title>`, shown until Flutter sets the title;
  - `<meta name="apple-mobile-web-app-title" content="sg_smart_commute">`;
  - `manifest.json` `name`/`short_name` `sg_smart_commute`.

### 2.3 Version source

- Flutter 3.47.2 exports `const String? appBuildName` and `appBuildNumber` from `package:flutter/services.dart`
  (`packages/flutter/lib/src/services/app_version.dart`; commit 874101206d8, flutter#187935).
- The tool defines them from pubspec `version` (or `--build-name`/`--build-number`) in `getBuildInfo()`
  (`flutter_tools/lib/src/runner/flutter_command.dart:1507-1508`). `build apk`, `build web`, `run`, `drive` and `test`
  all call it.
- They are the same values the tool writes into Android `versionName`/`versionCode` (`aapt2`: `versionName='1.0.0'
  versionCode='1'`) and into Web `version.json`.
- A scratch Web build with `version: 1.2.3+45` compiled the literal `1.2.3|45` into `main.dart.js`.
- `flutter test` has no `--build-name` option, so under test they always carry the pubspec version.
- A build made outside the flutter tool would leave them `null`, and About then shows `Version unavailable`.

### 2.4 `showAboutDialog` vs a custom dialog

Evidence from `packages/flutter/lib/src/material/about.dart:414-470`:
- `AboutDialog` hard-codes a header row of `[icon] [name, version, gap, legalese]` followed by `children`. The version
  therefore reads before the description, and omitting it leaves empty `Text('')` lines.
- The icon sits *beside* the name. At 360 dp with 2× text that leaves about 136 px for a 48 px `headlineSmall` name,
  so "Singapore" would break mid-word (estimated).

A Material 3 `AlertDialog(icon:, title:, content:, actions:, scrollable: true)` has these properties
(`dialog.dart:901-923`):
- it puts the icon above the title, so the name has the full width;
- it scrolls the icon, title and content;
- it keeps the actions pinned below.

### 2.5 `package_info_plus` (investigated, not used)

- 10.2.1 is already in the lock, transitive via `geolocator` → `geolocator_linux`, and is registered on Android and
  Web. 10.2.2 is the latest.
- It is not used (A-Q2).
- Its Web side would `GET version.json?cachebuster=…`.
- Notes: the session scratchpad `phase-a/pkg/package-info-plus.md`, not committed.

### 2.6 Baseline gates and CI

- `dart format --set-exit-if-changed .`: 146 files, 0 changed.
- `flutter analyze`: no issues.
- `flutter test`: **blocked locally.**
  - All 49 test files fail to load with "An Application Control policy has blocked this file".
  - Windows Smart App Control is enforcing (`VerifiedAndReputablePolicyState = 1`). The CodeIntegrity events
    3033/3077 show `dartvm.exe` refused `…\engine\windows-x64\flutter_tester.exe`, a binary unchanged since
    2026-08-31.
  - E1's last full run was 698/698.
- **No CI exists:**
  - `main` has no `.github/workflows/`;
  - `gh workflow list` and `gh run list` are empty;
  - the only workflow files in the repo, on the remote branch `add-claude-github-actions-1790850250380`, are Claude
    review bots, not a test runner.
- The repository is public, so GitHub-hosted Actions minutes are free.

## 3. Test execution strategy (A-Q1)

### 3.1 What runs where

| Evidence | Where |
|---|---|
| `flutter test` (RED, GREEN, full suite, mutations) | **CI** (GitHub Actions, ubuntu, Flutter 3.47.2), after A-CI is approved and merged |
| `dart format`, `flutter analyze` | Local (works under the policy) and CI |
| `flutter build web --release`, `flutter build apk --debug/--release` | Local. If a build tool is blocked too, record the exact message and Not run |
| Android integration (`flutter test integration_test -d emulator-5558`), Web `flutter drive` (profile, web-server) | Local. These run on the device or Chrome, not `flutter_tester`; to confirm in A5. If blocked, record Not run with the message |
| Live checks | Local emulator and real Chrome |

### 3.2 Task A-CI (prerequisite; needs approval O1; its own PR `ci/flutter-test`, merged before A1)

**Files:** create `.github/workflows/flutter-test.yml`.

```yaml
# Runs the Dart/Flutter gates on every non-main push and on demand.
# Exists because Windows Smart App Control blocks flutter_tester.exe on the
# development PC (docs/testing.md); Flutter is pinned to the project's SDK.
name: flutter-test
on:
  push:
    branches-ignore: [main]
  workflow_dispatch:
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - name: Flutter 3.47.2 (tag commit d3b14c87690)
        run: |
          git clone --depth 1 --branch 3.47.2 https://github.com/flutter/flutter.git "$RUNNER_TEMP/flutter"
          echo "$RUNNER_TEMP/flutter/bin" >> "$GITHUB_PATH"
      - run: flutter --version
      - run: flutter pub get
      - run: dart format --set-exit-if-changed .
      - run: flutter analyze
      - run: flutter test --reporter expanded
```

- No third-party action is used. Flutter comes from its own tag, and `actions/checkout` is pinned to a commit.
- `contents: read` only, with no secrets.
- [ ] **Step 1:** Branch `ci/flutter-test` from `main`, add the file, and push.
- [ ] **Step 2:** Record the first run: URL, duration, and `N/N` passed. That run is the CI baseline; expect 698 tests,
  the same suite as E1's 698/698. If any test fails only on Linux, stop and report. Do not edit tests to make CI
  green without a ruling.
- [ ] **Step 3:** Add a `docs/testing.md` row (CI baseline) and a `CLAUDE.md` line under Commands, saying
  "`flutter test` runs in CI (`flutter-test` workflow) while Smart App Control blocks `flutter_tester.exe`
  locally".
- [ ] **Step 4:** Open the PR. Do not merge without the owner.

### 3.3 RED/GREEN and mutations through CI (every test-first task)

1. Commit only the new or changed tests as `test(...): … (RED)`. Push the branch.
2. Record the CI run URL and the failing test names (`gh run view <id> --log-failed`). These must be the intended
   failures, for the intended reason.
3. Commit the implementation and push. Record the GREEN run: URL and `N/N`.
4. **Mutations:** for each mutation in the task:
   - from the task's GREEN head, `git switch -c mut/<task>-<id>`;
   - apply the one mutation, commit it, push it;
   - record the run URL and the tests that failed;
   - then `git push origin --delete mut/<task>-<id>` and `git branch -D mut/<task>-<id>`.

   The feature branch never carries a mutation.
5. Log each command and its real result in `docs/testing.md`. Anything that did not run is **Not run**, with the
   reason.

## 4. E3 design: one master, regenerated platform icons, human labels

### 4.1 Canonical master (O2)

- **If the owner supplies the original:**
  - Commit `tool/icon/app_icon_master.png`: the artwork's square tile at 1024×1024 px. It is outside `assets/` and
    not listed in `pubspec.yaml`, so it never ships in the APK or Web bundle.
  - The crop is a one-time edit, recorded in `docs/assumptions.md`: the tile's square, full-bleed inside its rounded
    corners, the same framing as `assets/app_icon.png`.
  - Full-bleed means the adaptive and maskable layers have no transparent corners, so O3 becomes invisible.
- **If the owner approves the fallback:** the master is `assets/app_icon.png` itself, 192 px. Outputs above 192 px are
  upscaled: the adaptive foreground up to 432 px and the Web icons up to 512 px. Record that as a known limitation.
- `assets/app_icon.png` (the in-app 192 px rounded tile) is **kept as it is**. It is already the canonical art at its
  size. Regenerating it would risk pixel changes with no user value (no redesign).

### 4.2 Generator: `flutter_launcher_icons` 0.14.4 as a pinned global tool

- 0.14.4 was published 2025-06-10. It is pure Dart (`args`, `checked_yaml`, `cli_util`, `image`,
  `json_annotation`, `path`, `yaml`) with SDK `>=3.0.0 <4.0.0`.
- It is not added to `pubspec.yaml`, so the lock is unchanged.

`tool/icon/flutter_launcher_icons.yaml`:

```yaml
# Regenerate the Android and Web app icons from the one canonical master
# (Phase A, E3). From the repository root:
#   dart pub global activate flutter_launcher_icons 0.14.4
#   dart pub global run flutter_launcher_icons -f tool/icon/flutter_launcher_icons.yaml
# Then keep web/manifest.json's formatting (see docs/testing.md, E3).
flutter_launcher_icons:
  image_path: "tool/icon/app_icon_master.png"    # fallback (O2): "assets/app_icon.png"
  android: true
  min_sdk_android: 24
  adaptive_icon_foreground: "tool/icon/app_icon_master.png"
  adaptive_icon_foreground_inset: 16
  adaptive_icon_background: "#FFFFFF"           # O3
  ios: false
  web:
    generate: true
    image_path: "tool/icon/app_icon_master.png"
  windows:
    generate: false
  macos:
    generate: false
```

What it writes, verified from the 0.14.4 source (`lib/android.dart`, `lib/constants.dart`,
`lib/web/web_icon_generator.dart`):

- **Android legacy icons:** `mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` at 48/72/96/144/192 px.
- **Android adaptive icon:**
  - `mipmap-anydpi-v26/ic_launcher.xml`, with `<background android:drawable="@color/ic_launcher_background"/>` and a
    foreground `<inset android:drawable="@drawable/ic_launcher_foreground" android:inset="16%"/>`;
  - `drawable-{mdpi..xxxhdpi}/ic_launcher_foreground.png` at 108/162/216/324/432 px;
  - `values/colors.xml`, with `ic_launcher_background`.
- **AndroidManifest:** it only rewrites the `android:icon` line to `@mipmap/ic_launcher`, the same value, so there is
  no expected diff.
- **Web:** `web/icons/Icon-192.png`, `Icon-512.png`, `Icon-maskable-192.png`, `Icon-maskable-512.png` and
  `web/favicon.png`.
  - It re-encodes `manifest.json`, changing colours only if they are configured (they are not).
  - The four icon entries already match.
  - So **restore the file's original formatting and edit only `name`/`short_name`** (§4.4).
- **`index.html`:** untouched by the generator.

Inset 16 % makes the foreground cover about 68 % of the 108 dp layer, so the art fills the 72 dp visible viewport.
Launcher masks (circle or squircle) crop the tile's corners. The bus and pin lie inside the central circle (checked
on the 192 px art). The final inset is confirmed by eye on emulator-5558 (A6).

A themed (monochrome) Android 13+ icon is **not** added: it would need a new one-colour drawing, which is a redesign.

### 4.3 Adaptive background (O3)

The colour is visible only where the master has transparent pixels inside the mask:
- none with a full-bleed master;
- small corner slivers with the 192 px rounded-tile fallback.

The proposal is `#FFFFFF`. It is not changed without the owner's answer.

### 4.4 Labels (A-Q4)

- `android/app/src/main/AndroidManifest.xml`: `android:label="sg_smart_commute"` becomes
  `android:label="Singapore Smart Commute"`. No other line changes.
- `web/index.html`:
  - `<title>sg_smart_commute</title>` becomes `<title>Singapore Smart Commute</title>`;
  - `<meta name="apple-mobile-web-app-title" content="sg_smart_commute">` becomes
    `content="Singapore Smart Commute"`.
  - The CSP line is untouched.
- `web/manifest.json`: `"name"` and `"short_name"` become `"Singapore Smart Commute"`.
  - `background_color`/`theme_color` stay `#0175C2` (O4).
  - The `icons` array is unchanged (same four files).

## 5. E4 design: version seam and About dialog

### 5.1 Version seam (A-Q2): `lib/app/app_info.dart`

```dart
import 'package:flutter/services.dart' show appBuildName, appBuildNumber;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The app's version and build (E4), as the flutter tool compiled them in from
/// pubspec `version: <version>+<build>`.
class AppInfo {
  const AppInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  /// "Version 1.0.0 (1)"; "Version 1.0.0" when the build has no number.
  String get label => buildNumber.isEmpty
      ? 'Version $version'
      : 'Version $version ($buildNumber)';
}

/// [name] and [number] as compiled in; null when the build carried no version,
/// so About says "Version unavailable".
AppInfo? appInfoFrom(String? name, String? number) =>
    name == null || name.isEmpty
    ? null
    : AppInfo(version: name, buildNumber: number ?? '');

/// The version the flutter tool compiled in (Flutter 3.47+ `appBuildName` /
/// `appBuildNumber`): no plugin, no I/O, no request. Tests override it.
final appInfoProvider = Provider<AppInfo?>(
  (ref) => appInfoFrom(appBuildName, appBuildNumber),
);
```

### 5.2 About UI (A-Q3): `lib/app/about_dialog.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'app_info.dart';
import 'app_logo.dart';

/// The app-bar About action (E4). An info icon named for the app; the logo
/// and title beside it stay decorative.
class AboutButton extends StatelessWidget {
  const AboutButton({super.key});

  static const String tooltip = 'About ${SmartCommuteApp.title}';

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('about-button'),
    tooltip: tooltip,
    icon: const Icon(Icons.info_outline),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => const AboutAppDialog(),
    ),
  );
}

/// Name, description, author and the compiled-in version, then "View
/// licenses" and "Close". A small AlertDialog rather than showAboutDialog,
/// whose fixed header reads the version before the description and squeezes
/// the name beside the icon (Phase A plan §2.4).
class AboutAppDialog extends ConsumerWidget {
  const AboutAppDialog({super.key});

  static const String description =
      'Singapore Smart Commute is a front-end-only commute helper for '
      'Singapore. It combines current conditions, bus journey suggestions, '
      'live bus arrivals, MRT alternatives, and an optional journey map.';
  static const String author = 'Author: Jaycee Wee';
  static const String versionUnavailable = 'Version unavailable';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(appInfoProvider);
    return AlertDialog(
      icon: const AppLogo(size: 48),
      title: const Text(SmartCommuteApp.title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(description),
          const SizedBox(height: 12),
          const Text(author),
          const SizedBox(height: 4),
          Text(info?.label ?? versionUnavailable),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => showLicensePage(
            context: context,
            applicationName: SmartCommuteApp.title,
            applicationVersion: info?.label,
            applicationIcon: const AppLogo(size: 48),
          ),
          child: const Text('View licenses'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
```

- `AppLogo` is already `ExcludeSemantics`, so the icon adds nothing for screen readers.
- The reading order is title, description, author, version, then the actions, in tree order.
- Colours come only from the theme (`AlertDialog` defaults), so the colour guard stays green, and the dialog follows
  every palette and brightness.
- `showDialog` gives the modal route, focus trap, barrier, Escape (`DismissIntent`), Android Back, and focus returning
  to the button.
- **View licenses** opens Flutter's standard `LicensePage`. On Web that page reads the app's own bundled `NOTICES`
  asset, same-origin and only when tapped. Opening About itself makes no request.

### 5.3 App bar

In `lib/app/home_screen.dart`, `actions: const [PaletteMenuButton()]` becomes
`actions: const [AboutButton(), PaletteMenuButton()]`. The order is About, then Colour theme (A-Q3).

### 5.4 Test harness

In `integration_test/fakes/test_app.dart`:
- add the parameter `AppInfo? appInfo = fakeAppInfo` and the override `appInfoProvider.overrideWithValue(appInfo)`;
- add `const fakeAppInfo = AppInfo(version: '9.8.7', buildNumber: '42');`. It deliberately differs from pubspec, so
  hard-coding `1.0.0 (1)` fails.
- Passing `appInfo: null` simulates a build with no version.

### 5.5 One E1 test changes (Tab order)

`test/features/appearance/palette_menu_button_test.dart` (keyboard test, `:179-180`) expects the palette button to be
**the first Tab stop**. With About placed before it (A-Q3), that becomes the second Tab stop.

Ruling: amend only that step to Tab twice. The new comment reads: "the second Tab stop, after About". E1's behaviour
is unchanged; only the page's Tab order gains one stop.

### 5.6 Build date

None (A-D5). No `DateTime.now()`, install or file time, and no `--dart-define`. The future option is
`--dart-define=BUILD_DATE_UTC=…` read with `String.fromEnvironment`, which is truthful only if every documented build
passes it. It is not planned.

## 6. Files

| Task | Create | Modify |
|---|---|---|
| A-CI | `.github/workflows/flutter-test.yml` | `docs/testing.md`, `CLAUDE.md` |
| A1 | `test/app/app_identity_test.dart`, `tool/icon/flutter_launcher_icons.yaml`, `tool/icon/app_icon_master.png` (O2), `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`, `res/drawable-{mdpi..xxxhdpi}/ic_launcher_foreground.png`, `res/values/colors.xml` | `res/mipmap-*/ic_launcher.png` (5), `AndroidManifest.xml` (label), `web/icons/*.png` (4), `web/favicon.png`, `web/manifest.json` (names), `web/index.html` (two titles) |
| A2 | `lib/app/app_info.dart`, `test/app/app_info_test.dart` | `integration_test/fakes/test_app.dart` |
| A3 | `lib/app/about_dialog.dart`, `test/app/about_dialog_test.dart` | `lib/app/home_screen.dart`, `test/features/appearance/palette_menu_button_test.dart` (Tab step), `integration_test/app_boot_test.dart` |
| A4 | — | `README.md`, `CLAUDE.md`, `docs/architecture.md`, `docs/assumptions.md`, `docs/testing.md` |

Not touched:
- `pubspec.yaml`, `pubspec.lock`;
- `lib/features/**`, including `appearance/`;
- `lib/main.dart`, `lib/app/app.dart`, `lib/app/app_logo.dart`, `assets/app_icon.png`;
- the CSP;
- `docs/enhancement_phase_*.md` (owner guides).

## Global Constraints

- Front-end only. No backend, proxy, serverless, secret or new provider host, and no CSP change (`CLAUDE.md`).
- **No new dependency.** `pubspec.yaml` and `pubspec.lock` are unchanged. `flutter_launcher_icons` 0.14.4 is a global
  dev tool only.
- Version text comes only from `appInfoProvider` (built-in `appBuildName`/`appBuildNumber`).
  - The fake is `9.8.7 (42)`.
  - Unavailable shows `Version unavailable`.
  - No build date.
- Exact copy (A-Q3):
  - title `Singapore Smart Commute`;
  - description `Singapore Smart Commute is a front-end-only commute helper for Singapore. It combines current conditions, bus journey suggestions, live bus arrivals, MRT alternatives, and an optional journey map.`;
  - `Author: Jaycee Wee`;
  - buttons `View licenses` and `Close`;
  - button tooltip `About Singapore Smart Commute`.
- App-bar order: `[logo] title … [About] [Colour theme]`. The logo and title are not clickable.
- Visible names: `Singapore Smart Commute` (Android label; Web title, Apple title, manifest `name` and `short_name`).
  The application ID `sg.smartcommute.sg_smart_commute`, the Dart package `sg_smart_commute` and the namespace are
  unchanged.
- Colours only from `Theme.of(context).colorScheme`. The five palette seeds remain the only fixed colours in `lib/`
  (`test/app/app_theme_test.dart`). The Web manifest colours stay `#0175C2` unless O4 decides otherwise.
- E1 stays intact (A-D6). The only E1 test edit is the Tab step (§5.5).
- `flutter test` evidence comes only from CI (§3). Never claim a local pass. Record Not run with reasons.
- Commits go on `feat/enhancement-phase-a`, never `main`. A docs-only plan PR comes first. The implementation PR is
  not merged without the owner.

## Review Focus

The ways this could fail for a real person that no unit test exercises, most likely first. Each one is pinned by the
named live check.

1. **The launcher mask crops the art badly**, for example the bus front or the pin cut off by Pixel's circle. Expect
   the whole bus and pin to stay recognisable. Pinned by A6 Android step 1, which compares the launcher and the app
   bar side by side.
2. **The real version differs from what tests use.** Tests fake `9.8.7 (42)`. On a device, About must show
   `Version 1.0.0 (1)`, matching `aapt2` `versionName`/`versionCode`, and Web must match `build/web/version.json`.
   Pinned by A6 Android step 4 and Web step 3.
3. **Maskable Web icon on install** shows transparent or black corners (fallback master). Expect a clean full-bleed
   icon. Pinned by A6 Web step 1.
4. **The Android 12+ splash** still shows the Flutter logo, from a cached icon. Expect the new art after reinstall.
   Pinned by A6 Android step 2.
5. **The About button pushes the title off at 2× text on a real font** (the test font differs). Expect the title to
   ellipsize and both actions to stay 48 dp. Pinned by A6 Android step 6 and Web step 5.

---

## 7. Task sequence

**Prerequisites:** the plan PR is merged, O1 is approved and A-CI is merged with a green baseline, and O2 is
answered. Then branch `feat/enhancement-phase-a` from the latest `origin/main`.

### Task A1: E3 icon consistency and visible names

**Files:** listed in §6 (A1).

**Interfaces:**
- Consumes `SmartCommuteApp.title` and `AppLogo.asset`.
- Produces the generated platform resources and the labels.

- [ ] **Step 1: Write the failing identity test.** Create `test/app/app_identity_test.dart`:

```dart
// E3: the platform icons and visible names carry the app's identity, not
// Flutter's project template. Reads the platform files directly.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/app.dart';
import 'package:sg_smart_commute/app/app_logo.dart';

const res = 'android/app/src/main/res';

/// Width and height from a PNG's IHDR chunk.
({int width, int height}) png(String path) {
  final b = File(path).readAsBytesSync();
  expect(b.sublist(1, 4), 'PNG'.codeUnits, reason: path);
  int u32(int at) =>
      b[at] << 24 | b[at + 1] << 16 | b[at + 2] << 8 | b[at + 3];
  return (width: u32(16), height: u32(20));
}

/// Flutter's untouched project-template icons, by byte length (Phase A A0
/// audit of main @ 53acc19): a file this exact length here is the template.
const templateLengths = {
  '$res/mipmap-mdpi/ic_launcher.png': 442,
  '$res/mipmap-hdpi/ic_launcher.png': 544,
  '$res/mipmap-xhdpi/ic_launcher.png': 721,
  '$res/mipmap-xxhdpi/ic_launcher.png': 1031,
  '$res/mipmap-xxxhdpi/ic_launcher.png': 1443,
  'web/favicon.png': 917,
  'web/icons/Icon-192.png': 5292,
  'web/icons/Icon-512.png': 8252,
  'web/icons/Icon-maskable-192.png': 5594,
  'web/icons/Icon-maskable-512.png': 20998,
};

void notTemplate(String path) => expect(
  File(path).lengthSync(),
  isNot(templateLengths[path]),
  reason: '$path is still the Flutter template icon',
);

void main() {
  test('Android: the launcher uses the app icon and the human name', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:label="${SmartCommuteApp.title}"'));
    expect(manifest, contains('android:icon="@mipmap/ic_launcher"'));
    expect(manifest, isNot(contains('sg_smart_commute"')));
  });

  test('Android: legacy icons at every density, none the template', () {
    const sizes = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    sizes.forEach((density, px) {
      final path = '$res/mipmap-$density/ic_launcher.png';
      expect(png(path), (width: px, height: px), reason: path);
      notTemplate(path);
    });
  });

  test('Android 8+: an adaptive icon whose layers exist', () {
    final xml = File(
      '$res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsStringSync();
    expect(xml, contains('@drawable/ic_launcher_foreground'));
    expect(xml, contains('@color/ic_launcher_background'));
    expect(
      File('$res/values/colors.xml').readAsStringSync(),
      contains('name="ic_launcher_background"'),
    );
    const sizes = {
      'mdpi': 108,
      'hdpi': 162,
      'xhdpi': 216,
      'xxhdpi': 324,
      'xxxhdpi': 432,
    };
    sizes.forEach((density, px) {
      final path = '$res/drawable-$density/ic_launcher_foreground.png';
      expect(png(path), (width: px, height: px), reason: path);
    });
  });

  test('Web: names, icons at their stated sizes, colours unchanged', () {
    final manifest =
        jsonDecode(File('web/manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(manifest['name'], SmartCommuteApp.title);
    expect(manifest['short_name'], SmartCommuteApp.title);
    expect(
      (manifest['background_color'], manifest['theme_color']),
      ('#0175C2', '#0175C2'),
      reason: 'manifest colours change only by an owner decision (O4)',
    );
    final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();
    expect(icons, hasLength(4));
    for (final icon in icons) {
      final path = 'web/${icon['src']}';
      final px = int.parse((icon['sizes'] as String).split('x').first);
      expect(png(path), (width: px, height: px), reason: path);
      notTemplate(path);
    }
    notTemplate('web/favicon.png');
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains('<title>${SmartCommuteApp.title}</title>'));
    expect(
      html,
      contains(
        '<meta name="apple-mobile-web-app-title" '
        'content="${SmartCommuteApp.title}">',
      ),
    );
  });

  test('the in-app logo is still the canonical 192 px art asset', () {
    expect(AppLogo.asset, 'assets/app_icon.png');
    expect(png(AppLogo.asset), (width: 192, height: 192));
  });
}
```

  Before committing, check that `templateLengths` is right, so the test can't pass vacuously: on `main` every listed
  file has exactly that length (`wc -c`).
- [ ] **Step 2: RED through CI** (§3.3). Commit the test only, as `test(app): E3 identity checks (RED)`, and push.
  Expected failures, with each failure message naming the file:
  - the label;
  - the five legacy icons ("still the Flutter template icon");
  - the adaptive icon (missing file);
  - Web names, icons and titles.

  Expected passes: the in-app logo test, and the Web colours.
- [ ] **Step 3: Generate the icons.**
  - Add `tool/icon/flutter_launcher_icons.yaml` (§4.2), plus `tool/icon/app_icon_master.png` if O2 supplied it.
    For the fallback, set the three image paths to `assets/app_icon.png`.
  - Set the O3 colour.
  - Run, from the repository root:
    ```
    dart pub global activate flutter_launcher_icons 0.14.4
    dart pub global run flutter_launcher_icons -f tool/icon/flutter_launcher_icons.yaml
    ```
  - If the global run refuses because the package is not in `pubspec`, stop. Do not add it to `pubspec`; report and
    rule. The alternative is to run it in a `git archive` copy and copy the outputs back.
- [ ] **Step 4: Inspect the generated diff.**
  - Run `git status --porcelain` and `git diff --stat`.
  - Only the files in §6 (A1) may change. `AndroidManifest.xml` must show no generator change.
  - Restore `web/manifest.json` (`git checkout -- web/manifest.json`) if the generator re-encoded it.
  - View every generated PNG; each must be the bus, skyline and pin art, not blank or cropped.
- [ ] **Step 5: Set the names** (§4.4).
  - `AndroidManifest.xml`: change the `android:label` line only.
  - `web/index.html`: `<title>` and `apple-mobile-web-app-title`.
  - `web/manifest.json`: `name` and `short_name`, keeping the file's formatting.
- [ ] **Step 6: GREEN through CI** (§3.3). Commit as `feat(app): E3 launcher and Web icons from the app art; human
  app name`, push, and record N/N.
- [ ] **Step 7: Mutations through CI** (§3.3, M8–M9 in §8).

### Task A2: E4 version seam

**Files:** create `lib/app/app_info.dart` and `test/app/app_info_test.dart`; modify
`integration_test/fakes/test_app.dart`.

**Interfaces:**
- Produces `class AppInfo {String version; String buildNumber; String get label}`,
  `AppInfo? appInfoFrom(String? name, String? number)`, and `final appInfoProvider = Provider<AppInfo?>`.
- Also produces `const fakeAppInfo` and `buildTestApp(appInfo:)`.

- [ ] **Step 1: Write the failing tests.** Create `test/app/app_info_test.dart`:

```dart
// E4: the version and build come only from the build (Flutter's
// appBuildName / appBuildNumber), never from a literal in lib/.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/app_info.dart';

/// pubspec `version: <name>+<number>`.
({String name, String number}) pubspecVersion() {
  final m = RegExp(
    r'^version:\s*([^+\s]+)\+(\S+)\s*$',
    multiLine: true,
  ).firstMatch(File('pubspec.yaml').readAsStringSync())!;
  return (name: m[1]!, number: m[2]!);
}

void main() {
  test('label: version and build, or the version alone', () {
    expect(
      const AppInfo(version: '9.8.7', buildNumber: '42').label,
      'Version 9.8.7 (42)',
    );
    expect(
      const AppInfo(version: '9.8.7', buildNumber: '').label,
      'Version 9.8.7',
    );
  });

  test('appInfoFrom: no name means no version; a missing number is empty', () {
    expect(appInfoFrom(null, '42'), isNull);
    expect(appInfoFrom('', '42'), isNull);
    expect(appInfoFrom('9.8.7', null)?.label, 'Version 9.8.7');
    expect(appInfoFrom('9.8.7', '42')?.label, 'Version 9.8.7 (42)');
  });

  test('the real provider carries the pubspec version, compiled in by the '
      'flutter tool', () {
    final v = pubspecVersion();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(appInfoProvider)?.label,
      'Version ${v.name} (${v.number})',
    );
  });

  test('lib/ never spells out the version: it comes only from the build', () {
    final v = pubspecVersion();
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      expect(f.readAsStringSync(), isNot(contains(v.name)), reason: f.path);
    }
  });
}
```

  Check before committing: `grep -rn "1\.0\.0" lib` returns nothing on `main` (verified in A0).
- [ ] **Step 2: RED through CI.** Commit `test(app): E4 version seam (RED)` and push. Expected: a compile failure,
  because `app_info.dart` doesn't exist. Record it.
- [ ] **Step 3: Implement.**
  - Create `lib/app/app_info.dart` exactly as in §5.1.
  - In `integration_test/fakes/test_app.dart`, add `import 'package:sg_smart_commute/app/app_info.dart';`.
  - Add the parameter `AppInfo? appInfo = fakeAppInfo,` after `palette`.
  - Add the override `appInfoProvider.overrideWithValue(appInfo),` after `initialPaletteProvider…`.
  - Add the top-level declaration below:

```dart
/// A version no real build has, so a hard-coded "1.0.0 (1)" in the UI fails.
const fakeAppInfo = AppInfo(version: '9.8.7', buildNumber: '42');
```

  - Extend the doc comment on `buildTestApp`: "the version is the fake [fakeAppInfo] (`appInfo: null` = a build with
    no version)".
- [ ] **Step 4: GREEN through CI.** Commit `feat(app): E4 version from Flutter's compiled-in build name and number`,
  push, and record N/N.
- [ ] **Step 5: Mutations through CI:** M3, M4 and M5 (§8).

### Task A3: E4 About action and dialog

**Files:**
- Create `lib/app/about_dialog.dart` and `test/app/about_dialog_test.dart`.
- Modify `lib/app/home_screen.dart`, `test/features/appearance/palette_menu_button_test.dart` (Tab step only) and
  `integration_test/app_boot_test.dart`.

**Interfaces:**
- Consumes `appInfoProvider`, `fakeAppInfo`, `buildTestApp(appInfo:)`, `AppLogo` and `SmartCommuteApp.title`.
- Produces `AboutButton` (`Key('about-button')`, `tooltip`) and `AboutAppDialog` (`description`, `author`,
  `versionUnavailable`).

- [ ] **Step 1: Write the failing tests.** Create `test/app/about_dialog_test.dart`:

```dart
// E4: the app-bar About action and its dialog. Opening and closing it
// changes nothing else in the app.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sg_smart_commute/app/about_dialog.dart';
import 'package:sg_smart_commute/app/app.dart';
import 'package:sg_smart_commute/app/app_info.dart';
import 'package:sg_smart_commute/app/app_logo.dart';
import 'package:sg_smart_commute/app/home_screen.dart';
import 'package:sg_smart_commute/core/geo/geo.dart';
import 'package:sg_smart_commute/core/location/location_service.dart';
import 'package:sg_smart_commute/features/appearance/domain/app_palette.dart';
import 'package:sg_smart_commute/features/appearance/presentation/palette_theme.dart';
import 'package:sg_smart_commute/features/journey/journey_providers.dart';

import '../../integration_test/fakes/fake_bus_arrival_repository.dart';
import '../../integration_test/fakes/fake_bus_network.dart';
import '../../integration_test/fakes/fake_environment_repository.dart';
import '../../integration_test/fakes/fake_location_service.dart';
import '../../integration_test/fakes/fake_map.dart';
import '../../integration_test/fakes/fake_place_search_repository.dart';
import '../../integration_test/fakes/fake_route_geometry.dart';
import '../../integration_test/fakes/test_app.dart';

const aboutButton = Key('about-button');
const dialogTransition = Duration(milliseconds: 300);
const bishan = LatLng(1.3508, 103.8485);

Widget app({
  AppInfo? appInfo = fakeAppInfo,
  AppPalette palette = AppPalette.teal,
}) => buildTestApp(
  location: FakeLocationService(access: LocationAccess.denied),
  environment: FakeEnvironmentRepository(),
  appInfo: appInfo,
  palette: palette,
);

Future<void> pumpTall(WidgetTester tester, Widget widget) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(widget);
  await tester.pump();
}

Future<void> open(WidgetTester tester) async {
  await tester.tap(find.byKey(aboutButton));
  await tester.pump();
  await tester.pump(dialogTransition);
}

Future<void> settleDialog(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(dialogTransition);
}

/// The dialog's texts in tree (reading) order.
List<String?> dialogTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data)
    .toList();

bool aboutFocused() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  var found = context.widget.key == aboutButton;
  context.visitAncestorElements((e) {
    found = found || e.widget.key == aboutButton;
    return !found;
  });
  return found;
}

/// Android's system Back, as the engine delivers it.
Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    SystemChannels.navigation.codec.encodeMethodCall(
      const MethodCall('popRoute'),
    ),
    (_) {},
  );
}

void main() {
  testWidgets('a named button before the colour theme button; the logo and '
      'title stay decorative', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpTall(tester, app());
    expect(
      tester.getSemantics(find.byKey(aboutButton)),
      isSemantics(
        isButton: true,
        isEnabled: true,
        hasEnabledState: true,
        isFocusable: true,
        hasTapAction: true,
        tooltip: 'About Singapore Smart Commute',
      ),
    );
    expect(
      tester.getRect(find.byKey(aboutButton)).right,
      lessThanOrEqualTo(
        tester.getRect(find.byKey(const Key('palette-button'))).left,
      ),
    );
    expect(
      find.ancestor(
        of: find.byKey(const Key('app-logo')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(
      tester.getSemantics(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(SmartCommuteApp.title),
        ),
      ),
      isNot(isSemantics(hasTapAction: true)),
    );
    semantics.dispose();
  });

  testWidgets('opens by tap: icon, name, description, author, the '
      'compiled-in version, then View licenses and Close; no build date', (
    tester,
  ) async {
    await pumpTall(tester, app());
    await open(tester);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(AppLogo),
      ),
      findsOneWidget,
    );
    expect(dialogTexts(tester), [
      'Singapore Smart Commute',
      AboutAppDialog.description,
      'Author: Jaycee Wee',
      'Version 9.8.7 (42)',
      'View licenses',
      'Close',
    ]);
  });

  testWidgets('a build without a version: "Version unavailable", the rest '
      'unchanged', (tester) async {
    await pumpTall(tester, app(appInfo: null));
    await open(tester);
    expect(dialogTexts(tester), [
      'Singapore Smart Commute',
      AboutAppDialog.description,
      'Author: Jaycee Wee',
      'Version unavailable',
      'View licenses',
      'Close',
    ]);
  });

  testWidgets('Close, Escape and system Back each close it', (tester) async {
    await pumpTall(tester, app());
    await open(tester);
    await tester.tap(find.text('Close'));
    await settleDialog(tester);
    expect(find.byType(AlertDialog), findsNothing);
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settleDialog(tester);
    expect(find.byType(AlertDialog), findsNothing);
    await open(tester);
    await systemBack(tester);
    await settleDialog(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget, reason: 'app still open');
  });

  testWidgets(
    'keyboard: Tab reaches About first; Enter opens; Escape closes and '
    'returns focus; Space opens',
    (tester) async {
      await pumpTall(tester, app());
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(aboutFocused(), isTrue, reason: 'the first Tab stop');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settleDialog(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settleDialog(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(aboutFocused(), isTrue, reason: 'focus returns to the button');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await settleDialog(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.windows,
    }),
  );

  testWidgets("View licenses opens Flutter's licence page", (tester) async {
    await pumpTall(tester, app());
    await open(tester);
    await tester.tap(find.text('View licenses'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LicensePage), findsOneWidget);
  });

  testWidgets('360 × 780 dp at 2× text: both actions fit beside the title; '
      'the dialog scrolls and its buttons stay on screen', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(app());
    await tester.pump();
    expect(tester.takeException(), isNull);
    final about = tester.getRect(find.byKey(aboutButton));
    final palette = tester.getRect(find.byKey(const Key('palette-button')));
    expect(about.width, greaterThanOrEqualTo(48));
    expect(about.right, lessThanOrEqualTo(palette.left));
    expect(
      tester
          .getRect(
            find.descendant(
              of: find.byType(AppBar),
              matching: find.text(SmartCommuteApp.title),
            ),
          )
          .right,
      lessThanOrEqualTo(about.left),
    );
    await open(tester);
    expect(tester.takeException(), isNull);
    final screen = Offset.zero & const Size(360, 780);
    for (final label in ['View licenses', 'Close']) {
      final r = tester.getRect(find.text(label));
      expect(
        screen.contains(r.topLeft) &&
            screen.contains(r.bottomRight - const Offset(1, 1)),
        isTrue,
        reason: label,
      );
    }
    await tester.scrollUntilVisible(
      find.text('Version 9.8.7 (42)'),
      50,
      scrollable: find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  for (final b in Brightness.values) {
    for (final p in AppPalette.values) {
      testWidgets('${b.name}, ${p.label}: the dialog takes the palette scheme', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = b;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await pumpTall(tester, app(palette: p));
        await open(tester);
        expect(tester.takeException(), isNull);
        expect(
          Theme.of(tester.element(find.byType(AlertDialog))).colorScheme,
          paletteTheme(p, b).colorScheme,
        );
      });
    }
  }

  testWidgets('opening and closing About changes nothing else: no re-plan, '
      'refetch, camera move, tile or geometry request; the selection kept', (
    tester,
  ) async {
    final bus = FakeBusNetworkRepository();
    final arrivals = FakeBusArrivalRepository();
    final geometry = FakeRouteGeometryRepository();
    final tiles = FakeTileProvider();
    tester.view.physicalSize = const Size(1080, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildTestApp(
        location: FakeLocationService(
          access: LocationAccess.granted,
          position: bishan,
        ),
        environment: FakeEnvironmentRepository(),
        places: FakePlaceSearchRepository(),
        busNetwork: bus,
        busArrivals: arrivals,
        routeGeometry: geometry,
        mapTiles: () => tiles,
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('destination-field')),
      'VivoCity',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.text('VIVOCITY'));
    await tester.pump();
    await tester.pump();
    for (final key in ['select-option-F10', 'show-map']) {
      await tester.ensureVisible(find.byKey(Key(key)));
      await tester.pump();
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
      await tester.pump();
    }
    Object? plan() =>
        ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
            .read(journeyPlanProvider)
            .value;
    MapCamera camera() =>
        MapCamera.of(tester.element(find.byType(MarkerLayer)));
    final before = (
      plan: plan(),
      centre: camera().center,
      zoom: camera().zoom,
      loads: (bus.loads, arrivals.totalCalls, geometry.loads),
      tiles: tiles.requested.length,
    );
    expect(before.plan, isNotNull);
    expect(before.tiles, greaterThan(0), reason: 'the map really drew');

    await open(tester);
    await tester.tap(find.text('Close'));
    await settleDialog(tester);

    expect(identical(plan(), before.plan), isTrue, reason: '0 new plans');
    expect(camera().center, before.centre);
    expect(camera().zoom, before.zoom);
    expect((bus.loads, arrivals.totalCalls, geometry.loads), before.loads);
    expect(tiles.requested.length, before.tiles);
    expect(find.byKey(const Key('selected-option-F10')), findsOneWidget);
  });
}
```

  Amend the E1 keyboard test (§5.5) in `test/features/appearance/palette_menu_button_test.dart`. Replace

```dart
      await key(LogicalKeyboardKey.tab);
      expect(focused(), 'button', reason: 'the first Tab stop');
```

  with

```dart
      await key(LogicalKeyboardKey.tab);
      await key(LogicalKeyboardKey.tab);
      expect(focused(), 'button', reason: 'the second Tab stop, after About');
```

  Then add an About step to `integration_test/app_boot_test.dart`, after the existing `expect`:

```dart
    await tester.tap(find.byKey(const Key('about-button')));
    await pumpUntilFound(tester, find.text('Author: Jaycee Wee'));
    expect(find.text('Version 9.8.7 (42)'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Author: Jaycee Wee'), findsNothing);
```

  Check `pumpUntilFound`'s signature in `integration_test/support.dart` before using it, and match it.
- [ ] **Step 2: RED through CI.** Commit `test(app): E4 About action and dialog (RED)` and push.
  - Expected: a compile failure (`about_dialog.dart` is missing).
  - Note that the amended E1 Tab test fails on `main`'s layout, where the second Tab leaves the palette button. That
    is the intended RED.
- [ ] **Step 3: Implement.**
  - Create `lib/app/about_dialog.dart` exactly as in §5.2.
  - In `lib/app/home_screen.dart`, add `import 'about_dialog.dart';` and set
    `actions: const [AboutButton(), PaletteMenuButton()]`.
- [ ] **Step 4: GREEN through CI.** Commit `feat(app): E4 About action and dialog`, push, and record N/N. The full
  suite must include E1's palette, invariants and colour-guard tests, all green.
- [ ] **Step 5: Mutations through CI:** M1, M2 and M6–M7, plus M10–M12 (§8).

### Task A4: Documentation

- [ ] **`docs/assumptions.md`:** new rows.
  - **E3 icons:** the master and its source (O2); generator 0.14.4 with the command; inset 16 %; the O3 background;
    no monochrome; `assets/app_icon.png` kept.
  - **E3 names:** Android and Web labels; the application ID unchanged; O4 colours.
  - **E4 About:** the exact copy and order; the version from `appBuildName`/`appBuildNumber` and "Version
    unavailable"; no build date; View licenses (same-origin `NOTICES`, only when tapped).
- [ ] **`docs/architecture.md`:** a short ADR, "E4 version source: Flutter's compiled-in build name/number, not
  `package_info_plus`". Context is A0 (§2.3, §2.5); the consequences are no plugin, no request, and `null` outside
  the flutter tool.
- [ ] **`CLAUDE.md`:**
  - Project: "E3 icons, E4 About" next to E1.
  - Architecture: `lib/app/app_info.dart` and `lib/app/about_dialog.dart`, and the icon regeneration command.
  - Testing: `buildTestApp(appInfo:)` with the fake `9.8.7 (42)`, and CI for `flutter test`.
- [ ] **`README.md`:** the About dialog in the feature list. No screenshot change is required. If the README shows the
  launcher icon, update it.
- [ ] **`docs/testing.md`:** the E3 regeneration and manifest-formatting note, and run-log rows per task.
- [ ] Commit `docs: E3 icons and E4 About`.

### Task A5: Gates

- [ ] Local:
  - `dart format --set-exit-if-changed .`;
  - `flutter analyze`;
  - `flutter build web --release`;
  - `flutter build apk --debug`;
  - `flutter build apk --release`.

  Record the release APK size against 55,108,652 B (E1). The dependency cost is expected to be about 0 B; the icon
  PNGs add a few hundred KB at most (estimate).
- [ ] **CI full suite** on the final head: URL and N/N.
- [ ] **Android integration** on `emulator-5558`: `flutter test integration_test -d emulator-5558`.
- [ ] **Web drive** (profile, web-server, chromedriver 154), one file per run, with 0 CSP violations and 0 SEVERE.
  If Smart App Control blocks a step, record the exact message and Not run.

### Task A6: Live checks

- **Android** (`emulator-5558`; never `emulator-5554`):
  1. The launcher icon on the home screen and in the app drawer, side by side with the app-bar logo. It must be the
     same art, not badly cropped, with no white square or padding.
  2. The Android 12+ splash shows the new art.
  3. The label reads "Singapore Sm…" or the full name. Check App info and the location prompt (on a fresh install).
  4. About shows `Version 1.0.0 (1)`, equal to `aapt2 dump badging` `versionName='1.0.0' versionCode='1'`.
  5. Check the five palettes in light and dark.
  6. Font scale 2.0 at 360 dp.
  7. Back closes the dialog.
  8. After a restart the palette is kept (E1).
  9. Recents shows "Singapore Smart Commute".
- **Web** (real Chrome):
  1. Favicon, tab title, and the PWA install name and icon. The maskable icon must have clean corners.
  2. Tab to About, Enter, Escape, then Space; check `role=dialog`, the name, and focus returning to the button.
  3. The version equals `build/web/version.json`.
  4. The five palettes in light and dark.
  5. 360 px at 2×.
  6. Opening About makes 0 network requests (DevTools), and "View licenses" makes only the same-origin `NOTICES` read.
  7. 0 CSP or SEVERE errors.

### Task A7: Final review and PR

- [ ] A fresh reviewer on the most capable model reviews the full diff against `origin/main`. Checklist:
  - no E2 or E5 code; no planner or map change (except tests);
  - no provider host or CSP change; no secret; no dependency; `pubspec*` unchanged;
  - E1 intact; only the Tab step changed;
  - the version is never hard-coded; no build date;
  - the copy is exact;
  - generated resources are confined to §6.
- [ ] Fix Critical and Important findings, rerun the affected gates in CI and locally, then freeze the head.
- [ ] Push and open the PR against `main` with the evidence. **Do not merge.**

## 8. Mutation checks (each via a throwaway `mut/*` branch in CI, §3.3)

| ID | Mutation | Must fail |
|---|---|---|
| M1 | The dialog hard-codes `'Version 1.0.0 (1)'` | dialog-text tests (expects `9.8.7 (42)`) and the lib/ literal guard |
| M2 | `label` swaps version and build | `label` unit test, dialog-text test |
| M3 | `appInfoFrom` ignores null or empty (would print "Version null") | `appInfoFrom` test, "Version unavailable" widget test |
| M4 | The provider returns `AppInfo(version: '1.0.0', buildNumber: '1')` | lib/ literal guard |
| M5 | The provider ignores the constants and returns `null` | the pubspec-wiring test |
| M6 | `AppTitle` wrapped in `InkWell(onTap: …)` | decorative test |
| M7 | The tooltip changes to `'About'` | named-button test |
| M8 | `android:label` reverted to `sg_smart_commute` | identity test |
| M9 | The xxxhdpi template icon restored (`git show 53acc19:<path>`) | identity test |
| M10 | Description and author lines swapped | dialog-text order test |
| M11 | `scrollable: false` | 360 dp at 2× test (overflow or unreachable version) |
| M12 | About placed after the palette button | order test and the amended E1 Tab test |

## 9. Risks

1. **No CI yet (O1).** Test-first can't start until A-CI is approved and merged. Linux and Windows test differences
   are possible on the first CI run; stop and report if any appear.
2. **The icon master is missing (O2).** The fallback gives soft 512 px Web and 432 px adaptive icons.
3. **The generator run as a global tool** may need the package in `pubspec` (A1 Step 3 rule). Its manifest re-encode
   is handled by restoring the file.
4. **Smart App Control** may also block other local tools (builds, drive). Each block is recorded, never worked
   around by changing the policy.
5. **Launcher label truncation.** Accepted (A-Q4).
6. **Theme focus ring** is faint on light palettes. This is a known E1 limitation, unchanged.

## 10. In and out of scope

- **In:**
  - E3 platform icons and visible names;
  - the E4 About action, dialog and version seam;
  - the E1 regression and the one Tab-step test edit;
  - the docs;
  - A-CI, once approved.
- **Out:**
  - E2 (static journey time; decisions frozen for Phase B);
  - E5 (one-transfer journeys; not researched);
  - planner, ranking, map and journey UI;
  - `package_info_plus`, build date and a monochrome icon;
  - manifest colour changes (O4);
  - logo redesign.

## Self-review against `main` @ `53acc19` (by the plan author)

1. **Spec coverage:**
   - Guide §4 (E3): the resource audit, one master, the generator, labels, tests and live checks are covered by A1,
     A6 and §4.
   - Guide §5 (E4): the info action, dialog, copy, version seam, failure and accessibility are covered by A2, A3,
     A6 and §5.
   - Guide §3 (E1 preservation): the Global Constraints, the palette tests, the E1 suite in CI and A6 step 5.
   - Guide §6 A0–A7: §2 and §7.
   - Owner rulings A-Q1–A-Q6: §1.2, §3, §5 and the Global Constraints.
2. **Placeholders:** none in code steps. O1–O4 are explicit owner inputs with defaults, not placeholders.
3. **Type consistency:**
   - `AppInfo{version, buildNumber, label}`, `appInfoFrom(String?, String?)`, `appInfoProvider: Provider<AppInfo?>`,
     `fakeAppInfo` and `buildTestApp(appInfo:)` are used identically in A2, A3 and §5.
   - The keys `about-button`, `palette-button`, `app-logo`, `select-option-F10`, `show-map`,
     `selected-option-F10` and `destination-field` exist on `main`, or are created in A3.
4. **Checked against current code:**
   - `home_screen.dart:22-24` (actions);
   - `test_app.dart` parameters and overrides;
   - `palette_menu_button_test.dart:179-180` (the Tab step);
   - `app_logo.dart` (`AppLogo.asset`, `ExcludeSemantics`);
   - `index.html:37,43`;
   - `manifest.json`;
   - the template icon lengths (A0 listing);
   - `grep -rn 1.0.0 lib` empty;
   - `SystemChannels.navigation`;
   - `AlertDialog` scrollable layout (`dialog.dart:901-923`).

   `FakeTileProvider.requested`, `FakeBusArrivalRepository.totalCalls`, `FakeBusNetworkRepository.loads` and
   `FakeRouteGeometryRepository.loads` are used as in `palette_change_invariants_test.dart`.
5. **Review Focus:** five live-only failure modes, each pinned to an A6 step.
