#!/usr/bin/env bash
# Milestone 0 API/CORS probe. Read-only GET/OPTIONS requests, no credentials.
# Usage: bash tool/probe_apis.sh > docs/probe-output/curl-probes.txt
set -u
ORIGIN="https://example.com"
UA="sg-smart-commute-m0-probe (university course project)"

probe() { # name url [extra curl args...]
  local name="$1" url="$2"; shift 2
  local body; body=$(mktemp)
  echo "=== $name"
  echo "GET $url"
  curl -s -m 20 -D - -o "$body" -A "$UA" -H "Origin: $ORIGIN" "$@" "$url" \
    | tr -d '\r' | grep -iE '^HTTP/|^access-control-allow-(origin|headers|methods)|ratelimit|retry-after' \
    | sort -u
  echo "bytes: $(wc -c < "$body")"
  # Redact pre-signed URL signature parameters (e.g. data.gov.sg's S3 download link).
  echo "body: $(head -c 220 "$body" | tr '\n' ' ' | sed -E 's/(X-Amz-[A-Za-z0-9-]+=)[^&" ]*/\1REDACTED/g')"
  echo
  rm -f "$body"
}

preflight() { # name url requested-header
  echo "=== PREFLIGHT $1 (Access-Control-Request-Headers: $3)"
  curl -s -m 20 -X OPTIONS -D - -o /dev/null -H "Origin: $ORIGIN" \
    -H "Access-Control-Request-Method: GET" -H "Access-Control-Request-Headers: $3" "$2" \
    | tr -d '\r' | grep -iE '^HTTP/|^access-control-allow-(origin|headers)' | sort -u
  echo
}

echo "# probe run: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

DG=https://api-open.data.gov.sg/v2/real-time/api
probe "data.gov.sg two-hr-forecast" "$DG/two-hr-forecast"
probe "data.gov.sg uv" "$DG/uv"
probe "data.gov.sg pm25" "$DG/pm25"
probe "data.gov.sg psi" "$DG/psi"
preflight "data.gov.sg (optional x-api-key)" "$DG/uv" "x-api-key"

probe "busrouter stops" "https://data.busrouter.sg/v1/stops.min.json"
probe "busrouter services" "https://data.busrouter.sg/v1/services.min.json"
probe "busrouter routes (Phase 2)" "https://data.busrouter.sg/v1/routes.min.json"
probe "ArriveLah 09048" "https://arrivelah2.busrouter.sg/?id=09048"

probe "OneMap search (no token)" "https://www.onemap.gov.sg/api/common/elastic/search?searchVal=vivocity&returnGeom=Y&getAddrDetails=Y&pageNum=1"
probe "OneMap routing (no token, expected 401)" "https://www.onemap.gov.sg/api/public/routingsvc/route?start=1.3,103.8&end=1.31,103.85&routeType=walk"
probe "Photon search" "https://photon.komoot.io/api/?q=vivocity&bbox=103.6,1.15,104.1,1.48&limit=3"
probe "Photon reverse" "https://photon.komoot.io/reverse?lat=1.3508&lon=103.8485"
sleep 1.1
probe "Nominatim search" "https://nominatim.openstreetmap.org/search?q=vivocity&countrycodes=sg&format=jsonv2&limit=3"
sleep 1.1
probe "Nominatim reverse" "https://nominatim.openstreetmap.org/reverse?lat=1.3508&lon=103.8485&format=jsonv2"

probe "data.gov.sg MRT exits poll-download" "https://api-open.data.gov.sg/v1/public/api/datasets/d_b39d3a0871985372d7e1637193335da5/poll-download"

probe "LTA DataMall BusArrival (excluded, expected 401)" "https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival?BusStopCode=09048"
preflight "LTA DataMall (excluded)" "https://datamall2.mytransport.sg/ltaodataservice/v3/BusArrival?BusStopCode=09048" "accountkey"
