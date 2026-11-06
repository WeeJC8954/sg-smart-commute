# E5 one-transfer benchmark (development only)

Kept for E5 Gate 2 and later gates (owner ruling F5, `docs/e5-gate0-discovery-report.md` §13). Not part of the app,
not a test gate, never run by `flutter test` or CI. Results and their reading: `docs/e5-gate2-implementation-plan.md`
§2; every run is logged in `docs/testing.md`.

## What it measures

- **Fixed inputs.** The busrouter snapshot `test/fixtures/busrouter/snapshot-2026-11-06/` (SHA-256 in its
  `PROVENANCE.md`), a seeded sample (seed 20261106, 500 stop pairs at least 1.5 km apart, each end moved 0.0004° in
  latitude and longitude off its stop), and 12 named stop pairs with no direct bus (`bench.dart`, `namedFixtures`).
- **Real app code** for parsing (`parseBusrouterStops`/`Services`), the direct planner (`planDirectBus`) and E2
  (`estimateBusMinutes`). The one-transfer search is a **prototype** (`transfer_search.dart`, Gate 0 §6 with the
  owner's F1 rules), not the implementation; Gate 3 writes the real search test-first in `lib/` and points this
  benchmark at it.
- **Results** (deterministic): coverage of the no-direct pairs for detour limits 2.0, 2.5, 3.0 and none, with a same-stop
  transfer or a walk of up to 150 m; plausibility (detour, minutes excluding waits, straight-line speed, journeys slower
  than walking); the journeys each limit step adds; what the 150 m walk adds; the named fixtures.
- **Timings:** parse, index build, the first (cold) plan and search, then warm `planDirectBus` (3 × 500 runs) and
  warm searches (3 × the no-direct pairs, limit 2.5). Chrome rounds `performance.now()` to 0.1 ms.

## Running it (from the repository root)

```bash
# Dart VM. "Running build hooks..." precedes the report on stdout.
dart run tool/e5_transfer_bench/vm_main.dart

# Chrome through dart2js -O4 (as `flutter build web`): compiles to build/e5_transfer_bench/,
# opens index.html headless with file access, prints the report. Needs bash and Chrome.
DART=<path to dart> bash tool/e5_transfer_bench/run_chrome.sh "<path to chrome>"
```

On the development PC: `DART=/c/Users/linus/dev/flutter-3.47.2/flutter/bin/dart` and
`"/c/Program Files/Google/Chrome/Application/chrome.exe"` (Git Bash).

## Checking a run

Everything from `E5 one-transfer benchmark` down to the `== timings` line must equal `expected_results.txt` on both
platforms (the run of 2026-11-06 was identical on the VM and in Chrome):

```bash
dart run tool/e5_transfer_bench/vm_main.dart | sed 's/^.*E5 one-transfer/E5 one-transfer/' \
  | sed '/== timings/,$d' | diff - tool/e5_transfer_bench/expected_results.txt
```

A difference means the inputs, the app's parser or planner, or the prototype changed. Explain it in the run log
before regenerating `expected_results.txt`. Timings vary between runs; report at least three runs per platform, with
the device and browser version.
