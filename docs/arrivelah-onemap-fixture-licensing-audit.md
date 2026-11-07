# ArriveLah and OneMap Fixture Licensing Audit (owner ruling A-4)

**Status:** audit, 2026-11-06. Owner rulings: A-4b approved, with A-4c "replace them too": the eight OneMap files are
removed from the tree and replaced by synthetic bodies (`test/fixtures/onemap/README.md`, branch
`test/synthetic-onemap-fixtures`, 2026-11-07); their history stays. ArriveLah (A-4a) is handled separately. The rest of
this document is the audit as written for review; it changes no fixture, test or history, and no third party is
contacted. It is not legal advice: a conclusion that depends on reading terms is tagged **[A]**.

**Tags:** **[C]** confirmed (read from the files, the sources or Git, or measured); **[A]** assumption or reading not
verified; **[P]** proposal, needs approval.

**Related:** the busrouter audit `docs/busrouter-fixture-licensing-audit.md`. The runtime use of these providers is in
`docs/runtime-data-rights-assessment.md`.

## 1. Summary

- **ArriveLah [C/A].** Two of the five files are captured arrival records: LTA DataMall Bus Arrival data relayed by
  ArriveLah, a third-party proxy with no data licence. The other three are tiny: two error or instruction messages and
  one empty list. DataMall datasets are under the Singapore Open Data Licence (SODL), which permits copying and
  distribution with a conspicuous attribution notice and a link to the licence.
  - The fixtures carry no such notice.
  - Whether the SODL covers data obtained through an unlicensed proxy, rather than from DataMall itself, is not
    established [A].
- **OneMap [C/A].** Six of the eight files are captured search results with addresses, postal codes and coordinates;
  the other two hold only an error message. OneMap's terms forbid "store, … distribute, … reproduce, publish" of SLA
  Data except as clause 3(a) expressly permits, and 3(a) does not expressly list distribution. So committing captured
  results is not shown to be permitted.
  - The captures were also made without registration, while the terms require it for building a web application on
    the API.
- **Recommendation [P]:** replace both sets with hand-made synthetic responses that keep every tested shape and edge
  case, as A-1 did for busrouter, each in its own PR.
- **Tests [C]:** a deletion trial in a temporary worktree, leaving the real fixtures untouched, gave 3 failures among
  the 32 tests of the 3 ArriveLah test files, and 18 failures among the 37 tests of the 2 OneMap test files. A failure
  in a file-level variable counts once, so these are lower bounds.

## 2. Inventory [C]

