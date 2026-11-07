# OneMap Runtime-Use Assessment (owner decision A-5d)

**Status:** assessment only, 2026-11-07, for owner review. No code, asset, test or history is changed, and no third
party (SLA, OneMap or anyone else) is contacted: no email, form, issue or registration. **It is not legal advice:**
readings of terms are tagged **[A]**, and the open questions in §5 need SLA's answer or advice to settle.

**Tags:** **[C]** confirmed (read from code, terms or docs, or measured); **[A]** assumption or reading not verified;
**[P]** proposal, needs approval.

**Owner's instruction** (as for A-5): public access, CORS headers, and personal or non-commercial use do not by
themselves grant permission.

**Related:** `docs/runtime-data-rights-assessment.md` (A-5, busrouter; A-5d is its decision 4),
`docs/arrivelah-onemap-fixture-licensing-audit.md` (A-4, the OneMap fixtures), `docs/map-feasibility.md` §4.1–§4.2
(the P2-M0 tile decision), `docs/data-sources.md` § OneMap.

**Update 2026-11-07 (owner decisions A-5d-1, A-5d-3, A-5d-5).** The official terms were read again, raw, with `curl`
(02:53–03:02 UTC), and each quote here was checked against that text (§9). The caching behaviour is compared with
the verified terms (§4.5 update), registration is reassessed (§4.3 update), the remaining open questions say who can
settle each (§10), and a letter to SLA is drafted, **not sent** (`docs/sla-clarification-request-draft.md`). Still
docs only, and still no third party contacted.

## 1. Summary

- **Update 2026-11-07 [C].** The raw re-read changes four readings (details in §9.2 and §9.3):
  - The API Terms of Service open with "The Agency may offer datasets through an API." They also say they "do not
    grant you any rights over: … any intellectual property found in content accessible through the APIs." They are
    the standard government template: data.gov.sg's API terms are the same apart from the host, and LTA DataMall's
    add clauses. So they do not say that search results are SODL "datasets"; that stays open (§10, Q2).
  - The registration checkbox also accepts an "Open Data Policy", and agrees to receive SLA's information about
    OneMap. §4.3 quoted it wrongly.
  - SLA's answers on ask.gov.sg can now be read raw. One says "The Terms and Conditions for the use of APIs can be
    viewed at API Terms of Service (onemap.gov.sg)". It shows how SLA itself points API users to the API terms.
  - The contact address is verified on the API docs' own "Contact Us" page: `onemap@sla.gov.sg`.
- **Update 2026-11-07, caching [C/A].** No published OneMap term mentions caching. Measured against the verified
  terms, the app's caches show **no confirmed incompatibility**. The Android disk tile cache is the closest point
  to Terms of Use 3(b)'s "store", which is a reading only [A] (§4.5 update).
- **[C]** The app uses two OneMap services at runtime: tokenless place search (`/api/common/elastic/search`) and the
  keyless `Default`/`Night` raster tiles with the OneMap logo. It sends no token, key or account data, and has none.
- **[C] Search is documented as token-only.** The API docs (read 2026-11-07) still show "Search API now requires
  token-based authentication. Register your token to ensure uninterrupted service", and list "API token provided by
  the Authentication Service" as a search parameter. Live, the tokenless call still answers HTTP 200 with results and
  CORS `*`. Every response carries "Authentication token missing. Please create an account and generate or renew your
  API Token."
- **[C] Tiles need no token.** The authentication docs say "The token is not required for the map services." The
  basemap docs require the OneMap logo and attribution, which the app shows exactly as OneMap's snippet gives it.
- **[C] New finding: an API terms of service, distinct from the website terms.** OneMap's "API Terms of Service"
  page (linked from the API docs, and accepted when registering) says: "Use of the datasets is governed by the
  Singapore Open Data Licence." OneMap hosts SODL v1.0, which permits use, copying and distribution with "a
  conspicuous notice acknowledging the source of the datasets and including a link to the most recent version of this
  Licence". The API terms also require using "the access control credentials issued to you if applicable", keeping
  them "secure and confidential", and using the API "in accordance to the Agency's published technical and other
  specifications". The "Developer Agreement" the website terms name could not be found; its old URL shows a "We have
  moved!" page.
- **[A] Reading.** Tokenless search is **not shown to be permitted.** It works technically, but the published
  specification puts a token on every search request, and the website terms want a registration for building a web
  application on the API. A token cannot be used within the project's rules: it would be a credential in a public
  bundle, or need a server. Tile use stays as accepted in P2-M0. If the SODL governs the search results, then the
  app's search credit lacks the licence notice and link.
- **[P]** Recommended: ask SLA in writing (drafted, not sent) whether a public, client-only app may use search without
  a token. Meanwhile, accept and document the position for this project (status quo, with the existing enforcement
  handling). Add the SODL notice and link to the search credit. Keep the tiles. Plan a contingency geocoder only if
  enforcement comes or SLA says no (§6, §8).

## 2. What the app uses at runtime [C]

| Use | Endpoint (`lib/core/config/app_config.dart`) | When | Attribution shown |
|---|---|---|---|
| Place search (origin and destination) | `https://www.onemap.gov.sg/api/common/elastic/search?searchVal=<q>&returnGeom=Y&getAddrDetails=Y&pageNum=1` (`OneMapEndpoints.search`) | Type-ahead (350 ms debounce, ≥ 3 chars or a 6-digit postcode) and submit; paced to 1 request per second (`OneMapRateLimit`) | "Place search: OneMap © Singapore Land Authority" (`oneMapAttribution`) under each result list and in the footer |
| Basemap tiles | `https://www.onemap.gov.sg/maps/tiles/{Default\|Night}/{z}/{x}/{y}.png` (`BasemapEndpoints`) | Only while the user has the map open; z11–19 inside OneMap's documented bounds (`MapConfig`) | 20 × 20 logo, then "OneMap © contributors \| Singapore Land Authority", both names linked (`BasemapAttributionRow`) |
| Logo | `https://www.onemap.gov.sg/web-assets/images/logo/om_logo.png` | With the map | Part of the attribution |
| Reverse geocode | `/api/public/revgeocode` | **Never**: it answers 401 without a token, so `reverseGeocode` returns null without a call | — |

Other facts from the code [C]:

- **Search client:** `JsonHttpClient` (10 s timeout, bounded retry on 5xx and network errors, `Accept: application/json`,
  4 MiB cap, in-flight dedup). It sets no `User-Agent`, so on Android dart:io sends its library default; on the Web the
  browser sends its own headers. `web/index.html` sets no referrer policy, so the browser's default applies (normally
  `strict-origin-when-cross-origin`, which sends the app's origin as `Referer` [A]).
- **Search results** are cached in memory only, per normalised query, for 5 min and at most 50 queries
  (`OneMapPlaceSearchRepository`). Nothing from OneMap is written to storage: `shared_preferences` holds only the
  palette id (E1). The chosen origin or destination lives in memory for the session.
