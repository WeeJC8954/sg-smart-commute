# Runtime Data-Rights Assessment: busrouter (owner ruling A-5)

**Status:** assessment only, 2026-11-06, for owner review before E5 Gate 3. No code, asset or history is changed, and
no third party (LTA, busrouter's maintainer or anyone else) is contacted. **It is not legal advice:** the legal
position is uncertain (§5), and readings of terms are tagged **[A]**.

**Tags:** **[C]** confirmed (read from code, terms or Git, or measured); **[A]** assumption or reading not verified;
**[P]** proposal, needs approval.

**Owner's instruction:** public access, CORS headers, and personal or non-commercial use do not by themselves grant
permission.

## 1. Summary

- **[C]** The app loads three busrouter files at runtime (stops, services, route lines) and asks ArriveLah, hosted
  under busrouter's domain, for arrivals. It bundles no busrouter data. After A-1 (PR #92), the repository tree holds
  none either; history still does.
- **[C]** Most of the static data is LTA website content (lta.gov.sg XML and KML files) compiled by `cheeaun/sgbusdata`.
  LTA's website terms require written permission to reproduce or distribute its contents, and also say: "To use the
  Contents of this website or any part thereof, the user must seek permission in writing". busrouter grants no
  licence.
- **[A]** So the app's runtime use of the static data is **not shown to be permitted**.
  - The open question is whether LTA's "use" clause reaches content obtained through a third party, and how far
    factual data (stop codes, positions, stop orders) is protected at all.
  - That needs authoritative advice or LTA's answer; reading the terms cannot settle it.
- **[C/A]** Arrivals and road names come from LTA DataMall, whose datasets are under the Singapore Open Data Licence
  (SODL). That licence permits use with a conspicuous notice and a link to the licence.
  - The app's attribution, "Arrivals: ArriveLah (LTA DataMall)", lacks the licence link and notice.
  - Whether proxy-obtained data is covered is not established.
- **[P]** Options (§6): ask LTA in writing (the terms' own route); take legal advice; or move to SODL-licensed DataMall
  data. The last could be a bundled asset built offline with the developer's own key (as the MRT asset is built from
  data.gov.sg), or busrouter's re-hosted DataMall copies. Each move changes F7 and ADR-001's scope and needs separate
  approval. E5's design does not depend on the source, since it consumes `BusNetwork`, but it inherits the question
  because it uses the same data.

## 2. What the app uses at runtime [C]

| Endpoint (`app_config.dart`) | When | What reaches the user | Attribution shown |
|---|---|---|---|
| `https://data.busrouter.sg/v1/stops.min.json` | First bus journey of a session | Stop names, codes and positions (card steps, map markers) | "Bus data: busrouter.sg (data © LTA)" (app footer) |
| `https://data.busrouter.sg/v1/services.min.json` | Same | Services and their stop order (the planner; "toward" names) | Same |
| `https://data.busrouter.sg/v1/routes.min.json` | Open map with a bus ride | The ride's line, drawn on the map | Same |
| `https://arrivelah2.busrouter.sg/?id=<stop>` | Per displayed boarding stop | Next arrival times | "Arrivals: ArriveLah (LTA DataMall)" (footer, and under the arrivals) |

Bundled assets: `assets/mrt_stations.json` (data.gov.sg, SODL, credited in-app) and the app icon. No busrouter data
is bundled [C].

## 3. Provenance chain [C]

| Data | Chain | Origin class |
|---|---|---|
| Stop code, position, name | lta.gov.sg `bus_stops.xml` → sgbusdata (names corrected from SimplyGo's e-guide) → `data.busrouter.sg` | LTA website (+ SimplyGo) |
| Stop road name | DataMall `BusStops` → sgbusdata → `data.busrouter.sg` | LTA DataMall |
| Services, stop order per direction | lta.gov.sg `bus_services.xml` and `bus_route_xml/*.xml` → sgbusdata (gaps patched from OneMap, Citymapper) → `data.busrouter.sg` | LTA website (+ others) |
| Route lines | lta.gov.sg `bus_route_kml/*.kml` → sgbusdata (patched from OneMap, Citymapper) → `data.busrouter.sg` | LTA website (+ others) |
| Arrivals | DataMall Bus Arrival API (the operator's key) → ArriveLah (`arrivelah2.busrouter.sg`) | LTA DataMall |

Sources: sgbusdata's `fetch-*.js`, `patch-*.js` and `generate-data.js`, and the busrouter-sg and arrivelah READMEs, all
read 2026-11-06.

## 4. Terms [C]

| Terms | Relevant text |
|---|---|
| **LTA website terms of use** (last updated 3 December 2021) | "Except as otherwise provided, the Contents of this website shall not be reproduced, republished, uploaded, posted, transmitted, communicated or otherwise distributed in any way, without the prior written permission of LTA." "To use the Contents of this website or any part thereof, the user must seek permission in writing, stating the Contents for use; intent of use; manner of use; time frame of use and identity of the user." "Modification of any of the Contents or use of the Contents for any other purpose will be a violation of LTA's copyright and other intellectual property rights." "Except as set forth below, caching and links to, and the framing of this website or any of the Contents are prohibited." |
| **LTA DataMall API terms of service** (updated 9 July 2025) | Clause 1: "Use of the datasets is governed by the Singapore Open Data Licence." Clause 10(b): credentials kept secure and confidential |
| **Singapore Open Data Licence v1.0** | "worldwide, perpetual, royalty-free, non-exclusive licence to Use the datasets": "use, access, download, copy, distribute, transmit, modify and adapt". It requires "a conspicuous notice acknowledging the source of the datasets" and "a link to the most recent version of this Licence"; excludes third-party rights the agency cannot license; grants nothing to Downstream Sub-Licensees |
| **busrouter-sg** | README: the data is "mostly _scraped_ from https://www.lta.gov.sg/, which means they are copyrighted by the Land Transport Authority"; "Data © LTA © OneMap © OSM contributors. Everything else: MIT". No licence file |
| **sgbusdata** | No licence; no data terms |
| **ArriveLah** | README: "MIT. Data is copyrighted by LTA." No licence file |

## 5. Assessment by the four distinctions

### 5.1 Direct runtime access to busrouter endpoints

- **LTA website content (stops, services, route lines).**
  - Each user's app downloads busrouter's copy and shows parts of it. The project does not host or redistribute it.
  - But LTA's terms make *use* of its contents subject to written permission. Neither busrouter nor sgbusdata claims
    to hold that permission or to pass on any licence.
  - **Not shown to be permitted [A].**
  - The uncertainty has two parts: whether the "use" clause binds someone who never visits lta.gov.sg and receives
    the content from a third party, and how far stop codes, positions and stop orders are protectable as a
    compilation. Both are legal questions this assessment cannot settle.
  - CORS `*`, no key and a public URL do not change this.
- **DataMall content (road names, arrivals).** Under the SODL, use is permitted with the notice and link [C].
  - **Gap 1 [C]:** the app's credits name LTA DataMall but give no SODL notice or link.
    **Update 2026-11-07 (A-5b):** the footer now shows the notice and the link, and the arrivals credit names the
    licence. This closes Gap 1 only; Gap 2 and ArriveLah's own terms are unchanged.
  - **Gap 2 [A]:** whether a copy relayed by a proxy (ArriveLah) or re-hosted (sgbusdata) is a dataset "offered for use
    under the terms of this Licence" is not established. The licence attaches to the data, which suggests yes, but
    that is unconfirmed.

### 5.2 Redistribution in the repository or app package

- **App package [C]:** no busrouter data is bundled, so there is no redistribution through the app.
- **Repository [C]:**
  - after PR #92 (A-1), no busrouter data is in the tree;
  - the captured files remain in history since 2026-10-02, and the E5 snapshot in PR #90's refs (A-2 and A-3,
    deferred);
  - the ArriveLah captures (DataMall data, no notice) and the OneMap captures are pending A-4
    (`docs/arrivelah-onemap-fixture-licensing-audit.md`).

### 5.3 Local development and benchmark downloads

- **[C]** These are local copies for developer use, not redistributed: the E5 benchmark's optional
  `fetch_snapshot.sh`, plus `tool/journey_smoke.dart`, `tool/route_geometry_probe.dart`, `tool/probe_apis.sh`,
  `tool/probe_map.sh` and `tool/api_probe_app.dart`, which call busrouter live when run by hand.
- **[A]** The same "use" question as §5.1 applies.
- **[P]** Treat all of them like the benchmark download: optional, never CI, and run only if the owner accepts the
  position. Today only the benchmark's README says so.

### 5.4 LTA website content against DataMall and other sources

| Class | Licence | Runtime status |
|---|---|---|
| LTA website (stops, names, positions, services, stop order, route lines) | None granted; written permission required | Not shown permitted [A] |
| LTA DataMall (road names, arrivals) | SODL v1.0 | Permitted with notice and link [C], subject to the proxy question [A]; notice missing [C] |
| SimplyGo (name corrections) | Not checked | Not established [A] |
| OneMap, Citymapper (route patches) | OneMap terms; Citymapper not checked | Not established [A] |

## 6. Options

| ID | Option | What it involves | Assessment |
|---|---|---|---|
| O1 | **Ask LTA in writing**, as its terms prescribe: contents, intent, manner, time frame, identity | A letter from the owner (not sent; needs approval) | The only route to authoritative permission for the website-derived data. LTA may refuse without reasons |
| O2 | **Legal advice** on the "use" clause for third-party copies and on protection of factual compilations | Owner's decision | Settles the uncertainty without changing the app |
| O3 | **Ask busrouter's maintainer** whether they hold LTA permission | A message from the owner (not sent) | They cannot grant LTA's rights; this only clarifies provenance |
| O4 | **Bundled SODL asset built offline from DataMall** (`BusStops`, `BusRoutes`) with the developer's own AccountKey, used only locally and never committed or shipped, like `tool/build_mrt_asset.dart` | A new dev tool, a bundled asset, attribution with an SODL notice and link | Licensed for distribution with notice [C]. Needs a DataMall account. Freshness depends on rebuilds. **No route lines** (DataMall has none), so the map shows markers and a note. **Conflicts with `CLAUDE.md`'s hard constraint as written**, which puts LTA DataMall out of scope; even an offline, never-shipped key would need the owner to amend it. Also changes F7 and the data-source ADR |
| O5 | **busrouter's re-hosted DataMall copies at runtime** (`raw/bus-stops.datamall.json`, 841,891 B; `raw/bus-routes.datamall.json`, 7,629,059 B, over the 4 MiB cap; CORS `*`) | A parser for the DataMall shape, and a larger download or cap | Data under the SODL, subject to the proxy question [A]. These are undocumented intermediate files that could disappear. No route lines. Not recommended over O4 |
| O6 | **Accept the risk** for this personal project, documented, and stop at that | Owner's decision | Keeps today's app. The question stays open; it should be revisited before any wider release |

Quick fix within today's scope [P]: add the SODL notice and licence link to the arrivals credit (Gap 1). It is a text
change in `app_config.dart` and the footer, and needs approval as a UI change.

## 7. Effect on E5

- E5 adds no data and no endpoint (F7). It uses the same `stops.min.json` and `services.min.json` through
  `BusNetwork`, so it inherits §5.1's open question; it does not add one.
- Its design (legs, planner, card, map) does not depend on the source. Under O4 or O5 it would work unchanged on a
  DataMall-built `BusNetwork`, except that both rides would show markers and a note instead of lines.
- The E5 benchmark stays optional (§5.3).

## 8. Decisions requiring owner approval

| ID | Decision | Recommendation |
|---|---|---|
| A-5a | How to resolve §5.1: O1 (ask LTA), O2 (advice), O4 or O5 (licensed DataMall data), or O6 (accept and document) | O2 or O1 before any wider release. For E5 Gate 3, decide whether O6 is acceptable meanwhile; otherwise plan O4 as its own enhancement, which removes route lines |
| A-5b | Add the SODL notice and licence link to the arrivals credit (Gap 1) | Approve, as a small separate change |
| A-5c | Make every live-busrouter dev tool optional and documented as such (§5.3) | Approve; documentation only |
| A-5d | Whether to assess OneMap's runtime use (tokenless search without the registration its terms require for web applications; tiles accepted in P2-M0) the same way | Approve, as a separate assessment: it is outside A-5's busrouter scope but has the same shape |
