# busrouter Fixture Licensing Audit (owner ruling G2-11)

**Status:** audit, 2026-11-06. Owner rulings of 2026-11-06: A-1 approved, and done in its own PR (the five files are
removed from the tree; their history stays); A-2 and A-3 deferred; A-4 approved (a separate audit); A-5, a runtime
data-rights assessment, required before E5 Gate 3. The rest of this document is the audit as written for review. It changes no fixture, test or history. It does not contact any
third party. It is not legal advice: where a conclusion depends on reading terms, it is tagged **[A]**.

**Why:** in E5 Gate 2, the redistribution rights of a full busrouter snapshot could not be established
(`docs/e5-gate2-implementation-plan.md` §2.8). The owner asked for the same check on the busrouter fixtures committed
since M3.

**Tags:** **[C]** confirmed (read from the files, the sources or Git, or measured); **[A]** assumption or reading not
verified; **[P]** proposal, needs approval.

## 1. Summary

- **[C]** Six files under `test/fixtures/busrouter/` were committed on 2026-10-02 and 2026-10-03. Five of them are
  unmodified subsets of busrouter's published files; the sixth is a provenance note.
- **[C]** Almost all of their content traces back to lta.gov.sg. LTA's website terms forbid reproducing or distributing
  that content without LTA's prior written permission. busrouter and sgbusdata grant no licence.
- **[C/A]** Redistribution rights cannot be established for any of the five data files. Only one field, the road
  name, comes from a licensed source: LTA DataMall under the Singapore Open Data Licence.
- **[C]** In a deletion trial, 32 of the 70 tests in the three files that read the fixtures failed without them. No
  other test uses them, and the E5 benchmark does not use them.
- **[P]** The recommendation is to replace them with synthetic fixtures that keep every tested behaviour (§6). The test
  count stays at or above the 959 / 32 baseline.
- **[C]** The files remain in `main`'s history and in the refs of the PRs that added them (#6, #42). Removing them from
  history would need the owner's approval; removing them from GitHub's PR refs and cached views would need GitHub
  Support (§7).

## 2. Inventory [C]

| File | Bytes | Added (commit, date, PR) | Content |
|---|---|---|---|
| `test/fixtures/busrouter/stops.subset.json` | 22,490 | `0247bc2`, 2026-10-02, #6 | Stops `{code: [lng, lat, name, road]}` used by six services, plus 46239 Larkin Ter (across the Causeway) |
| `test/fixtures/busrouter/services.subset.json` | 3,500 | `0247bc2`, 2026-10-02, #6 | Services 4 (loop), 184 (one direction), 265 (a stop twice), 647 (a stop twice in a row), 65 and 160: name and ordered stop lists |
| `test/fixtures/busrouter/geometry/stops.json` | 24,277 | `997fd83`, 2026-10-03, #42 | Stops of services 10, 46, 4, 11, 2B and 115 |
| `test/fixtures/busrouter/geometry/services.json` | 4,909 | `997fd83`, 2026-10-03, #42 | Those services' stop lists |
| `test/fixtures/busrouter/geometry/routes.json` | 2,532 | `997fd83`, 2026-10-03, #42 | Their encoded route polylines |
| `test/fixtures/busrouter/geometry/PROVENANCE.md` | 1,430 | `997fd83`, 2026-10-03, #42 | Written for this project: URLs, capture time, planned cases (no third-party data) |

Related files checked:
- **`integration_test/fakes/fake_bus_network.dart`:** synthetic. Its stops are named "(fake)", its service numbers start
  with F, and its coordinates are hand-picked. Not affected.
- **`docs/probe-output/route-geometry.txt`:** aggregate statistics of a matcher run (counts and percentages) and one
  ride length. These are derived facts with no records copied [A].
- **Tests that quote a few real stop codes, names or service numbers** (for example `busrouter_test.dart`'s header
  comment) quote short factual excerpts, not the data set [A].
- **Not busrouter, and not audited here:** `test/fixtures/arrivelah/` (ArriveLah, a third-party proxy of DataMall
  arrivals), `test/fixtures/onemap/` (OneMap search responses) and the NEA fixtures (data.gov.sg, Singapore Open Data
  Licence). The ArriveLah and OneMap captures raise a similar question; see the decision A-4 in §8.

## 3. Original sources, by field [C]

