#!/usr/bin/env bash
# Phase 2 M0 map feasibility probe: basemap tiles and walking-route endpoints.
# Read-only GETs, no credentials: one request per endpoint, plus one map view
# of OneMap tiles (40) in parallel to test its shared-host limit. Not part of the app.
# Usage: bash tool/probe_map.sh > docs/probe-output/map-probes.txt
set -u
ORIGIN="https://example.com"
UA="sg-smart-commute-p2m0-probe (university course project)"

# One tile over Raffles Place (103.8515, 1.2840) at z16, from
# x = floor((lon + 180) / 360 * 2^z), y = floor((1 - asinh(tan(lat)) / pi) / 2 * 2^z).
Z=16 X=51673 Y=32534

probe() { # name url
  local name="$1" url="$2"
  local body; body=$(mktemp)
  echo "=== $name"
  echo "GET $url"
  curl -s -m 20 -D - -o "$body" -A "$UA" -H "Origin: $ORIGIN" "$url" \
    | tr -d '\r' \
    | grep -iE '^HTTP/|^access-control-allow-origin|^content-type|^cache-control|^cross-origin-resource-policy|ratelimit|retry-after' \
    | sort -u
  echo "bytes: $(wc -c < "$body")"
  case "$(file -b --mime-type "$body" 2>/dev/null)" in
    image/*|application/octet-stream|application/x-protobuf) echo "body: <binary>" ;;
    *) echo "body: $(head -c 200 "$body" | tr '\n' ' ')" ;;
  esac
  echo
  rm -f "$body"
}

echo "# probe run: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

echo "## Raster basemaps"
for style in Default Night Grey Original; do
  probe "OneMap $style" "https://www.onemap.gov.sg/maps/tiles/$style/$Z/$X/$Y.png"
done
probe "OneMap Default (z19)" "https://www.onemap.gov.sg/maps/tiles/Default/19/413388/260273.png"
probe "OneMap Default (outside SG: London z16)" "https://www.onemap.gov.sg/maps/tiles/Default/16/32744/21792.png"
probe "OSM standard" "https://tile.openstreetmap.org/$Z/$X/$Y.png"
probe "CARTO light_all" "https://a.basemaps.cartocdn.com/light_all/$Z/$X/$Y.png"
probe "CARTO dark_all" "https://a.basemaps.cartocdn.com/dark_all/$Z/$X/$Y.png"
probe "CARTO light_all @2x" "https://a.basemaps.cartocdn.com/light_all/$Z/$X/$Y@2x.png"

echo "## Vector basemap (keyless)"
probe "OpenFreeMap style liberty" "https://tiles.openfreemap.org/styles/liberty"
probe "OpenFreeMap TileJSON" "https://tiles.openfreemap.org/planet"

echo "## Bus route geometry"
probe "busrouter routes.min.json" "https://data.busrouter.sg/v1/routes.min.json"

echo "## Walking routes, Raffles Place MRT -> Fullerton Hotel (~600 m)"
A="103.8515,1.2840" B="103.8531,1.2862"
probe "OSRM demo (foot)" "https://router.project-osrm.org/route/v1/foot/$A;$B?overview=full&geometries=polyline"
probe "FOSSGIS OSRM routed-foot" "https://routing.openstreetmap.de/routed-foot/route/v1/driving/$A;$B?overview=full&geometries=polyline"
probe "FOSSGIS Valhalla pedestrian" \
  'https://valhalla1.openstreetmap.de/route?json=%7B%22locations%22%3A%5B%7B%22lon%22%3A103.8515%2C%22lat%22%3A1.2840%7D%2C%7B%22lon%22%3A103.8531%2C%22lat%22%3A1.2862%7D%5D%2C%22costing%22%3A%22pedestrian%22%7D'
probe "BRouter (hiking-mountain)" "https://brouter.de/brouter?lonlats=103.8515,1.2840%7C103.8531,1.2862&profile=hiking-mountain&alternativeidx=0&format=geojson"
probe "OneMap routing, no token" "https://www.onemap.gov.sg/api/public/routingsvc/route?start=1.2840,103.8515&end=1.2862,103.8531&routeType=walk"

echo "## OneMap: one map view of tiles in parallel (8 x 5 at z16), then one search"
echo "Does tile traffic trip the per-host limit that 429s search after 2-3 calls in ~1.5 s?"
codes=$(for dx in 0 1 2 3 4 5 6 7; do for dy in 0 1 2 3 4; do
  curl -s -m 20 -o /dev/null -w "%{http_code}\n" -A "$UA" -H "Origin: $ORIGIN" \
    "https://www.onemap.gov.sg/maps/tiles/Default/$Z/$((X - 4 + dx))/$((Y - 2 + dy)).png" &
done; done; wait)
echo "tile responses: $(echo "$codes" | grep -c "^200$") x 200 of $(echo "$codes" | grep -c .)"
probe "OneMap search right after the burst" \
  "https://www.onemap.gov.sg/api/common/elastic/search?searchVal=VivoCity&returnGeom=Y&getAddrDetails=N&pageNum=1"