Added in `bc1c0a9` (2026-10-02, PR #8, ArriveLah) and `654e1cb` (2026-10-01, PR #5, OneMap). Neither set has been
changed since.

| File | Bytes | Content | Read by |
|---|---|---|---|
| `test/fixtures/arrivelah/stop_03019.json` | 8,798 | Live arrivals at one stop: service, operator, next/subsequent times, bus positions, load, feature, type, origin and destination codes | `arrivelah_parser_test.dart`, `bus_arrival_repository_test.dart` |
| `test/fixtures/arrivelah/stop_75009_loop.json` | 19,856 | The same at a loop terminal | `arrivelah_parser_test.dart`, `bus_arrival_domain_test.dart` |
| `test/fixtures/arrivelah/stop_99999_empty.json` | 15 | `{"services":[]}` | `arrivelah_parser_test.dart` |
| `test/fixtures/arrivelah/error_body.json` | 57 | ArriveLah's own error message | `arrivelah_parser_test.dart` |
| `test/fixtures/arrivelah/no_id_instruction.json` | 241 | ArriveLah's own usage message with its project URL | `arrivelah_parser_test.dart` |
| `test/fixtures/onemap/mall-vivocity.json`, `mrt-bishan.json`, `postal-098585.json`, `postal-238801.json`, `hdb-123-amk-ave-6.json`, `street-orchard-road.json` | 568–3,827 each | Search results: SEARCHVAL, block, road, building, full address, postal code, SVY21 X/Y, latitude/longitude, with the "Authentication token missing" message | `onemap_place_search_test.dart`, `place_search_config_test.dart` (VivoCity) |
| `test/fixtures/onemap/postal-000000.json`, `hdb-blk-raw.json` | 184 each | The error message and an empty result list | `onemap_place_search_test.dart` |

## 3. Sources and terms

| Source | Terms | Reading |
|---|---|---|
| **LTA DataMall** (origin of ArriveLah's arrival records) | API terms of service (updated 9 July 2025), clause 1: "Use of the datasets is governed by the Singapore Open Data Licence." Clause 10(b): credentials kept "secure and confidential" [C] | The licence attaches to the datasets. The credential duty binds the key holder, here ArriveLah's operator [A] |
| **Singapore Open Data Licence v1.0** | Grants "a worldwide, perpetual, royalty-free, non-exclusive licence to Use the datasets", and the user may "use, access, download, copy, distribute, transmit, modify and adapt" them. It requires "a conspicuous notice acknowledging the source of the datasets" with "a link to the most recent version of this Licence". It excludes personal data and "third party rights that the Agency is not authorised to license", and "does not grant any rights to Downstream Sub-Licensees" [C] | Distribution of DataMall data is permitted with the notice. Whether a copy obtained through a proxy counts as a dataset "offered for use under the terms of this Licence" is not established [A] |
| **ArriveLah** (`cheeaun/arrivelah`) | No licence file (`license: null`). README: "This is like a proxy to LTA's DataMall Bus Arrival API", and "MIT. Data is copyrighted by LTA." [C] | Grants nothing for the data. Its own error and usage texts come from MIT-licensed code; they are short and functional [A] |
| **OneMap** (SLA) | Terms of use, read 2026-11-06 (no date on the page). Clause 3(a) grants "a non-transferable, non-exclusive, royalty-free, revocable licence to access, view, download, print or otherwise use the SLA Data and the SLA Material for any usage, subject to …". Clause 3(b): "Except as expressly permitted in Clause 3(a) above, you shall not: store, download, archive, print, distribute, publicly display, reproduce, publish, post, communicate, copy, modify, …". Preamble: to "start building your own Web Application(s) using the API and the Data, then you will need to complete the online registration process and … accept the terms of the Developer Agreement" [C] | 3(a)'s "otherwise use … for any usage" sits next to 3(b)'s ban on storing, distributing and publishing. Committing captured results to a public repository is not shown to be permitted [A] |

## 4. Determinations

| Files | Determination |
|---|---|
| ArriveLah `stop_03019.json`, `stop_75009_loop.json` | **Not established [A].** It may be permitted under the SODL with a notice, if the licence covers proxy-obtained copies. The fixtures carry no notice |
| ArriveLah `error_body.json`, `no_id_instruction.json` | **Low concern [A]:** the proxy's own short messages, from MIT code |
| ArriveLah `stop_99999_empty.json` | **No content** [C] |
| OneMap six result files | **Not established [A]:** SLA Data captured and published, against 3(b) as read |
| OneMap `postal-000000.json`, `hdb-blk-raw.json` | **Low concern [A]:** an error message and an empty list |

## 5. Impact and recommended replacements [P]

| Option | What | Assessment |
|---|---|---|
| **R1 (recommended)** | Hand-made synthetic responses with the same field names and shapes: fake stop codes and service numbers, times relative to a fixed clock, loads, features and types from the documented enums; fake addresses, postal codes and coordinates for OneMap. Each case is kept: monitored and unmonitored times, a loop terminal, the empty list, the error body, the token message, missing or odd fields. Each replaced test is moved one-for-one, so the 959 / 32 baseline holds | Removes the question for the files; done like A-1, in its own PR per provider |
| R2 | Keep the two ArriveLah captures and add the SODL notice and licence link in a provenance file | Rests on the proxy question [A]; does not help OneMap |
| R3 | Ask LTA or SLA for permission | A third-party request for the owner to make; not done |

**History [C].** The files stay in `main`'s history and in PRs #5 and #8, as the busrouter fixtures do (A-2 and A-3,
deferred).

## 6. Decisions requiring owner approval

| ID | Decision | Recommendation |
|---|---|---|
| A-4a | Replace the ArriveLah fixtures with synthetic responses (R1) | Approve, in its own PR |
| A-4b | Replace the OneMap fixtures with synthetic responses (R1) | Approve, in its own PR |
| A-4c | Keep the low-concern files (error and empty bodies) as they are, or replace them too | Replace them too, for one consistent rule: no captured third-party responses in `test/fixtures/` (the NEA files are data.gov.sg data under the SODL, outside this audit) |