From sgbusdata's scripts (`fetch-bus-stops.js`, `fetch-bus-services.js`, `fetch-bus-services-routes.js`,
`patch-bus-stop-names.js`, `patch-missing-routes.js`, `generate-data.js`; read 2026-11-06):

| Field | Origin | Class |
|---|---|---|
| Stop code, position, name | `https://www.lta.gov.sg/map/busService/bus_stops.xml` | LTA website |
| Stop name corrections | SimplyGo e-guide (`svc.simplygo.com.sg/eservice/eguide/bscode_idx.php`) | Other (TransitLink) |
| Stop road name | DataMall `BusStops` API | LTA DataMall |
| Service list and type | `https://www.lta.gov.sg/map/busService/bus_services.xml` | LTA website |
| Ordered stops per direction | `.../bus_route_xml/<service>.xml` | LTA website |
| Route geometry (polylines) | `.../bus_route_kml/<service>-<n>.kml` | LTA website |
| Missing or multi-line routes | OneMap and Citymapper responses (`patch-missing-routes.js`, `patch-multiline-routes.js`) | Other (SLA OneMap; Citymapper) |
| Assembly | `cheeaun/sgbusdata` scripts, published at `data.busrouter.sg` | Community project |

## 4. Licences and redistribution conditions

| Source | Terms | Redistribution |
|---|---|---|
| LTA website content | Terms of use, updated 3 December 2021: contents "shall not be reproduced, republished, uploaded, posted, transmitted, communicated or otherwise distributed in any way, without the prior written permission of LTA"; using them requires a written request; no stated exception for personal or non-commercial use [C] | **Not permitted without LTA's written permission** [C] |
| LTA DataMall | API terms of service: the datasets are under the Singapore Open Data Licence [C] | Permitted with the licence's attribution, for data obtained through DataMall [A: the licence text was not re-read in this audit] |
| `cheeaun/busrouter-sg` | README: data "copyrighted by the Land Transport Authority"; "Data © LTA © OneMap © OSM contributors. Everything else: MIT"; no licence file [C] | Grants nothing for the data [C] |
| `cheeaun/sgbusdata` | No licence, and the README states no data terms [C] | Grants nothing [C] |
| SimplyGo (name corrections) | Not checked | Not established [A] |
| OneMap (route patches) | Terms read in P2-M0 (`docs/map-feasibility.md` §4.2): a revocable licence to view and use [C] | Not shown to cover redistribution [A] |
| Citymapper (route patches) | Not checked | Not established [A] |

