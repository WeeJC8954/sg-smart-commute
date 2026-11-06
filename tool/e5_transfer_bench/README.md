# E5 one-transfer benchmark (development only)

Kept for E5 Gate 2 and later gates (owner ruling F5, `docs/e5-gate0-discovery-report.md` §13). Not part of the app,
not a test gate, never run by `flutter test` or CI, and nothing in `lib/` imports it. Results and their reading:
`docs/e5-gate2-implementation-plan.md` §2; every run is logged in `docs/testing.md`.

## Fixed input (downloaded, never committed)

The busrouter `stops.min.json` and `services.min.json` as published in `cheeaun/sgbusdata` at commit
`a60fe9e6a42873a0f60aba4a31725b39b1fe9d55` (2026-11-01, "Latest data: Sun Nov 1 00:45:58 UTC 2026"), byte-identical to
what `data.busrouter.sg` served on 2026-11-06:

| File | Size (bytes) | SHA-256 |
|---|---|---|
| `stops.min.json` | 317,298 | `db30f31bf874ae3d33da6bf1817484bf10dc1166ae88dbb2f67d4f60690b3ef6` |
| `services.min.json` | 256,632 | `e9e3d370489723d22638434307e35f2cd6581eb5b21013bb0e219dfb15afa95a` |

`fetch_snapshot.sh` downloads them from that commit into `build/e5_transfer_bench/snapshot/` (git-ignored) and stops
unless both hashes match. They are not in the repository: their redistribution rights are not established. Most of the
data is scraped from lta.gov.sg, whose terms forbid redistribution without LTA's written permission (plan §2.8). The
run works for as long as GitHub serves that commit.

Besides the input, the benchmark uses:
- **a seeded sample:** seed 20261106, 500 stop pairs at least 1.5 km apart, each end moved 0.0004° in latitude and
  longitude off its stop;
- **12 named stop pairs** with no direct bus (`bench.dart`, `namedFixtures`).

## What it measures

- **Real app code** for parsing (`parseBusrouterStops`/`Services`), the direct planner (`planDirectBus`) and E2
  (`estimateBusMinutes`, `estimateDirectJourney`). The one-transfer search is a **prototype** (`transfer_search.dart`,
  Gate 0 §6 with the owner's F1 rules), not the implementation. Gate 3 writes the real search test-first in `lib/` and
  points this benchmark at it.
- **Results** (deterministic):
  - coverage of the no-direct pairs for detour limits 2.0, 2.5, 3.0 and none, with a same-stop transfer or a walk of
    up to 150 m;
  - plausibility: detour, minutes excluding waits, straight-line speed, journeys slower than walking;
  - the journeys each limit step adds, and what the 150 m walk adds;
  - the G2-4 ranking comparison: score order against E2-minute order, with the largest gaps and the direct options
    as context;
  - the named fixtures;
  - the pre-E5 direct plans of the sample, the baseline that Gate 3 must leave unchanged.
- **Timings:** parse, index build, the first (cold) plan and search, then warm `planDirectBus` (3 × 500 runs) and warm
  searches (3 × the no-direct pairs, limit 2.5). Chrome rounds `performance.now()` to 0.1 ms.

## Running it (from the repository root, in bash)

```bash
bash tool/e5_transfer_bench/fetch_snapshot.sh      # once; needs curl and sha256sum

# Dart VM. "Running build hooks..." precedes the report on stdout.
dart run tool/e5_transfer_bench/vm_main.dart

# Chrome through dart2js -O4 (as `flutter build web`): compiles to build/e5_transfer_bench/,
# opens index.html headless with file access, prints the report.
DART=<path to dart> bash tool/e5_transfer_bench/run_chrome.sh "<path to chrome>"
```

On the development PC: `DART=/c/Users/linus/dev/flutter-3.47.2/flutter/bin/dart` and
`"/c/Program Files/Google/Chrome/Application/chrome.exe"` (Git Bash).

## Checking a run

Everything from `E5 one-transfer benchmark` down to the `== timings` line must equal `expected_results.txt` on both
platforms. The runs of 2026-11-06 were identical on the VM and in Chrome. To check a VM run:

```bash
dart run tool/e5_transfer_bench/vm_main.dart | sed 's/^.*E5 one-transfer/E5 one-transfer/' \
  | sed '/== timings/,$d' | diff - tool/e5_transfer_bench/expected_results.txt
```

- **If the output differs**, the inputs, the app's parser or planner, or the prototype changed. Explain it in the run
  log before regenerating `expected_results.txt`.
- **`expected_results.txt` holds only derived facts:** counts, stop codes, service numbers, road names (from LTA
  DataMall, Singapore Open Data Licence) and the named pairs' labels written here. It holds no stop names from
  lta.gov.sg.
- **Timings vary between runs.** Report at least three runs per platform, with the device and browser version.