- **Tiles:** `OneMapTileProvider` (`lib/features/map/presentation/basemap.dart`) is flutter_map 8.3.2's
  `NetworkTileProvider` with a plain `http.Client` (no automatic retry) and `BuiltInMapCachingProvider` capped at 50 MB
  (`MapConfig.tileCacheMaxBytes`). On Android flutter_map sends `User-Agent: flutter_map (sg.smartcommute.sg_smart_commute)`
  (`TileLayer.userAgentPackageName`); on the Web the header cannot be set and the built-in cache is a no-op, so the
  browser's HTTP cache applies.
- **CSP:** `connect-src` lists `https://www.onemap.gov.sg` (search, tiles and logo share the host).
- **Failure handling:** HTTP 401/403, or an `error` with no `results` list, → `ApiUnauthorized` ("OneMap now requires
  sign-in"), with no credential, proxy or workaround (`docs/assumptions.md`, "OneMap 'error' field").
- **Dev tools** that call OneMap live when run by hand: `tool/probe_apis.sh`, `tool/probe_map.sh`,
  `tool/api_probe_app.dart`, `tool/place_search_eval.dart`, `tool/journey_smoke.dart`, `tool/map_performance_probe.dart`.

## 3. Sources read [C]

All read on **2026-11-07** (about 02:20–02:40 UTC) with `curl`, unless marked otherwise. No page shows a "last updated"
date.

| Source | URL | How read | Result |
|---|---|---|---|
| OneMap Terms of Use | https://www.onemap.gov.sg/legal/termsofuse.html | `curl`, text extracted | Read in full |
| OneMap API Terms of Service | https://www.onemap.gov.sg/legal/apitermsofservice.html | `curl`, text extracted | Read in full |
| Singapore Open Data Licence v1.0 (OneMap copy) | https://www.onemap.gov.sg/legal/opendatalicence.html | `curl`, text extracted | Read in full |
| OneMap API docs (search, authentication, registration, MCP, workshop pages) | https://www.onemap.gov.sg/apidocs/ | A single-page app: the HTML shell is empty, so the text was read from its bundle `/apidocs/static/js/main.18cfd432.js` (1,363,539 B) with `grep` | Text strings read; layout and the page each string sits on are inferred from the surrounding strings [A] |
| Basemap docs | https://www.onemap.gov.sg/docs/maps/ | `curl`, text extracted | Read |
| Attribution snippet | https://www.onemap.gov.sg/docs/maps/resources/code-attr.txt | `curl` | Read; unchanged from the 2026-10-03 reading |
| TileJSON | https://www.onemap.gov.sg/maps/json/raster/tilejson/2.2.0/Default.json | `curl` | z11–19; bounds `[103.502, 1.16, 104.11475, 1.56073]`; no attribution field |
| "Developer Agreement" | https://www.onemap.gov.sg/legal/developeragreement.html | `curl` | **Not verified:** a "We have moved!" page with a link to the home page. No other copy found |
| SLA answers on ask.gov.sg ("How may I obtain approval for the use of OneMap?" and another) | https://ask.gov.sg/sla/questions/cmbt7ovwe00als5f6glia8wmv, …/cmbt7ovwe00ahs5f68ql9se2p | WebFetch and `curl` | **Not verified:** HTTP 403 to both. A web-search summary said they point to a registration portal and the API Terms of Service, which is not relied on |
| OSMF Nominatim usage policy | https://operations.osmfoundation.org/policies/nominatim/ | WebFetch (a model's summary with quotes) | Read; quotes as returned |
| OSMF tile usage policy | https://operations.osmfoundation.org/policies/tiles/ | WebFetch | Read; quotes as returned |
| Photon README | https://github.com/komoot/photon | WebFetch | Read; quotes as returned |

**Update 2026-11-07.** Every row above was read again raw (02:53–03:02 UTC), and the quotes in §4 and §6 were checked
against that text. Three statuses change:
- **ask.gov.sg answers: now verified.** `curl` with a browser `User-Agent` answered 200, and the answers were read
  raw (§9.1).
- **OSMF policies and Photon README: now verified.** They were read raw (the README from
  `raw.githubusercontent.com`), and the quotes in §6 S4, S4b and S6 are verbatim.
- **"Developer Agreement": still not verified.** The page still shows "We have moved!", and the API docs bundle does
  not name it.

Some pages do show a date. The Terms of Use, API Terms of Service and SODL pages on OneMap still show none, and the
basemap docs footer says "Copyright © 2024". §9.1 lists each source's date.

Live requests: §4.7. Avast's HTTPS scanning did not break `curl` here (it uses Windows' certificate store).

## 4. Assessment by topic

### 4.1 Tokenless place search

**What the app does [C].** One GET per search to `/api/common/elastic/search` with `searchVal`, `returnGeom=Y`,
`getAddrDetails=Y`, `pageNum=1`, and no `Authorization` header. It reads page 1 only (≤ 10 results). An `error` field
with an empty `results` list counts as no results; an `error` with no `results` list, or a 401/403, counts as
enforcement.

**What the documents say [C].**
- API docs banner (bundle string): "IMPORTANT: Search API now requires token-based authentication. Register your
  token to ensure uninterrupted service." The search page lists the parameter "API token provided by the
  Authentication Service", and its code samples send an `Authorization` header. The search page's errors include
  "429 - API limit exceeded." with no number.
- The August 2025 workshop page: "OneMap's Search API Tokenized Search is a recent update that most API users will
  start to observe when accessing the OneMap website. Once adopted, users will receive a unique authentication token
  for their queries, which will be renewed every 3 days." And: "Users onboard the token-based authentication will have
  a higher API call limit capped at 250; and further request for higher limits can be discussed on a case-by-case
  basis." No unit or period is given.
- API Terms of Service, Additional Conditions: "Your right to Use APIs may be subject to additional terms, including
  limitations on Use, found on the individual pages of each API." "When you Use the API, you must utilise the access
  control credentials issued to you if applicable." "You agree to Use the API in accordance to the Agency's published
  technical and other specifications".
- The response itself (live, 2026-11-07): HTTP 200, `"found": 58`, and `"error": "Authentication token missing. Please
  create an account and generate or renew your API Token."` This is the same text as in the fixtures captured on
  2026-10-01.

**Reading [A].**
- The token requirement is documented, not enforced: the server answers in full and adds a notice. The notice tells
  the caller to "create an account and generate or renew your API Token", so it states a requirement, not just a
  missing value. The workshop text suggests a soft rollout, with tokenless calls on a lower limit (matching the 429
  after 2–3 calls seen in October).
- Under the API terms, the search page's token requirement is an "additional term" and part of the "published
  technical … specifications". So tokenless use is **not shown to be permitted**, even though it works. "Credentials
  issued to you if applicable" does not help: it reads as "if you have been issued credentials", and the search page
  says everyone should have them.
- The app's behaviour on enforcement is sound: a clear `ApiUnauthorized` state and no workaround.

### 4.2 Map tiles

