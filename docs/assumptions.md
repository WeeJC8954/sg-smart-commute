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
