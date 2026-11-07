# Source and licence of the NEA test fixtures

`two-hr-forecast.json`, `uv.json`, `pm25.json` and `psi.json` in this folder are unmodified responses of the
data.gov.sg real-time API (`https://api-open.data.gov.sg/v2/real-time/api/…`), captured once with `curl` on
1 October 2026 (`docs/testing.md`, the 2026-10-01 M1 row). The National Environment Agency (NEA) publishes the
data. The NEA parser tests need real payloads, so the files stay (`docs/captured-data-inventory.md`, C-1).

Notice:

> Contains information from the 2-hour Weather Forecast, UV Index, PM2.5 and PSI datasets of the National
> Environment Agency, accessed on 1 October 2026 from data.gov.sg, which is made available under the terms of the
> Singapore Open Data Licence version 1.0, https://data.gov.sg/open-data-licence

The same notice covers the NEA positions copied into `integration_test/fakes/fake_environment_repository.dart` (the
five region label locations and three forecast-area positions); its readings and forecasts are invented.

This notice is for these NEA files only. The other test data has its own source and terms, or none:
- `busrouter/`, `onemap/`, `arrivelah/`: synthetic, written for this project (each folder's `README.md`);
- `integration_test/fakes/`: synthetic places and stops (`integration_test/fakes/README_places.md`).

No other licence is implied for them: the Singapore Open Data Licence is not assumed to cover OneMap, busrouter or
ArriveLah data.