**What the app does [C].** `Default` tiles in light mode and `Night` in dark mode, 256 px PNG, z11–19, camera bounded
to the docs' SW (1.144, 103.535) to NE (1.494, 104.502), only while the map is open, no prefetch or offline pack, no
automatic retry, refit once per scene change (`docs/map-feasibility.md` §4.2 rules 1–7).

**What the documents say [C].**
- Authentication docs: "The token is not required for the map services."
- Basemap docs: "Under our Terms of Use, by using our base map services, you MUST include the OneMap logo and
  attribution". They give the XYZ URL `https://www.onemap.gov.sg/maps/tiles/Default/{z}/{x}/{y}.png`, HD, TileJSON,
  WMS and WMTS links, and Leaflet examples.
- TileJSON: z11–19, bounds `[103.502, 1.16, 104.11475, 1.56073]`. These differ from the docs' Leaflet bounds, which
  the app uses; P2-M0 found that tiles outside Singapore return an empty 200.
- No tile usage policy, rate limit, quota or caching rule was found in the basemap docs, the terms of use or the API
  terms (searched again 2026-11-07). The tile response sends `Cache-Control: max-age=14400, s-maxage=14400,
  must-revalidate`.

**Reading [A].** Unchanged from P2-M0: tiles are offered for embedding, need no token, and the app meets the one
stated condition (logo and attribution). The lack of a published limit is not read as permission for unlimited
traffic, and the project's reasonable-use rules stay. Whether the API terms (and so the SODL) also cover tiles is
unclear: the basemap docs point to the "Terms of Use", not the API terms.

### 4.3 Registration and authentication

**What the app does [C].** Nothing: no account, no token, no credential anywhere in the bundle.

**What the documents say [C].**
- Terms of Use, preamble: "If you are interested in the material on the Site and you wish to use or start building
  your own Web Application(s) using the API and the Data, then you will need to complete the online registration
  process and as part of that process click to accept the terms of the Developer Agreement." A "Registered Developer"
  is a user who "has accepted the terms and conditions of the Developer Agreement". Clause 2 lets SLA "restrict access
  to some parts of the Site e.g. to Registered Developers only".
- Registration page (bundle string): "By registering for an account, I acknowledge and accept the [Privacy Statement]
  and [API Terms of Service] of OneMap." (**not verbatim**: corrected in the update below.) It posts to `/api/public/user/registerUser` and `confirmRegistration`
  (email and password, confirmation code).
- Authentication API: "This API authenticates users' credentials (email and password) as a POST request body to
  generate an access token." "Each token is valid for 3 days. … When it expires, the user needs to re-authenticate
  with the same credentials. The token does not auto renew when it expires." "Developers are strongly encourage to
  securely store sensitive data such as API keys and passwords in your application." The best-practice page says to
  "store credentials and tokens securely using environment variables or secure storage solutions". The MCP pages
  describe a newer refresh-token flow (access tokens "last 24 hours", refresh after 30 days) and say "don't share them
  or commit them to Git."
- API Terms of Service: "You agree to keep such credentials secure and confidential."
- The "Developer Agreement" itself: **not verified** (§3). The registration page now names the API Terms of Service
  instead [A].

**Reading [A].**
- Search needs a token; tiles do not. Reverse geocoding and routing already answer 401 without one.
- A token comes only from the developer's email and password, and lasts 3 days (24 hours on the newer flow). A public
  app could use one only by shipping those credentials, or a token renewed every few days, in the bundle, or by adding
  a server to hold them. The first breaks `CLAUDE.md`'s "no credentials, no secrets" rule and the API terms'
  confidentiality clause; the second breaks "no server-side component of any kind". So **any token-requiring OneMap
  API is out of scope by rule**, as `docs/data-sources.md` already says for routing.
- Registering an account without using a token in the app would make the owner a registered developer who has
  accepted the API terms. It would not meet the search page's token requirement, and the app would be exactly as it is
  now. It is still a third-party registration, for the owner to decide (§6, S5).

**Update 2026-11-07: verified requirements and reassessment (A-5d-5).**

*What registration is [C]* (API docs bundle, read 02:55 UTC):
- **The checkbox, verbatim:** "By registering for an account, I acknowledge and accept the Privacy Statement, Open
  Data Policy and API Terms Of Use of OneMap. I also agree to receive information about OneMap provided by Singapore
  Land Authority, including (but not limited to) updates and notifications for OneMap API."
  - "Privacy Statement" links to `onemap.gov.sg/legal/privacystatement.html`, and "API Terms Of Use" links to
    `legal/apitermsofservice.html`. "Open Data Policy" has no link, and no page of that name was found.
- **The form asks for:**
  - an email address;
  - a "User Group" (Business, Government Agency, Education, Others) and an industry;
  - "Which type of application are you developing?" (Mobile Application, Website, Research / Student Projects,
    Others);
  - "What is the proposed use of the data/API?";
  - how the user learned about OneMap.

  A reCAPTCHA runs on submit.
- **The second step:** "Enter your confirmation code and set your password to start utilizing Singapore's
  geospatial data." The password is 12 to 60 characters.
- **The token:** it comes from email and password, "Each token is valid for 3 days", and "The token does not auto
  renew when it expires". The search page marks the `Authorization` header "Required".

*Who must register, for what [C/A]:*

| Use | Official text | Registration needed? |
|---|---|---|
| Search API | Banner: "Search API now requires token-based authentication. Register your token to ensure uninterrupted service."; `Authorization` "Required" [C] | **Yes, as documented**, for any caller, since only a registered account can get a token [C]. Not enforced today [C] |
| Map tiles | "The token is not required for the map services." Basemap docs ask only for the logo and attribution [C] | **No token**. Whether the Terms of Use preamble's registration ("use or start building your own Web Application(s) using the API and the Data") still reaches a keyless tile user is not stated [A] |
| Reverse geocode, routing | Token; 401 without one [C] | Yes; the app does not use them |
| Old SLA answer (ask.gov.sg, "Updated by SLA 1y ago") | "You may apply for a OneMap API token which allows you to display maps on your website. Please apply for the token at this URL https://developers.onemap.sg/register/ ." [C] | It predates the current docs, which say tiles need no token. Read as outdated [A] |

*Reassessment [A]:*
- **No compliant token path exists within `CLAUDE.md`.** A token comes only from an account's email and password,
  lasts 3 days, and must be kept "secure and confidential" (API terms). A public Web or Android bundle cannot hold it,
  and the app has no server to hold it.
- **Registration alone meets nothing that matters at runtime.** It may meet the Terms of Use preamble's
  "online registration process". It does not meet the search page's token requirement. It changes nothing in the
  app.
- **It costs the owner something.** The owner would accept the API terms, give SLA personal data, and agree to
  receive SLA's messages: a personal decision.
- **Recommendation for A-5d-5: still "not now".**
  - Ask SLA first (`docs/sla-clarification-request-draft.md`, question 2): who must register, and whether a keyless
    public client can be accepted at all.
  - Register only if SLA asks for it. Then record that the app still sends no token.
  - Registering and then sending no token would not make tokenless search compliant.

### 4.4 Attribution

