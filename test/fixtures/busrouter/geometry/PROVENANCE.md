# Geometry fixtures: provenance

Captured from live busrouter, a subset of three files, keyed exactly as the
live data (routes: service -> encoded polylines; services: service -> {name,
routes}; stops: code -> [lng, lat, name, road]).

- https://data.busrouter.sg/v1/routes.min.json
- https://data.busrouter.sg/v1/services.min.json
- https://data.busrouter.sg/v1/stops.min.json

Captured at (UTC): 2026-10-03T04:45:59.919479Z

Command (regenerates these files and this one): `dart run tool/capture_route_geometry_fixtures.dart`

Services captured: 10, 46, 4, 11, 2B, 115 (10: 2 direction(s), 46: 2 direction(s), 4: 1 direction(s), 11: 1 direction(s), 2B: 1 direction(s), 115: 1 direction(s)).

## Planned test cases

Indices are positions in the direction's stop list in `services.json`. The
codes are as found in the captured data; "expected" is what the plan assumed.

| Service/dir | Board -> alight index | Stop codes as captured | Expected |
| --- | --- | --- | --- |
| 10/0 | 43 -> 52 | 03019 -> 14141 | 03019 -> 14141 |
| 115/0 | 0 -> 1 | 63221 -> 63231 | 63221 -> 63231 |
| 10/1 | 0 -> 1 | 16009 -> 16089 | 16009 -> 16089 |
| 46/1 | 0 -> 1 | 77009 -> 77321 | 77009 -> 77321 |
| 4/0 | 0 -> 1 | 75009 -> 76191 | 75009 -> 76191 |
| 11/0 | 6 -> 8 | 80199 -> 90039 | 80199 at 6 and 17 |
| 11/0 | 17 -> 19 | 80199 -> 80171 | 80199 at 6 and 17 |
| 2B/0 | 0 -> 3 | 99009 -> 99039 | 99009 -> 99039 |
