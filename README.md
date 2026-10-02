# Singapore Smart Commute

A **front-end-only** Flutter app (Android + Web) for Singapore. It shows current conditions (2-hour forecast,
UV, 1-hr PM2.5, 24-hr PSI) and suggests how to start a journey: a direct bus with live arrival times, and the
nearest MRT station as an alternative. University course project.

> **Status:** Milestone 4. The app has location with manual fallback, the environmental dashboard, OneMap
> place search for origin and destination, a direct-bus suggestion with an MRT alternative, and live bus
> arrival times (ArriveLah) for each suggested bus, refreshed manually.

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

NEA / data.gov.sg (Singapore Open Data Licence) · busrouter.sg (community project; bus data © LTA) ·
MRT station exits: LTA via data.gov.sg (Singapore Open Data Licence), bundled as `assets/mrt_stations.json`
(regenerate with `dart run tool/build_mrt_asset.dart`) · OneMap © SLA · live arrivals: ArriveLah (community
proxy of LTA DataMall Bus Arrival; not an official LTA API).
Details and limits: [`docs/data-sources.md`](docs/data-sources.md).

## Known limitations

- Walking times are **estimates** (straight-line × 1.3 at 80 m/min), not routed.
- Phase 1 suggests **direct buses only** (no transfers), ranked by a documented heuristic, not "the best"
  route. MRT is shown as information only: the nearest station name and an estimated walk, with no lines,
  codes, routes or arrivals.
- Bus stop data comes from busrouter.sg and is loaded on the first journey request (about 570 KB).
- Tokenless OneMap search can rate-limit (HTTP 429 after a few quick calls was seen in M3 testing).
- busrouter, ArriveLah and tokenless OneMap search are third-party services with no SLA.
- Live arrivals are shown only for the suggested buses' boarding stops and refresh only when you tap
  "Refresh arrivals" (reused for 15 s). An arrival can be missing (e.g. a peak-hour-only service off-peak):
  the app then says "No live arrival available" and still shows the route. "(scheduled)" marks estimates LTA
  bases on the timetable rather than the bus's position.

## Documentation

- [Implementation guide v2.1](docs/singapore-smart-commute-implementation-guide.v2.md)
- [API feasibility](docs/api-feasibility.md) · [Architecture](docs/architecture.md) ·
  [Data sources](docs/data-sources.md) · [Assumptions](docs/assumptions.md) · [Testing](docs/testing.md)

## Roadmap

M1 location + environment → M2 places → M3 direct-bus planner + MRT → M4 live arrivals → M5 hardening →
Phase 2 map.