Attribution alone does not grant permission (owner's instruction, and the LTA terms ask for permission, not attribution).

## 5. Files whose redistribution rights cannot be established

| File | Determination |
|---|---|
| `stops.subset.json`, `geometry/stops.json` | **Cannot be established** [C]: codes, positions and names from lta.gov.sg; only the road names are DataMall data |
| `services.subset.json`, `geometry/services.json` | **Cannot be established** [C]: stop lists from lta.gov.sg (the "name" field is busrouter's composition of LTA stop names) |
| `geometry/routes.json` | **Cannot be established** [C]: polylines from lta.gov.sg KML, possibly patched from OneMap or Citymapper |
| `geometry/PROVENANCE.md` | Project-authored; no issue [C] |

## 6. Impact and recommended replacements

### 6.1 Impact on tests [C]

Deletion trial on 2026-11-06: the busrouter fixture folder was moved out of the working tree, and the three test files
that read it were run, then the folder was restored and `git status` checked clean.
- **Result:** the runner reported 39 passed and 32 failed. A text scan counts 70 tests in the three files; the extra
  count was not investigated.
- `busrouter_test.dart` (24 tests): parser drops, lng/lat order, loops, repeated stops, the out-of-bounds stop, and
  the planner on real routes.
- `busrouter_routes_test.dart` (15): the `routes.min.json` parser and repository.
- `ride_geometry_test.dart` (31): the real-ride cases, such as Bus 10 03019 → 14141 drawn at 4,426 m, the 4/0 loop,
  46/1 reversed, the repeated stop and 2B/0 unmatched.
- **Not used** by any other test, by `integration_test/`, or by the E5 benchmark, which fetches its own input. Removing
  the files without replacements would drop the 959 baseline by 32.

### 6.2 Options

| Option | What | Assessment |
|---|---|---|
| **S1 (recommended) [P]** | Hand-written synthetic fixtures with the same schemas, in a separate change. Invented stop codes and names (marked fake, as in `fake_bus_network.dart`). Each tested shape is built on purpose: a loop, a one-direction service, a stop repeated, a stop repeated twice in a row, a stop outside SG bounds, invalid entries. Polylines are encoded from synthetic coordinates by a small test helper, and the cases are rebuilt geometrically: as given, doubled closed loop, reversed, repeated stop, unmatched, malformed. Each of the 32 tests is replaced one-for-one, or rewritten against the synthetic data with the same assertion intent; the count stays ≥ 959 | Removes the rights question for future commits. Loses the "real data" smoke character of about 5 tests, such as the 4,426 m Bus 10 ride, which the manual smoke checks and probes in `docs/testing.md` already cover. `tool/capture_route_geometry_fixtures.dart` would then be retired, or kept only as a local-only, uncommitted capture |
| S2 | Ask LTA for written permission for test fixtures | The only route to keeping real data. A third-party request the owner must make; not done |
| S3 | Keep the files as they are | Not recommended: the rights cannot be established |

**Benchmark reproducibility.** None of these options affects it: the benchmark never read these fixtures.

## 7. Historical Git exposure (unresolved) [C]

| What | Where it remains | What would remove it |
|---|---|---|
| The five fixture data files | `main`'s history since `0247bc2` (2026-10-02) and `997fd83` (2026-10-03); PRs #6 and #42; every clone. The repository is public and has 0 forks (checked 2026-11-06) | A history rewrite (needs the owner's explicit approval, against guide §23's no-rewrite rule), then GitHub Support to remove cached views and PR references. GitHub's guide says that after a rewrite, data stays reachable in clones, in forks, "directly via their SHA-1 hashes in cached views on GitHub" and "through any pull requests that reference them"; Support removes the last two only once everything else is cleaned |
| The E5 snapshot (commit `b1715b6`; blobs `4238dc62…` stops, `5f7f58b3…` services, `e1355c69…` provenance) | Branch `docs/e5-gate2-plan` and PR #90 (closed unmerged). Committed 2026-11-06 12:45 UTC and pushed minutes later; removed from the branch tip by `6792956` (committed 13:14 UTC). Never in `main` | Deleting the branch (owner action; this session's permission check refuses it). The PR's ref would still keep the commit reachable; only GitHub Support can purge it |

- **Closing PR #90 does not remove the hosted data** [C]. Neither would deleting the branch.
- **Context, not a remedy [C].** The same bytes are published openly by `data.busrouter.sg` and `cheeaun/sgbusdata`, so
  the exposure adds no new availability. It is still a copy this project has no shown right to host.
- **Whether to contact GitHub Support** is the owner's decision (A-3). Under the guide quoted above, Support would act
  on PR references only after the history is rewritten and no fork holds the commits.

## 8. The benchmark's download

The E5 benchmark's `fetch_snapshot.sh` downloads the same LTA-derived files from GitHub into a local, git-ignored
folder.
- **[C]** Nothing is redistributed: the files are fetched for local use only.
- **[A]** But LTA's terms say that to "use the Contents of this website or any part thereof, the user must seek
  permission in writing". The terms do not say how far that reaches content obtained through a third party.
- **Decision.** Because the answer is uncertain, under the owner's G2-11 instruction **the download is optional**. It
  is not part of CI, not a required developer step, and not a Gate 3 pass condition. It runs only if the owner
  approves.

The same clause bears on the app itself, which loads busrouter data at runtime for every bus journey. This audit does
not assess that use; it is listed as decision A-5 so it is not lost.

## 9. Decisions requiring owner approval

| ID | Decision | Recommendation |
|---|---|---|
| A-1 | Replace the five fixture data files with synthetic fixtures (S1), in a separate change after E5 Gate 2 | Approve S1 |
| A-2 | Rewrite history to remove the fixture files from `main` and the snapshot from `docs/e5-gate2-plan`, or leave history as it is and stop adding such data | Leave history as it is unless legal advice says otherwise: a rewrite breaks every clone and PR reference, and cannot reach PR refs without Support |
| A-3 | Contact GitHub Support about PR #90's and PRs #6 / #42's references | Not now; only together with A-2 |
| A-4 | Audit the ArriveLah and OneMap fixtures the same way | Approve, as a separate small audit |
| A-5 | Whether the app's runtime use of busrouter data, and the optional benchmark download, need LTA's written permission | Owner's call, possibly with advice; ask LTA only with the owner's approval |