| Requirement | Source | What the app shows | Status |
|---|---|---|---|
| OneMap logo and "OneMap © contributors \| Singapore Land Authority", linked, with base maps | Basemap docs; snippet `code-attr.txt` (2026-11-07) | The 20 × 20 logo, the same text, "OneMap" → `https://www.onemap.gov.sg/`, "Singapore Land Authority" → `https://www.sla.gov.sg/`, always visible below the map | **Met [C]** |
| Do not remove or obscure SLA notices and logos | Terms of Use 3(b)(ii) | Never collapsed, covered or removed (widget test) | **Met [C]** |
| Links only to the home page, with no implied endorsement | Terms of Use 8(a)–(b) | Links to the home page only; no endorsement wording | **Met [A]** |
| A "conspicuous notice acknowledging the source of the datasets" with "a link to the most recent version of this Licence" | SODL v1.0, if it governs API data (API Terms of Service) | "Place search: OneMap © Singapore Land Authority": source named, no licence notice or link | **Gap [A]**, if the SODL applies |
| Search-specific attribution | API docs | None found in the search docs | — |
| SLA (service level) | Terms of Use clause 2 and 11 (**update 2026-11-07:** the disclaimer is clause 10; clause 11 is the indemnity); API terms "Disclaimers" | No service level is offered ("as is", "as available"; the API terms disclaim "service levels, continued availability") | Nothing to show [C] |

Terms of Use 3(b)(ii) also bars "use" of SLA's logos except as 3(a) allows, while the basemap docs require the logo.
The docs' explicit requirement is read as the permission for that use [A].

**Update 2026-11-07: links in any new credit [C/A]** (this bears on A-5d-2):
- **OneMap Terms of Use 8(a)–(b):** "You may link to the Site's home page", and "You must not establish a link: … to
  any part of this Site other than the home page". So a licence link to OneMap's copy
  (`onemap.gov.sg/legal/opendatalicence.html`) would be a link to a part other than the home page [A].
  - The same text of SODL v1.0 is at `https://data.gov.sg/open-data-licence`. data.gov.sg's terms say only: "If you
    create a link or frame to The Website, you do so at your own risk. We reserve the right to object or disable any
    link or frame to or from The Website." [C]
- **SLA's own website terms** (`www.sla.gov.sg/terms-of-use`, "Last updated on 28 May 2025") say: "You shall not cache
  or frame this Site or any part thereof or any of the Contents, nor create hyperlinks to any page of this Site or any
  of the Contents, without the prior written permission of SLA" [C].
  - The basemap credit's `https://www.sla.gov.sg/` link is the one OneMap's own required snippet gives. It is read
    as permitted through that requirement [A].
  - A new link to sla.gov.sg elsewhere has no such basis [A].
- **The SODL also says:** "You must not Use the datasets in a way that suggests any official status or that an Agency
  endorses you or your Use of the datasets." [C]

### 4.5 Caching and storage

**What the documents say [C].**
- Terms of Use 3(a): "access, view, download, print or otherwise use the SLA Data and the SLA Material for any
  usage". 3(b): "Except as expressly permitted in Clause 3(a) above, you shall not: store, download, archive, print,
  distribute, publicly display, reproduce, publish, … copy, …".
- SODL v1.0 (if it governs API data): "use, access, download, copy, distribute, transmit, modify and adapt the
  datasets", with the attribution notice.
- Tiles: `Cache-Control: max-age=14400, s-maxage=14400, must-revalidate`, plus `ETag` and `Last-Modified`.
- Search responses: no `Cache-Control`, `ETag` or `Last-Modified` header (live, 2026-11-07).
- flutter_map 8.3.2 `BuiltInMapCachingProvider`: "Simple built-in map caching using an I/O storage mechanism, for
  native (non-web) platforms only". It "Usually uses HTTP headers to determine tile freshness". Its default directory
  is "a platform provided cache directory, which may be cleared by the OS at any time"; it "will noop" on the Web.

**What the app stores [C].**

| Data | Where | How long |
|---|---|---|
| Search results | In memory (`OneMapPlaceSearchRepository`) | 5 min per query, ≤ 50 queries, gone when the app closes |
| Chosen origin and destination | In memory (providers) | The session |
| Tiles, Android | flutter_map's built-in cache on disk, in the platform cache directory | Fresh for `max-age` (4 h), then revalidated; kept on disk up to the 50 MB cap, beyond the session, until trimmed by the cap or cleared by the OS |
| Tiles and logo, Web | The browser's HTTP cache | As the browser applies `max-age` |
| Search responses, Web | Browser HTTP cache | Not cached: no validators or freshness headers [A] |

**Reading [A].**
- The in-memory search cache is transient use during the session, close to "view" and "otherwise use"; it is not
  archiving.
- The HTTP caches follow OneMap's own `Cache-Control` and revalidate. That is the behaviour the server asks for, and
  P2-M0 accepted it.
- The Android disk cache is the closest to 3(b)'s "store": tiles stay on disk across sessions, up to 50 MB, though
  each one is revalidated before reuse once stale. It is a cache honouring the server's headers, not an offline pack,
  but the terms do not mention caching. Recorded as a residual point for SLA (§6, S2).

**Update 2026-11-07: behaviour from code against verified terms (A-5d-3; no behaviour changed).**

*Behaviour, from the code at `bbd9329` and flutter_map 8.3.2's source in the pub cache [C]:*

| Item | Behaviour |
|---|---|
| Search cache | `PlaceSearchConfig.cacheTtl` = 5 min; `maxCachedQueries` = 50 (least recently used evicted first; expired entries dropped on every write); failures not cached. `OneMapPlaceSearchRepository` keeps the parsed `Place` values (id, display name, address, postal code, latitude, longitude, type), not the raw response, in a Dart map in memory; nothing reaches disk or `shared_preferences` |
| Search pacing | `OneMapRateLimit`: 1 request per 1 s window per running app, retries included; debounce 350 ms; at least 3 characters or a 6-digit postcode; at most 100 characters; page 1 only (≤ 10 results) |
| Tiles, Android | `OneMapTileProvider` = `NetworkTileProvider` + `BuiltInMapCachingProvider.getOrCreateInstance(maxCacheSize: MapConfig.tileCacheMaxBytes)`, which is 50,000,000 bytes. Files go in an `fm_cache` folder under the platform cache directory, "which may be cleared by the OS at any time". Freshness comes from `Cache-Control: max-age` (OneMap sends `max-age=14400`, 4 h, observed by A-5d at 02:33 UTC). A fresh tile is shown from disk with no request. A stale one is revalidated with `If-None-Match` / `If-Modified-Since`, and a 304 refreshes its metadata. **A stale tile is never shown when the request fails**: the code evicts it and reports the error. The size cap "is applied only when the instance is created", so the cache "may exceed this limit while the program is running" |
| Tiles, Web | The built-in provider is a no-op ("they will noop"). The browser's HTTP cache applies OneMap's headers; the app adds no cache, service-worker tile cache or storage |
| Prefetch, offline | None: tiles are requested only while the map is open, for the visible area plus flutter_map's default one-tile `panBuffer` |

