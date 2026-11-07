# busrouter test data (synthetic)

Hand-made data with the shapes of busrouter's `stops.min.json`, `services.min.json` and `routes.min.json`, built in
`synthetic_busrouter.dart`. Nothing is copied from busrouter, LTA or any other source:
- stop codes and service numbers start with `F`;
- names end in "(fake)";
- positions are laid out in metres from fixed origins;
- route lines are encoded with the test encoder (`integration_test/fakes/fake_route_geometry.dart`).

It replaced captured subsets of the live files on 2026-11-06 (owner decision A-1,
`docs/busrouter-fixture-licensing-audit.md`), because their redistribution rights could not be established.
`.gitignore` refuses JSON in this folder.

## Planner network (`busrouter_test.dart`): 224 stops, 6 services

| Service | Built for |
|---|---|
| `F4` | A one-direction loop from and back to `F0400` "Loop Int". The stops at indices 5 and 22 face each other across the road, 29.1 m apart |
| `F184` | One direction only, 45 stops: forward rides match, reverse ones do not |
| `F265` | Passes `F2650` twice (indices 13 and 28), going once round a circle between |
| `F647` | Two directions; direction 1 lists `F6479` twice in a row (indices 22 and 23) |
| `F65` | Two ordinary directions on opposite sides of a road |
| `F160` | Reaches `F9999`, north of the app's GPS box but inside the transport-data bounds |

## Ride-line network (`ride_geometry_test.dart`, `busrouter_routes_test.dart`): 6 services with lines

| Service/direction | Built for |
|---|---|
| `F10`/0 | 15 stops on a line bent between each pair: a 10-stop ride is drawn (3,641 m) |
| `F10`/1 | An open U-shaped line whose ride 0 → 1 would match only through the end-to-start join: never drawn |
| `F4`/0 | A closed loop starting at its terminal: 0 → 1 drawn on the line as given |
| `F115`/0 | A closed loop whose line starts between stops 0 and 1: 0 → 1 drawn only on the doubled line |
| `F46`/1 | A line stored backwards |
| `F11`/0 | `F1199` served at indices 6 and 17: each ride from it is drawn on its own pass (1,000 m and 300 m) |
| `F2B`/0 | A line 500 m away from every stop: not matched |

Mutation checks of 2026-11-06 (`docs/testing.md`): with doubling forced on open lines, never applied to closed
lines, the reversed variant removed, alighting before boarding allowed, or stops limited to the GPS box, the
matching tests fail.
