# Singapore Smart Commute

A **front-end-only** Flutter app (Android + Web) for Singapore. It shows current conditions (2-hour forecast,
UV, 1-hr PM2.5, 24-hr PSI) and suggests how to start a journey: a direct bus with live arrival times, and the
nearest MRT station as an alternative. University course project.

> **Status:** Milestone 0 (feasibility + skeleton). There are no app features yet. See
> [`docs/api-feasibility.md`](docs/api-feasibility.md).

## No credentials required

The app calls only public, keyless, CORS-enabled data sources. It ships **no API keys or secrets**, and you
don't need to configure any `.env`, `--dart-define` or account. There is no backend or proxy. See
[`docs/architecture.md`](docs/architecture.md) (ADR-001).

## Prerequisites

| Tool | Version used |
|---|---|
| Flutter (stable) | 3.47.2 (Dart 3.13.2) |
| Chrome | for Web |
| Android SDK + emulator or device | SDK 36, JDK 21 (Android Studio) |

Run `flutter doctor` first. Visual Studio (Windows desktop) is **not** needed. Android builds need the SDK
licences accepted (`flutter doctor --android-licenses`). Gradle downloads the NDK, CMake and Platform 36 on
the first build, which can take 15–20 minutes.

## Setup

```bash
git clone https://github.com/WeeJC8954/sg-smart-commute.git
cd sg-smart-commute
flutter pub get
```

## Run

```bash
flutter run -d chrome        # Web
flutter devices              # find your Android emulator/device id
flutter run -d <device-id>   # Android
```

- **Web geolocation needs HTTPS** in deployed builds (`localhost` is exempt during development). Any
  hosted demo must be served over HTTPS (static hosting only).
- **Android emulator:** the default emulator location is outside Singapore. Set a Singapore location in
  Extended controls → Location.

## Test and quality gates

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

The dev-only feasibility probes are described in [`docs/testing.md`](docs/testing.md).

## Data sources and attribution

NEA / data.gov.sg (Singapore Open Data Licence) · busrouter.sg and ArriveLah (community projects over LTA
DataMall data) · OneMap © SLA. Details and limits: [`docs/data-sources.md`](docs/data-sources.md).

## Known limitations

- Walking times are **estimates** (straight-line × 1.3 at 80 m/min), not routed.
- Phase 1 suggests **direct buses only** (no transfers). MRT is shown as information only.
- busrouter, ArriveLah and tokenless OneMap search are third-party services with no SLA.

## Documentation

- [Implementation guide v2.1](docs/singapore-smart-commute-implementation-guide.v2.md)
- [API feasibility](docs/api-feasibility.md) · [Architecture](docs/architecture.md) ·
  [Data sources](docs/data-sources.md) · [Assumptions](docs/assumptions.md) · [Testing](docs/testing.md)

## Roadmap

M1 location + environment → M2 places → M3 direct-bus planner + MRT → M4 live arrivals → M5 hardening →
Phase 2 map.