*Official terms on caching and storage, verified raw [C]:*
- **OneMap Terms of Use 3(a):** "SLA grants to you a non-transferable, non-exclusive, royalty-free, revocable licence
  to access, view, download, print or otherwise use the SLA Data and the SLA Material for any usage, subject to the
  terms and conditions set out in these Terms of Use."
- **3(b)(i):** "Except as expressly permitted in Clause 3(a) above, you shall not: store, download, archive, print,
  distribute, publicly display, reproduce, publish, post, communicate, copy, modify, edit, translate, adapt, transmit,
  upload in any medium or combine or integrate with or incorporate into any other materials, any part of the Site or
  any SLA Data or SLA Material".
- **Clause 6 (termination):** "you … must promptly destroy and/or permanently erase all copies of the SLA Data and SLA
  Material in your possession, custody or control."
- **API Terms of Service:** no caching or storage clause. They refer to "additional terms, including limitations on
  Use, found on the individual pages of each API".
- **API docs:** no caching rule for search results or tiles. The only caching text is about the token: "you can use a
  utility like tokenCache to store the token temporarily for reuse without additional API calls".
- **Basemap docs:** no caching rule.
- **SODL v1.0** (if it applies): "use, access, download, copy, distribute, transmit, modify and adapt the datasets".
- **The server's own headers:** tiles `max-age=14400, s-maxage=14400, must-revalidate`; search responses have none.

*Comparison:*

| Behaviour | Against the verified terms | Finding |
|---|---|---|
| In-memory search cache (5 min, ≤ 50 queries) | No term mentions caching. 3(a) allows to "download … or otherwise use … for any usage". Whether a 5-minute in-memory copy is "store" or "copy" under 3(b) is a reading | **No confirmed incompatibility.** Possible reading only [A]: low, as it is transient and never written to storage |
| Android disk tile cache (trimmed to 50 MB when first opened in each run, kept across sessions, OS-clearable) | No term mentions caching. The server's `Cache-Control` invites caching for 4 h and requires revalidation after, which the code does. The bytes stay on disk past 4 h, stale, until revalidated, trimmed or cleared. 3(b) names "store" and "archive", unless 3(a) covers it | **No confirmed incompatibility.** The **closest possible conflict [A]**: a persistent on-device copy of SLA Data could be read as "store" under 3(b)(i). It is a cache that honours headers, not an offline pack |
| Browser HTTP cache (Web) | Same headers; the browser decides | **No confirmed incompatibility** [A] |
| Clause 6 erase-on-termination | Only on termination. An installed Android app cannot erase users' caches remotely; the OS may clear them; the cap trims when the cache is first opened in each run | Nothing applies today. It is a point to ask about if SLA ever terminates [A] |

**Confirmed incompatibilities: none.** No verified clause names caching, and none sets a period, size or place that the
app exceeds.

**For an owner decision, as possible readings only [A]:**
- the Android disk tile cache under 3(b)(i) "store";
- the in-memory search cache under the same clause, much weaker.

Both are put to SLA in the letter (question 4). A-5d-3's recommendation is unchanged: keep the behaviour until SLA
answers. If the owner wants to remove the closest point without waiting, an in-memory-only tile cache on Android is a
code change for its own PR (not proposed here).

**Correction to the table above [C]:** for "Tiles, Android", the 50 MB cap is applied when the cache is first opened in each run. It is not
a hard ceiling during a session.

### 4.6 Android and Web

**What the documents say [C].** No platform-specific terms were found. The API terms: "You shall not mis-present or
mask your API Client's identity when Using the API." No `User-Agent` or `Referer` requirement is published for search
or tiles.

**What the app sends [C/A].**

| Request | Android | Web |
|---|---|---|
| Search | dart:io's default `User-Agent` (`Dart/<version> (dart:io)`) [A]; no `Referer`; no cookie jar, so OneMap's `Set-Cookie` is not kept [A] | The browser's `User-Agent`, `Origin` and `Referer` (the app's origin) [A]; a non-credentialed request, so the cookie is not stored [A] |
| Tiles | `User-Agent: flutter_map (sg.smartcommute.sg_smart_commute)` [C] | The browser's headers |

**CORS [C].** Search, its preflight and tiles all answer `Access-Control-Allow-Origin: *` (§4.7). The 429 has no CORS
header, so the Web sees a network error (`docs/assumptions.md`, "OneMap rate limit"). Android does not apply CORS.

**Reading [A].** Neither platform masks or misrepresents the client: no spoofed header, no proxy. The Android search
request does not identify the app either, since it uses the library default. Setting an app `User-Agent` there would be
a small production change (§8, A-5d-4); it is not required by any published OneMap rule.

### 4.7 Documented terms against technical access

**Live requests [C]** (2026-11-07, 02:33 UTC; `Origin: https://example.com`; bodies kept only in the session
scratchpad and not committed; `X-Remote-Addr` and cookie values not recorded):

| Command | Status | Relevant headers |
|---|---|---|
| `curl -sS -D - -o <scratch> -H "Origin: https://example.com" "https://www.onemap.gov.sg/api/common/elastic/search?searchVal=orchard&returnGeom=Y&getAddrDetails=Y&pageNum=1"` | **200**, `application/json`, 4,133 B | `Access-Control-Allow-Origin: *`; `Access-Control-Allow-Headers` includes `Authorization`; no `Cache-Control`, `ETag` or rate-limit headers; a `Set-Cookie` (`_toffsuid`, `HttpOnly`, `SameSite=strict`); `Referrer-Policy: no-referrer`. Body fields only: `found` 58, and the "Authentication token missing…" `error` |
| `curl -sS -X OPTIONS -o /dev/null -D - -H "Origin: https://example.com" -H "Access-Control-Request-Method: GET" "<same URL>"` | **200**, 2 B | `Access-Control-Allow-Origin: *`; `Access-Control-Allow-Methods: GET,OPTIONS` (and wider repeated lists) |
| `curl -sS -o <scratch> -D - -H "Origin: https://example.com" "https://www.onemap.gov.sg/maps/tiles/Default/15/25836/16266.png"` | **200**, `image/png`, 21,083 B, 256 × 256 | `Access-Control-Allow-Origin: *`; `Cache-Control: max-age=14400, s-maxage=14400, must-revalidate`; `ETag`; `Last-Modified: Fri, 06 Nov 2026 03:54:45 GMT`; `X-Cache-Status: HIT` |

**Differences [A].**

| Topic | Documented | Technically |
|---|---|---|
| Search token | Required ("now requires token-based authentication"; token parameter) | Not enforced: 200 with results and a notice |
| Web application registration | Required by the Terms of Use preamble | Nothing checks it |
| Tiles token | Not required | Not required |
| Rate limit | "429 - API limit exceeded"; "capped at 250" for token users, no unit | 429 after 2–3 tokenless calls in about 1.5 s (October) |
| Browser access | No statement | CORS `*` on search, preflight and tiles |
| Reverse geocode, routing | Token | 401 without one |

