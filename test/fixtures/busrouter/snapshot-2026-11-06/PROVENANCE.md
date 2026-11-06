# busrouter snapshot (2026-11-06): provenance

Unmodified full copies of the two busrouter files the app loads, kept as the fixed input of the E5 benchmark
(`tool/e5_transfer_bench/README.md`) and of the planned E5 regression fixtures. Data © LTA via busrouter.sg
(`docs/data-sources.md`, "Licence / attribution"); the app credits it as "Bus data: busrouter.sg (data © LTA)".

| File | URL | Size (bytes) | SHA-256 |
|---|---|---|---|
| `stops.min.json` | https://data.busrouter.sg/v1/stops.min.json | 317,298 | `db30f31bf874ae3d33da6bf1817484bf10dc1166ae88dbb2f67d4f60690b3ef6` |
| `services.min.json` | https://data.busrouter.sg/v1/services.min.json | 256,632 | `e9e3d370489723d22638434307e35f2cd6581eb5b21013bb0e219dfb15afa95a` |

Fetched with `curl` at 2026-11-06 12:27 UTC (HTTP 200 for both). Never edit these files: a new snapshot gets a new
dated folder, and the benchmark's `expected_results.txt` is regenerated from it.
