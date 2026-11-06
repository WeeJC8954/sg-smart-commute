#!/usr/bin/env bash
# Chrome (dart2js) run of the E5 benchmark (README.md). From the repository
# root:  bash tool/e5_transfer_bench/run_chrome.sh "<path to chrome>"
# DART may point at the SDK's dart (default: dart on PATH).
set -euo pipefail
chrome=${1:?usage: run_chrome.sh <path to chrome>}
dart=${DART:-dart}
here=tool/e5_transfer_bench
out=build/e5_transfer_bench
data=$out/snapshot  # fetch_snapshot.sh
mkdir -p "$out"
"$dart" compile js -O4 -o "$out/bench.js" "$here/web_main.dart" >/dev/null
cp "$here/index.html" "$data/stops.min.json" "$data/services.min.json" "$out/"
dir=$(cd "$out" && (pwd -W 2>/dev/null || pwd))
"$chrome" --headless=new --disable-gpu --disable-extensions \
  --allow-file-access-from-files --dump-dom "file:///${dir#/}/index.html" \
  2>/dev/null >"$out/dom.html"
sed -n '/<pre id="out">/,/<\/pre>/p' "$out/dom.html" |
  sed -e 's/<pre id="out">//' -e 's/<\/pre>.*//' \
    -e 's/&gt;/>/g' -e 's/&lt;/</g' -e 's/&amp;/\&/g'
