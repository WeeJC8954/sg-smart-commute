# Data Sources

All Phase 1 sources are keyless and called directly from the client. Verification:
[`api-feasibility.md`](api-feasibility.md) (2026-10-01).

## data.gov.sg / NEA real-time APIs

| | |
|---|---|
| Owner | GovTech (data.gov.sg), data from NEA |
| Endpoints | `https://api-open.data.gov.sg/v2/real-time/api/two-hr-forecast`, `/uv`, `/pm25`, `/psi` |
| Data used | 2-hr forecast per area (`area_metadata[].label_location`, ~47 areas); UV index (national, hourly, daytime); 1-hr PM2.5 per region (5 regions, `regionMetadata`); `psi_twenty_four_hourly` per region |
| Auth | None. An optional API key exists for higher limits. It is not used, and it would be public if it ever were |
| Update cadence | Forecast: 2-hr validity window, update time in the payload; UV, PM2.5 and PSI: hourly readings (`updatedTimestamp` in the payload) |
| Limits | Anonymous: **6 real-time calls per 10 s** → `429` ([guide](https://guide.data.gov.sg/developer-guide/api-overview/api-rate-limits)) |
| Licence / attribution | Singapore Open Data Licence. Attribute "Source: NEA / data.gov.sg" |
| Limitations | Readings are national, regional or area-based, never point-based. UV is not measured at night |
| Fallback | Show the stale reading with its timestamp, or an unavailable state with Retry. Values are never fabricated |

## busrouter static data

| | |
|---|---|
| Owner | busrouter.sg (community project by Lim Chee Aun, `github.com/cheeaun/busrouter-sg`), derived from LTA data |
| Endpoints | `https://data.busrouter.sg/v1/stops.min.json` (~317 KB), `services.min.json` (~255 KB); `routes.min.json` (polylines, Phase 2) |
| Data used | Stops `code → [lng, lat, name, road]` (**lng first**); services `{name, routes: [[stop codes per direction]]}` |
| Auth | None |
| Update cadence | Static; refreshed by the project periodically |
| Licence / attribution | Verify the repo licence before release. Attribute "Bus data: busrouter.sg (LTA DataMall)" |
| Limitations | No SLA, and the schema could change without notice |
| Fallback | `StaticDataUnavailable` → journey shows "Bus data unavailable" plus the MRT alternative |

## ArriveLah

| | |
|---|---|
| Owner | Community project by Lim Chee Aun (`github.com/cheeaun/arrivelah`), proxying LTA DataMall Bus Arrival |
| Endpoint | `https://arrivelah2.busrouter.sg/?id={busStopCode}` |
| Data used | Per service: `next` / `subsequent` arrival `time` (ISO `+08:00`), `duration_ms`, `load` (SEA/SDA/LSD), `feature` (`WAB`), `type` |
| Auth | None |
| Update cadence | Near real time. The app only refreshes manually (≤ 20 s cache) |
| Licence / attribution | Verify the repo licence. Attribute "Arrivals: ArriveLah (LTA DataMall)" |
| Limitations | No SLA. Called only for ≤ 3 shortlisted stops per journey |
| Fallback | `No live arrival available`. A missing ETA is never shown as 0 min |

## OneMap search (tokenless)

| | |
|---|---|
| Owner | Singapore Land Authority |
| Endpoint | `https://www.onemap.gov.sg/api/common/elastic/search?searchVal=…&returnGeom=Y&getAddrDetails=Y&pageNum=1` |
| Data used | `SEARCHVAL`, `ADDRESS`, `POSTAL`, `LATITUDE`, `LONGITUDE` |
| Auth | Documented as token-required. Currently answers without a token, with an `error` message in the body |
| Licence / attribution | OneMap terms of use. Attribute "OneMap © SLA" |
| Limitations | Access could be withdrawn. Weak ranking for some parks (see feasibility §4.3) |
| Fallback | Detect 401/403, or `error` with empty `results` → `ApiUnauthorized`. The tested OSM adapters are candidates (not built yet) |

## Candidate fallbacks (evaluated, not integrated)

- **Photon** (`photon.komoot.io`, ODbL / OSM): keyless, CORS-enabled, suits type-ahead. Terms: "be fair —
  extensive usage will be throttled", with no availability guarantee.
- **Nominatim** (`nominatim.openstreetmap.org`, ODbL / OSM): keyless, CORS-enabled. Policy: ≤ 1 req/s,
  **no client-side autocomplete**, identify the app via Referer/User-Agent, show attribution.

## LTA MRT Station Exit (bundled asset — generation in Milestone 3)

- data.gov.sg dataset `d_b39d3a0871985372d7e1637193335da5` (GeoJSON), via `poll-download`. Singapore Open
  Data Licence.

## Excluded

- **LTA DataMall:** needs an AccountKey, and has no browser CORS support. Never called by the app. A local
  reference check is optional and needs the developer's own key (`api-feasibility.md` §5).
- **OneMap routing:** needs a token.
