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

## 1. Summary

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
  and [API Terms of Service] of OneMap." It posts to `/api/public/user/registerUser` and `confirmRegistration`
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

### 4.4 Attribution

| Requirement | Source | What the app shows | Status |
|---|---|---|---|
| OneMap logo and "OneMap © contributors \| Singapore Land Authority", linked, with base maps | Basemap docs; snippet `code-attr.txt` (2026-11-07) | The 20 × 20 logo, the same text, "OneMap" → `https://www.onemap.gov.sg/`, "Singapore Land Authority" → `https://www.sla.gov.sg/`, always visible below the map | **Met [C]** |
| Do not remove or obscure SLA notices and logos | Terms of Use 3(b)(ii) | Never collapsed, covered or removed (widget test) | **Met [C]** |
| Links only to the home page, with no implied endorsement | Terms of Use 8(a)–(b) | Links to the home page only; no endorsement wording | **Met [A]** |
| A "conspicuous notice acknowledging the source of the datasets" with "a link to the most recent version of this Licence" | SODL v1.0, if it governs API data (API Terms of Service) | "Place search: OneMap © Singapore Land Authority": source named, no licence notice or link | **Gap [A]**, if the SODL applies |
| Search-specific attribution | API docs | None found in the search docs | — |
| SLA (service level) | Terms of Use clause 2 and 11; API terms "Disclaimers" | No service level is offered ("as is", "as available"; the API terms disclaim "service levels, continued availability") | Nothing to show [C] |

Terms of Use 3(b)(ii) also bars "use" of SLA's logos except as 3(a) allows, while the basemap docs require the logo.
The docs' explicit requirement is read as the permission for that use [A].

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

## 6. Options

| ID | Option | What it involves | Against the hard constraints | Assessment |
|---|---|---|---|---|
| S1 | **Accept and document** (status quo): keep tokenless search, the enforcement handling and the tiles | This document; owner's decision | Fits | Keeps the app. The documented requirement stays unmet; enforcement may come without notice, and the app then shows "requires sign-in" with no place search. Revisit before any wider release |
| S2 | **Ask SLA in writing** (OneMap's contact page, `http://www.onemap.gov.sg/apidocs/contactus`, named in the API docs): tokenless search from a public client-only app at ≤ 1 request/s; whether the SODL governs API data; the Android tile cache | A letter from the owner, **drafted only, not sent** | Fits (no change unless SLA answers) | The only route to an authoritative answer. SLA may say no, or not answer |
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