None of the technical facts grants permission (owner's instruction). They show only that enforcement could start at
any time without notice, which the terms allow (clause 2; API terms "Suspension or termination").

## 5. Open questions

1. **[A]** Do the API Terms of Service (and so the SODL) govern search results, alongside or instead of the website
   terms' clause 3(b)? If they do, use and redistribution are licensed with the notice and link (§4.4). Only SLA or
   advice can settle this.
2. **[A]** Does SLA accept tokenless search from a public, client-only app while the token requirement is not
   enforced? The docs say no; the server says nothing.
3. **[A]** Do the API terms cover tiles, and is a header-honouring disk cache on Android "store" under 3(b)?
4. **[A]** What happened to the "Developer Agreement"? The terms still name it, and its old URL has moved.

**Update 2026-11-07.** §10 lists these questions with the others across A-4, A-5 and A-5d. For each one it says
whether the data owner (SLA, LTA, LTA DataMall) or qualified legal advice can settle it.

## 6. Options

| ID | Option | What it involves | Against the hard constraints | Assessment |
|---|---|---|---|---|
| S1 | **Accept and document** (status quo): keep tokenless search, the enforcement handling and the tiles | This document; owner's decision | Fits | Keeps the app. The documented requirement stays unmet; enforcement may come without notice, and the app then shows "requires sign-in" with no place search. Revisit before any wider release |
| S2 | **Ask SLA in writing** (OneMap's contact page, `http://www.onemap.gov.sg/apidocs/contactus`, named in the API docs): tokenless search from a public client-only app at ≤ 1 request/s; whether the SODL governs API data; the Android tile cache. **Update 2026-11-07:** that page's text gives `onemap@sla.gov.sg` ("If you have any questions, please reach out to us. … Feel free send us feedback at onemap@sla.gov.sg"). The August 2025 workshop page asks token enquirers to write there with "Name of Application", "Endpoints used" and "Expected Traffic". Draft: `docs/sla-clarification-request-draft.md` | A letter from the owner, **drafted only, not sent** | Fits (no change unless SLA answers) | The only route to an authoritative answer. SLA may say no, or not answer |
| S3 | **Register and use a token** | An account, then a token in the app or on a server | **Breaks both rules**: a credential in a public bundle, or a server. The API terms' confidentiality clause also rules out the bundle | Out of scope |
| S4 | **Replace search with Photon** (komoot public demo) | A new adapter (`PlaceSearchRepository` already exists as the seam), a CSP host, ODbL attribution | Fits: keyless, CORS `*` | README: "reasonable limit"; "Extensive usage will be throttled or completely banned"; no availability guarantee. Weaker in Singapore: no HDB block resolution, wrong acronyms (`docs/api-feasibility.md`). A public demo server's fair use for a distributed app is its own question [A] |
| S4b | **Replace search with Nominatim** (OSMF) | As S4, submit-only | Fits for submit; **not for type-ahead** | Policy: "an absolute maximum of 1 request per second" summed across all users; "stock User-Agents as set by http libraries will not do"; autocomplete "you must not implement such a service on the client side". Removes type-ahead; weaker in Singapore |
| S5 | **Register only**, accept the API terms, and keep tokenless search | An account (third-party registration, the owner's decision) | Fits (no token in the app) | Meets the Terms of Use preamble as written, not the search page's token requirement. Signals good faith; changes nothing technically. Worth doing only with S2 |
| S6 | **Replace tiles with OSM standard tiles** | A CSP host, OSM attribution, a distinct app User-Agent on Android | Fits | Policy: "Apps must configure a distinct, stable `User-Agent`", "Do **not** use a library default", Web "expected to send a valid `Referer`", "cache each tile for **at least 7 days**", "Offline use is not permitted", block "without notice". No dark style. No benefit over OneMap tiles, which need no token. Not recommended |
| S7 | **Replace tiles with OpenFreeMap** | MapLibre vector rendering | Fits (keyless) | Ruled out in P2-M0 (vector only). Not recommended |
| S8 | **SODL notice and link** on the search credit (and, if SLA confirms, on the basemap credit) | A text change in `app_config.dart` and the footer | Fits | Closes §4.4's gap if the SODL applies; harmless if not. Can ship with A-5b's arrivals notice |
| S9 | **Drop place search** | GPS-only origin; no destination search | Fits | Removes the M2 core feature. Not viable |

## 7. Effect on other decisions

- **A-4b (OneMap fixtures).** A-4 read the website terms only. If the SODL governs API data (§5 Q1), committing the
  captured results might be permitted with a notice. A-4b's recommendation (synthetic responses) still stands: it
  removes the question either way, and the captures were made tokenless.
- **A-5.** Unchanged. OneMap appears there only as a source of busrouter's route patches.
- **Dev tools.** The six live-OneMap tools in §2 have the same standing as the busrouter ones in A-5c.

## 8. Decisions requiring owner approval

| ID | Decision | Recommendation |
|---|---|---|
| A-5d-1 | How to treat tokenless search, documented as token-only: S1 (accept and document), S2 (ask SLA), S4/S4b (another geocoder); S3 (token) is out by rule | **S2 plus S1 meanwhile**: draft the letter for the owner to send or not, and keep the app as it is for this project. Plan S4 as its own change only if enforcement starts or SLA refuses. Revisit before any wider release |
| A-5d-2 | Add an SODL notice and licence link to the search credit (S8) | **Approve**, as a small separate UI-text change, together with A-5b if both are approved |
| A-5d-3 | Keep OneMap tiles under the P2-M0 rules, including the Android disk cache | **Keep**: the token is documented as not required for map services, and the attribution matches the snippet. Raise the disk cache in the S2 letter. Re-check the terms at any later map change |
| A-5d-4 | Send an app-identifying `User-Agent` on Android search requests | **Optional, low priority**: no published OneMap rule requires it; it would be a production change in its own PR |
| A-5d-5 | Register a OneMap account and accept the API terms without using a token (S5) | **Not now**: it changes nothing in the app and is a third-party registration. Reconsider only if SLA asks for it in answer to S2 |
| A-5d-6 | Treat the live-OneMap dev tools like A-5c (optional, run by hand, never in CI) | **Approve**; documentation only |

**Update 2026-11-07 (owner decisions of 2026-11-07).**

| ID | Status |
|---|---|
| A-5d-1 | S2 is drafted: `docs/sla-clarification-request-draft.md`, **not sent**. S1 holds meanwhile. Whether and when to send it is the owner's decision |
| A-5d-2 | Kept for a separate PR by the owner. The verified link limits (§4.4 update) bear on the wording: link the licence at data.gov.sg, not OneMap's legal page, and add no new sla.gov.sg link |
| A-5d-3 | Behaviour unchanged. Compared with the verified terms: **no confirmed incompatibility**. The Android disk cache is a possible reading under 3(b)(i) [A], and is asked about in the letter (§4.5 update) |
| A-5d-5 | Reassessed with the verified requirements: **still not now**. Register only if SLA asks for it (§4.3 update) |

## 9. Verified terms (2026-11-07, raw)

### 9.1 Sources

Every row was read with `curl` into the session scratchpad and extracted to text with a small script that strips tags.
Nothing was summarised by a model. "Date on page" is the page's own "last updated" text, if any.

| Source | URL | Read (UTC) | Date on page |
|---|---|---|---|
| OneMap Terms of Use | https://www.onemap.gov.sg/legal/termsofuse.html | 02:53 | None |
| OneMap API Terms of Service | https://www.onemap.gov.sg/legal/apitermsofservice.html | 02:53 | None |
| SODL v1.0, OneMap copy | https://www.onemap.gov.sg/legal/opendatalicence.html | 02:53 | None |
| OneMap "Developer Agreement" | https://www.onemap.gov.sg/legal/developeragreement.html | 02:53 | **Not verified**: "We have moved! Visit us at our new site https://www.onemap.gov.sg." |
| OneMap basemap docs | https://www.onemap.gov.sg/docs/maps/ | 02:53 | "Copyright © 2024" (footer) |
| OneMap attribution snippet | https://www.onemap.gov.sg/docs/maps/resources/code-attr.txt | 02:53 | None |
| OneMap API docs (single-page app) | https://www.onemap.gov.sg/apidocs/ → bundle `/apidocs/static/js/main.18cfd432.js` (1,363,539 B, the same file as A-5d's) | 02:55 | "©2025 OneMap. All rights reserved" (footer) |
| SLA website Terms of Use | https://www.sla.gov.sg/terms-of-use | 02:53 | "Last updated on 28 May 2025" |
| SLA answers on ask.gov.sg (5) | https://ask.gov.sg/sla/questions/ + `cmbt7ovwe00als5f6glia8wmv`, `cmbt7ovwe00ahs5f68ql9se2p`, `cmbt7ovwd00ads5f697i3bmzi`, `cmbt7ovwd00afs5f63pdyi1y9`, `cmbt7ovwe00ajs5f64epszmwk` | 02:59 | Each "Updated by SLA 1y ago" |
| LTA website Terms of Use | https://www.lta.gov.sg/content/ltagov/en/terms-of-use.html | 02:53 | "Last updated 03 December 2021" |
| LTA DataMall API Terms of Service | https://datamall.lta.gov.sg/content/datamall/en/api-terms-of-service.html | 02:54 | "Last updated 09 July 2025" |
| LTA DataMall website Terms of Use | https://datamall.lta.gov.sg/content/datamall/en/term-of-use.html | 02:54 | "Last updated 25 August 2022" |
| SODL v1.0, DataMall copy | https://datamall.lta.gov.sg/content/datamall/en/SingaporeOpenDataLicence.html | 02:54 | "Last updated 14 December 2020" |
| SODL v1.0, data.gov.sg | https://data.gov.sg/open-data-licence | 02:53 | None |
| data.gov.sg Privacy & Terms (with its API Terms of Service) | https://data.gov.sg/privacy-and-terms | 02:55 | None |
| busrouter-sg and arrivelah READMEs | https://raw.githubusercontent.com/cheeaun/busrouter-sg/master/README.md, …/arrivelah/master/README.md | 02:57 | None |
| OSMF Nominatim and tile policies, Photon README | https://operations.osmfoundation.org/policies/nominatim/, …/tiles/, https://raw.githubusercontent.com/komoot/photon/master/README.md | 03:01 | None |

`https://datamall.lta.gov.sg/content/datamall/en/tnc.html` answered 404. The three DataMall URLs above are the ones
DataMall's home page links to.

### 9.2 Clauses relied on, verbatim [C]

The quotes in §4 were checked against this text. They are verbatim except those in §9.3. Further clauses:

- **OneMap Terms of Use.**
  - 3(b)(ii): "remove, obscure, modify, alter or use any copyright notices, registered or unregistered trademarks,
    service marks or logos owned by or proprietary to SLA, or do anything which may constitute an infringement of any
    of the intellectual property rights of SLA or our third-party licensors."
  - Clause 2: "We reserve the right to deny or restrict access to this Site by any person, or to block access from a
    particular internet address to this Site, at any time without prior notice and without ascribing any reasons
    whatsoever."
  - Clause 9: "Currently, no charge is imposed for accessing or using any part of this Site."
  - The "User" definition reads, as published: ""User" or "you" means the mapping data application programming
    interface owned by or licensed to SLA to allow you to build experimental, innovative, web based applications using
    the Data." "the API" and "the Data" are not defined.
- **OneMap API Terms of Service.**
  - "The Agency may offer datasets through an API. Use of the datasets is governed by the Singapore Open Data Licence
    ." ("Singapore Open Data Licence" links to `opendatalicence.html`.)
  - "You can use, access, call, command, query or request the API, whether commercially or non-commercially
    ("Use")."
  - "These Terms of Service do not grant you any rights over: any personal data should any personal data be included
    or exposed through the APIs, inadvertently or otherwise; and any intellectual property found in content
    accessible through the APIs."
  - "The Agency may terminate these Terms of Service or suspend your access to the API for any reason whatsoever."
  - Apart from the host it names, the text is the same as data.gov.sg's API Terms of Service. LTA DataMall's version
    numbers the clauses and adds some (clauses 4, 5, 10(d) and 10(e)).
- **SODL v1.0.** The same text on all three hosts, apart from where sub-licensees are sent ("onemap.gov.sg" or
  "data.gov.sg").
  - The example notice: "[Contains information from {name of dataset} accessed on {date of access of dataset} from
    {source of data} which is made available under the terms of the Singapore Open Data Licence version 1.0 {URL link
    to licence}]".
  - "“Dataset” includes any data, or information within the dataset, that is offered for use under the terms of this
    Licence."
- **data.gov.sg terms, clause 2:** "The use of Datasets on The Website is wholly governed by the Singapore Open Data
  Licence . Access to datasets via application programming interfaces (APIs) is governed by the API Terms of Service
  ."
- **OneMap basemap docs:** "Under our Terms of Use , by using our base map services, you MUST include the OneMap logo
  and attribution:". "Terms of Use" links to `legal/termsofuse.html`, and the footer's "Contact Us" is
  `mailto:onemap@sla.gov.sg`.
- **Attribution snippet** (raw HTML): logo `om_logo.png` at 20 × 20, then `OneMap` linked to
  `https://www.onemap.gov.sg/`, `&copy;&nbsp;contributors&nbsp;&#124;&nbsp;`, then `Singapore Land Authority` linked to
  `https://www.sla.gov.sg/`.
- **OneMap API docs.**
  - Contact page: "If you have any questions, please reach out to us." and "Feel free send us feedback at
    onemap@sla.gov.sg and we will get back to you as soon as possible!"
  - Workshop page: "Users onboard the token-based authentication will have a higher API call limit capped at 250; and
    further request for higher limits can be discussed on a case-by-case basis." Then: "Interested parties can contact
    the SLA team at onemap@sla.gov.sg, and include the following details to allow us to better assist you: Name of
    Application; Endpoints used; Expected Traffic". No unit is given for "250". No other number appears in the
    bundle.
- **SLA website Terms of Use** (these govern `www.sla.gov.sg`, not OneMap).
  - "You may view, download and print the Contents for your personal, internal and non-commercial use, provided that
    you keep intact all accompanying copyright and other proprietary notices."
  - The hyperlink clause is quoted in §4.4's update.
  - "Where permission is required by these Terms of Use for use of this Site or the Contents, you may apply for
    permission by writing to SLA at 55 Newton Road, #12-01 Revenue House, Singapore 307987".
- **SLA answers on ask.gov.sg.**
  - "I am a web designer … How do I go about it?": "Please refer to our OneMap APIs page at
    http://www.onemap.sg/api/help/ . The Terms and Conditions for the use of APIs can be viewed at API Terms of
    Service (onemap.gov.sg) . Do contact OneMap Helpdesk at onemap@sla.gov.sg should you need any assistance."
  - "How may I obtain approval for the use of OneMap?": quoted in §4.3's update. It adds: "For assistance, please
    contact us at 1800 323 9829 or email us at onemap@sla.gov.sg".
  - Two answers about printed and e-mailed maps ask for "the OneMap logo and the copyright statement "© 2013 OneMap"".
    That is a different use from the app's.
- **LTA website Terms of Use.** The three quotes in A-5 §4 are verbatim.
- **LTA DataMall API Terms of Service.**
  - Clause 1 and clause 10(b) as quoted in A-5 and A-4: verbatim.
  - New, clause 4: "You can call the APIs up to 10 million times a day (the "Threshold"). If you exceed the Threshold,
    the Agency may, without warning, suspend or terminate your right to Use the API at its discretion."
  - Clause 8(b): no rights over "any intellectual property found in content accessible through the APIs".
- **LTA DataMall website Terms of Use.**
  - Clause 5 repeats LTA's "seek permission in writing" clause.
  - Clause 13: "Except as set forth below, caching and links to, and the framing of this website or any of the
    Contents are prohibited."
  - Clause 23: "The Contents of this website are strictly for your personal and non-commercial use only."
  - These clauses cover the website's Contents. The API datasets are under the API Terms of Service and the SODL [A].
- **busrouter-sg and arrivelah READMEs.** The quotes in A-5 §4 and A-4 §3 are verbatim as rendered. The raw Markdown
  writes the lta.gov.sg URL as `<https://www.lta.gov.sg/>`.

### 9.3 Corrections to earlier text

| Where | Earlier | Verified |
|---|---|---|
| §4.3, registration checkbox | "I acknowledge and accept the [Privacy Statement] and [API Terms of Service] of OneMap." | Not verbatim. The full text is in the §4.3 update: it adds an "Open Data Policy" and consent to receive SLA's information |
| §4.4, last row | "Terms of Use clause 2 and 11" | The "as is" disclaimer is clause 10 (clause 4(f) cites "Clause 4(e)", which fixes the numbering) |
| §4.5, "Tiles, Android" | "kept on disk up to the 50 MB cap … until trimmed by the cap" | The cap is applied when the cache instance is created (the first map opening in each run of the app); during a run the cache may exceed it (flutter_map source) |
| §3, ask.gov.sg | Not verified (403) | Verified raw (§9.1) |
| §3, OSMF and Photon | WebFetch quotes | Verified raw; the quotes in §6 are verbatim |
| §1 and §4.1, API terms | "Use of the datasets is governed by the Singapore Open Data Licence." | Verbatim, but it follows "The Agency may offer datasets through an API." The terms also exclude "any intellectual property found in content accessible through the APIs". Whether search results are SODL "datasets" is open (§10, Q2) |
| A-4 §3 and A-5 §4 | The SODL, DataMall, LTA, OneMap and README quotes | All verbatim; no correction |

## 10. Remaining uncertainty: who can settle each question

"Data owner" means a written answer or permission from the body that owns the data. "Legal advice" means a qualified
lawyer's reading of the published terms. Advice can assess risk; it cannot grant a permission the terms reserve to the
owner. ArriveLah's and busrouter's maintainer can describe their own arrangements but cannot grant LTA's or SLA's
rights.

| # | Open question | Docs | Who can settle |
|---|---|---|---|
| Q1 | May a public, client-only Web and Android app call OneMap search **without a token**, while the docs mark the token "Required"? | A-5d §4.1 | **SLA** only |
| Q2 | Do the API Terms of Service, and so the SODL, govern search results (and tiles), next to or instead of Terms of Use 3(b)? Are the results SODL "datasets"? | A-5d §4.1, §9.2 | **SLA**; legal advice can give a reading of the text |
| Q3 | Is the Android disk tile cache, or the 5-minute in-memory search cache, "store" under 3(b)(i)? | A-5d §4.5 | **SLA**; legal advice can give a reading |
| Q4 | Who must register, for which APIs; what replaced the "Developer Agreement"; what is the "Open Data Policy" the checkbox names? | A-5d §4.3 | **SLA** only |
| Q5 | What attribution does SLA want for search: wording, an SODL notice, and which links (given Terms of Use 8(b) and SLA's website hyperlink clause)? | A-5d §4.4 | **SLA** |
| Q6 | May the developer keep calling OneMap from the hand-run dev tools for local development and evaluation? | A-5d §2, §7 | **SLA** |
| Q7 | Were the captured OneMap search results committed in `test/fixtures/onemap/` (and kept in history) permitted? | A-4 | **SLA** (permission) or **legal advice** (risk; history removal) |
| Q8 | **busrouter / LTA website content:** does LTA's "To use the Contents of this website … the user must seek permission in writing" reach stop, service and route-line data obtained through sgbusdata and busrouter.sg? Is the app's use permitted? | A-5 §5.1 | **LTA** (permission; letter drafted on branch `docs/lta-clarification-draft`, not sent); **legal advice** on whether the clause binds third-party recipients and how far stop codes, positions and stop orders are protected |
| Q9 | Does LTA's "caching … prohibited" clause reach the app's in-session copy and the browser's HTTP cache of the busrouter files? | A-5 §4 | **LTA**; legal advice can give a reading |
| Q10 | **ArriveLah / DataMall proxy:** is DataMall Bus Arrival data relayed by ArriveLah (with the operator's AccountKey, which clause 10(b) says to keep confidential; clause 4's Threshold of 10 million calls a day binds the caller) a dataset the app may use under the SODL? Does the app's notice then satisfy the licence? | A-5 §5.1, A-4 | **LTA DataMall** (data owner); **legal advice** on whether a proxy-obtained copy is licensed |
| Q11 | Third-party patches inside the busrouter data: SimplyGo name corrections, OneMap and Citymapper route patches | A-5 §5.4 | **LTA** (SimplyGo is LTA's fare system [A]), **SLA** (OneMap patches); **legal advice** for Citymapper, which is neither |
| Q12 | Do the captured third-party responses still in Git history (busrouter: A-2, A-3; ArriveLah and OneMap: A-4) need removal? | A-4, busrouter audit | **Legal advice**; the data owners could permit them instead |
