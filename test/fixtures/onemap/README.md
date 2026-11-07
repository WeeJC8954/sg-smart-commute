# OneMap search test data (synthetic)

Hand-made response bodies with the shape of OneMap's tokenless elastic search (`error`, `found`, `totalNumPages`,
`pageNum`, `results` of `SEARCHVAL`, `BLK_NO`, `ROAD_NAME`, `BUILDING`, `ADDRESS`, `POSTAL`, `X`, `Y`, `LATITUDE`,
`LONGITUDE`), built in `synthetic_onemap.dart` as JSON text, so the tests decode and parse whole bodies. Nothing is
copied from OneMap or any other source; only the field names and the shape are OneMap's:
- names end in "(fake)" and roads are "FAKE ROAD", "FAKE LANE", "FAKE TURN", "FAKE WALK";
- postal codes are six digits, as the app requires (`isPostalCode`), in sectors that do not exist in Singapore: `00`
  (`009901`, which also tests the leading zero) and `99` (`9900xx`, `990901`);
- the `error` text is invented (`syntheticTokenMessage`); the parser only checks that the field is there;
- positions follow one formula: case k, row r at latitude 1.20 + 0.02k + 0.001r and longitude 103.70 + 0.03k + 0.001r,
  inside the app's SG box (`SgBounds`), except one row set to latitude 1.50, north of it. `X`/`Y` are SVY21-shaped
  numbers from a similar formula; the app does not read them.

It replaced eight live captures of 2026-10-01 on 2026-11-07 (owner decisions A-4b and A-4c,
`docs/arrivelah-onemap-fixture-licensing-audit.md`), because OneMap's terms do not show that publishing them is
permitted. `.gitignore` refuses JSON in this folder.

| Body | Replaces | Built for |
|---|---|---|
| `postalLeadingZeroBody` | `postal-098585.json` | One building; postcode `009901` kept as a string with its leading zero; exact postal match in the repository |
| `hdbBlockBody` | `hdb-123-amk-ave-6.json` | A block as an address (`BUILDING` "NIL") with its postcode, then a home in the block with `POSTAL` "NIL" |
| `mrtStationBody` | `mrt-bishan.json` | A station with `POSTAL` "NIL" first, two coded platforms, an exit with an empty `BLK_NO`, and an LRT station (typed as a station too) |
| `streetBody` | `street-orchard-road.json` | The provider's order kept (not alphabetical); the same name twice (a road and a building), both kept; one row north of the SG box, dropped |
| `mallBody` | `mall-vivocity.json` | A mall and a station named after it, with different postcodes; the body most repository tests answer with |
| `tokenWithResultBody` | `postal-238801.json` | One result next to the `error` message: normal, not a failure |
| `postalNoMatchBody` | `postal-000000.json` | `error` and an empty list for a postal code that matches nothing |
| `blockNoMatchBody` | `hdb-blk-raw.json` | The same empty shape for a raw "Blk …" query |

Readers: `test/features/places/onemap_place_search_test.dart`, `test/features/places/place_search_config_test.dart`
and `test/core/retry_after_provider_test.dart`. Rows built inline in the first file (out-of-box and invalid
coordinates, a non-6-digit postcode, `BUILDING` that differs from `SEARCHVAL`, blank fields, malformed bodies, more
than 10 results) are synthetic too.

Mutation checks of 2026-11-07 (`docs/testing.md`): with the `error` field ignored (or treated as a failure next to
results), the SG-box check dropped, `BUILDING` or `ADDRESS` used as the name, "NIL" or blank values kept, latitude and
longitude swapped, duplicate names removed, the results sorted, LRT stations not typed as stations, the postcode turned
into a number, the exact-postcode filter dropped, or more than 10 results read, these tests fail. Four of these
(`BUILDING` as the name, blank values kept, results sorted, LRT not typed) passed the tests on the captured data; the
synthetic bodies and two inline tests now catch them.
