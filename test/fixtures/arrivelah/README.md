# ArriveLah test data (synthetic)

Hand-made bodies with the shapes of ArriveLah's stop responses (`docs/data-sources.md` § ArriveLah), built as JSON
text in `synthetic_arrivelah.dart`. The tests decode them with `jsonDecode` and parse them with `parseArriveLah`, as
the app does a live answer. Nothing is copied from ArriveLah, LTA or any other source; only the field names and
shapes are kept:
- stop codes, service numbers and `origin_code`/`destination_code` start with `F`. Real stop codes are five digits,
  and the parser takes the code as given, so no real stop can be meant;
- free text is marked fake: `operator` is `FAKE`, the error and instruction messages say "(fake)", and the
  instruction's URL is under `example.invalid`;
- every `time` is the tests' clock, `arriveLahClock` (2001-02-03 12:00:00 +08:00, a fake date), plus an offset,
  written with an explicit `+08:00`;
- `duration_ms` is computed 40 s before that clock, so it is stale and never agrees with `time`;
- positions are laid out by formula from the time (0.0001° per second); unmonitored buses have lat/lng 0.

It replaced captured responses and ArriveLah's own short bodies on 2026-11-07 (owner decisions A-4a and A-4c,
`docs/arrivelah-onemap-fixture-licensing-audit.md`). `.gitignore` refuses JSON in this folder.

## Bodies

| Body | Read by | Built for |
|---|---|---|
| `busyStopBody` (stop `F0301`) | parser, repository | Ten services in an unsorted provider order. `F10`: next, next2 and next3, monitored, `SEA`/`WAB`/`DD`, visit 1, with `subsequent` a copy of next2. `F100`: `SDA`/`SD`, then `LSD`/`BD`. `F2`: next3 null. `F2A`: only next. `F5`: three arrivals for the repository's selection check. `F7`: `feature` empty (not marked accessible), then an unmonitored bus. `F8`: next 20 s past the clock. `F9`: all unmonitored. `F11`: `LSD`/`BD`, `SDA`/`DD` |
| `loopStopBody` (stop `F7500`) | parser, domain | A loop terminal. `F29`: visit numbers 2, 2, 1 with monitored 1, 1, 0 (one departure when boarding at the terminal, at +5 min). `F30`: visits 2, 1, 2 (the departure is the middle bus, +4 min). `F31`: listed twice (both entries kept by the parser and merged by `nextArrivals`: +2, +6, +11 min). `F3`, `F4`: ordinary schedule-based services |
| `emptyStopBody` | parser, repository | `{"services": []}`: an unknown stop, not a failure |
| `errorBody` | parser, repository | `{"error": …, "statusCode": 500}`, sent with HTTP 200 → `BusArrivalUnavailable` |
| `noIdInstructionBody` | parser | The usage object sent without an `id`: no `services` → `InvalidApiResponse` |

Missing, odd and invalid fields (unknown codes, string `monitored` and `visit_number`, rolled-over or offset-less
times, malformed entries and slots) are built inline in `arrivelah_parser_test.dart`; the stale and year-9999 times in
`bus_arrival_domain_test.dart`.

Mutation checks of 2026-11-07 (`docs/testing.md`): with the ETA taken from `duration_ms`, times read without their
offset, the `error` field ignored, `monitored` or `visit_number` dropped, minutes rounded up, the second entry of a
listed-twice service dropped (in the parser or in `nextArrivals`), an object without `services` accepted as empty, or
`subsequent` read as a slot, the tests fail. Dropping the second entry in the parser survived the captured data;
`F31` closes that gap.
