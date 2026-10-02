# P2-M0 map spike (throwaway)

A minimal, isolated Flutter app that proved the Phase 2 map stack on Android and Web before any map code
enters the app. Findings: `docs/map-feasibility.md`. **Not part of the app:** it has its own `pubspec.yaml`,
the app's `pubspec.yaml` is unchanged, and the root `analysis_options.yaml` excludes this folder. Delete the
folder (and that exclude line) once P2-M1 lands.

What it shows: OneMap Default / Night, OSM and CARTO raster tiles in `flutter_map`; origin, destination and
stop markers; the Bus 10 ride 03019 → 14141 sliced from busrouter `routes.min.json`; the walk from Raffles
Place to the boarding stop from the FOSSGIS Valhalla pedestrian router; `RichAttributionWidget`. `?src=N`
(0–4) picks the basemap on Web.

`web/index.html` is the app's own CSP plus the spike's extra hosts (OSM, CARTO, Valhalla) in `connect-src`;
`img-src` is unchanged.

## Run

Only the sources are tracked (see `.gitignore`); generate the platform folders first:

```bash
cd tool/map_spike
flutter create --platforms=android,web --project-name map_spike --org sg.smartcommute.spike .
# flutter create keeps the tracked web/index.html. For a release APK, add
#   <uses-permission android:name="android.permission.INTERNET"/>
# to android/app/src/main/AndroidManifest.xml.
flutter pub get
flutter build web --release      # then serve build/web statically, e.g. python -m http.server 8772
flutter build apk --release      # adb install -r build/app/outputs/flutter-apk/app-release.apk
```
