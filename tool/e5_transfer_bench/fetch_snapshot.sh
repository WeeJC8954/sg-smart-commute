#!/usr/bin/env bash
# Downloads the benchmark's fixed input into build/ (git-ignored) and checks it
# byte for byte (README.md). The files are not committed: their redistribution
# rights are not established (docs/e5-gate2-implementation-plan.md §2.8).
# Source: sgbusdata at a pinned commit, the repository data.busrouter.sg serves.
set -euo pipefail
commit=a60fe9e6a42873a0f60aba4a31725b39b1fe9d55
out=build/e5_transfer_bench/snapshot
mkdir -p "$out"
for f in stops services; do
  curl -sSf -o "$out/$f.min.json" \
    "https://raw.githubusercontent.com/cheeaun/sgbusdata/$commit/data/v1/$f.min.json"
done
cd "$out"
sha256sum -c - <<'SUMS'
db30f31bf874ae3d33da6bf1817484bf10dc1166ae88dbb2f67d4f60690b3ef6  stops.min.json
e9e3d370489723d22638434307e35f2cd6581eb5b21013bb0e219dfb15afa95a  services.min.json
SUMS
