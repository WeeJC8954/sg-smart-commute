# Assumptions

Documented values to review once working test journeys exist. See guide v2.1 §0.1.

| Area | Assumption | Value | Source / note |
|---|---|---|---|
| SG bounds | Valid GPS/geocode coordinates | lat 1.15–1.48, lng 103.60–104.10 | Bounding box. It includes some sea and Johor Strait. That is accepted |
| Location timeout | Acquisition timeout, started after permission is granted | 10 s | Guide §5.1 |
| Walking estimate | `ceil(haversine × 1.3 / 80)` minutes | detour 1.3, 80 m/min | Labelled "(est.)". Ignores barriers, bridges, expressways |
| Bus candidates | Origin/destination stop radius | 400 m, widened once to 800 m | Guide §9.2 |
| Bus scoring | `walkO_min + walkD_min + 1.5 × stops`; tie-break by fewer stops, then service no. | weights as shown | Placeholder weights |
| Journey scope | Direct bus only, zero transfers | — | Plus MRT as information only (station, code/line if reliable, est. walk) |
| Walk instead | Suggest walking when origin and destination are close | ≤ 300 m | Guide §9.2 step 9 |
| Staleness | Forecast / PM2.5 / PSI / UV stale thresholds | 3 h / 2 h / 2 h / 2 h (daytime) | Starting values, not official cadences |
| Bus arrival | Manual refresh; cache | ≤ 20 s | Auto-polling deferred |
| Caching | Session-only, in memory | — | Offline cold start → *Network unavailable* + Retry |
| data.gov.sg | Anonymous rate limit | 6 calls / 10 s | Official guide, 2026-10-01 |
| Place search | Strip `Blk`/`Block`, trim, collapse whitespace before querying | — | Milestone 0 eval: `Blk 123 …` failed on OneMap/Nominatim |
| Place search | 6-digit postal-code queries accept only an exact postcode match | — | Photon is fuzzy (`640512` → `640517`) |
| Time | Display at a fixed +08:00 offset; negative ages shown as "just now" | — | Singapore has no DST |
| M1 manual origin | Until place search exists (M2), the manual origin is a choice of one of the NEA 2-hr forecast areas (~47 names + `label_location`, from the live payload). The origin is that area's label location, provenance `manual`. The guide's §5.3 search field is M2 work | — | Guide §5.3 needs place search, which is M2. Simplest option consistent with §5.3 ("user explicitly selects one"). If the forecast fetch fails, the picker shows Retry |
| Late fix | A valid late fix populates the origin only if the user has neither selected an area nor started typing (focus or input in the area field). Otherwise it is offered as a "Use my current location" chip. Out-of-SG late fixes and late errors are ignored. A fix (in time or late) from any attempt, including one started by "Try location again", never replaces a manual origin: it is only offered. Only tapping "Use my current location" switches a manual origin back to GPS. With a manual origin set, "Try location again" runs in the background, and its denial, timeout, error or out-of-SG result changes nothing. Each attempt has an id: a superseded attempt's fix, error or timeout is dropped and never counts as the current attempt's result | — | Guide §5.4. Reviewer rule on PR #3 |
| Location errors | Any acquisition error not covered by §13 maps to `LocationUnavailable` (added to the §13 list) | — | e.g. a geolocator `PositionUpdateException` |
| Web location | Browsers report the service as always enabled; a blocked browser permission surfaces as "denied". No "Open settings" action on Web | — | geolocator_web behaviour |
| UV at night | Night = before 07:00 or from 20:00 SGT. At night the last reading is shown with its time under "UV not measured at night" and is never marked stale | 07:00–20:00 | Readings observed 07:00–19:00 on 2026-10-01 |
| Forecast staleness | Measured from the payload `update_timestamp` | 3 h | Guide §6.3 |
| PM2.5 / PSI staleness | Measured from the reading `timestamp` (the hour) | 2 h | Guide §6.3 |
| Dashboard refresh | Manual refresh-all (4 calls) is ignored for 15 s after the previous one. Retry is per dataset (1 call). Riverpod 3's automatic provider retry is disabled. There is no automatic polling | 15 s | data.gov.sg anonymous limit 6 calls / 10 s |
| Band tables | 24-hr PSI: Good 0–50, Moderate 51–100, Unhealthy 101–200, Very unhealthy 201–300, Hazardous > 300. 1-hr PM2.5 (µg/m³): Normal 0–55, Elevated 56–150, High 151–250, Very high ≥ 251. UV: Low 0–2, Moderate 3–5, High 6–7, Very high 8–10, Extreme ≥ 11 | — | Sources in `data-sources.md` (checked 2026-10-01) |
