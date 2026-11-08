# Draft: Clarification Request to SLA on OneMap Use (owner decision A-5d-1)

**Status: DRAFT for the owner's review. NOT SENT.** Nothing in this file has been sent to SLA, OneMap or anyone else,
and it must not be sent without the owner's explicit approval. Until SLA answers, the app's tokenless use of OneMap
search is **not** treated as permitted. Meanwhile the status quo is accepted and documented
(`docs/onemap-runtime-assessment.md`, S1).

## Notes for the owner (not part of the letter)

- **Why this form.** OneMap's terms prescribe no form for a permission request.
  - OneMap's API docs (workshop page, read 2026-11-07) ask token enquirers for "Name of Application", "Endpoints used"
    and "Expected Traffic". §1–§3 of the letter give those three.
  - §4–§6 add the manner, duration and identity. SLA's own website terms list these for a permission request about
    sla.gov.sg content, and LTA's letter uses them too.
- **Proposed channel: `onemap@sla.gov.sg`, to be verified again before sending.**
  - `onemap@sla.gov.sg` appeared on the OneMap API docs' "Contact Us" page ("If you have any questions, please reach out
    to us. … Feel free send us feedback at onemap@sla.gov.sg"), on the workshop page and in the basemap docs' footer.
  - SLA's answers on ask.gov.sg also give the hotline 1800 323 9829.
  - SLA's postal address in its website terms (55 Newton Road, #12-01 Revenue House, Singapore 307987) is for
    permission to use **sla.gov.sg** content, not OneMap. It is a fallback only.
  - All read raw on 2026-11-07 (`docs/onemap-runtime-assessment.md` §9) and not re-read since. Open the OneMap
    "Contact Us" page again just before sending and check that the address is still there.
- **Placeholders** are in square brackets: your name and email address only.
- **Repository and use** (checked 2026-11-08; framing decided by the owner on 2026-11-08):
  - the repository is https://github.com/WeeJC8954/sg-smart-commute, public and not archived on GitHub;
  - no public deployment of the app was found: no GitHub Pages site, homepage URL, deployment or release, and no
    hosting address in the repository's docs;
  - so the letter says, with one meaning throughout (owner, 2026-11-08): the application is currently intended for
    personal use; future sharing with a small number of family members or friends may be considered; no sharing or
    public release is currently scheduled; there is no committed public-release date. Questions about sharing or a
    public release are put as hypothetical. It gives no app link. If any of this changes before you send, revise
    §1, §3, §5 and question 1.
  - §3's user sentences are the owner's wording of 2026-11-08, for this proposed revision only. They do not replace the
    email already sent to SLA, which keeps its own wording (the sent text is to be archived when the owner provides it).
- **Facts in the letter** were rechecked against `main` at `725dc79` (2026-11-08):
  - the endpoints, pacing and cache values (`lib/core/config/app_config.dart`: `OneMapEndpoints`, `PlaceSearchConfig`,
    `OneMapRateLimit`, `BasemapEndpoints`, `MapConfig`);
  - the tile provider and the map credit (`lib/features/map/presentation/basemap.dart`; since `bbd9329` only the link
    widget was renamed for reuse, with no change to the credit);
  - the search credit under the results (`place_search_field.dart`) and in the footer (`lib/app/home_screen.dart`);
    the footer's Singapore Open Data Licence notices (C-6) name only the NEA, MRT and arrivals data, not OneMap;
  - the tile cache's timing (`docs/onemap-runtime-assessment.md` §4.5 and its correction table);
  - the start dates: first OneMap search code 1 October 2026 (`654e1cb`), first map code 3 October 2026 (`a03ff5d`).
- **What is in the repository (question 9).** Checked at `725dc79`:
  - the eight test files in `test/fixtures/onemap/` were replaced by made-up data (A-4b, PR #98, merged 2026-11-07,
    `8829d48`);
  - the 51-query `docs/probe-output/place-search-eval.json` was removed and the probe outputs' body heads redacted
    (PR #101, merged 2026-11-07, `98f3652`; `docs/captured-data-inventory.md` §4);
  - five map-spike screenshots showing OneMap Default and Night tiles (`docs/probe-output/map-spike/`, added in
    `6dc0fd3`) were removed in PR #106 (C-3, merged 2026-11-08, `f02ac08`);
  - the three README screenshots, which showed OneMap tiles (`docs/images/`, added in `34a1309`), were replaced by
    screenshots over made-up data and invented tiles in PR #108 (C-4, merged 2026-11-08, `5a05ca2`). The new ones show
    the app's standard OneMap credit line but no OneMap tile or logo, and the README says the credits describe no
    real data there;
  - all of the above remain in Git history (C-7: no history rewrite).
- **Expected traffic is not known.** The repository does not record how many people use the app. Each running copy
  sends at most one search request a second, and fewer in practice (it waits for a pause in typing and caches
  results). §3 uses the owner's sentence (2026-11-08) and gives no number.
- **Disclosure.** The letter says plainly that the app calls search without a token although the docs require one.
  That is the point of asking. Do not send it if you are not willing to accept "no" and switch search off or replace
  it (`docs/onemap-runtime-assessment.md` §6, S4).
- **Left out on purpose:** bus data and arrivals (LTA's, not SLA's; see `docs/lta-clarification-request-draft.md`).
- **Question 9 (Git history), kept by the owner on 2026-11-08,** asks SLA's view on the OneMap material in Git history.
  Its facts are in "What is in the repository" above.

---

**Subject:** Clarification on using OneMap search and map tiles in a personal, non-commercial app without a server

Dear OneMap team,

I am a hobby developer, and I would like your guidance on whether my small app uses OneMap in a way SLA accepts. I
would rather ask than assume. The details follow the points your API documentation asks for: the application, the
endpoints used and the expected traffic. Then come the manner of use, the duration and my identity.

**1. Name of application**

"Singapore Smart Commute": a personal, non-commercial hobby project. The application is currently intended for my
personal use. I may consider sharing it with a small number of family members or friends in the future, but no such
sharing or public release is currently scheduled, and there is no committed public-release date. Its source code is
public. It has no advertising, no fees and no sign-in, and it has no server, so it collects no user data. It shows
current weather and air quality, lets a user search for a place, and suggests direct bus journeys with live arrival
times, the nearest MRT station and an optional map.

**2. Endpoints used**

- Search: `https://www.onemap.gov.sg/api/common/elastic/search?searchVal=…&returnGeom=Y&getAddrDetails=Y&pageNum=1`.
  The app sends **no token**, because it has no way to keep one confidential (see §4).
- Map tiles: `https://www.onemap.gov.sg/maps/tiles/Default/{z}/{x}/{y}.png` (light theme) and `…/Night/…` (dark
  theme), zoom 11–19, inside the bounds given in your basemap documentation.
- The OneMap logo: `https://www.onemap.gov.sg/web-assets/images/logo/om_logo.png`, as your attribution snippet gives
  it.

The app does not call reverse geocoding, routing or any other OneMap service.

**3. Expected traffic**

The application is currently intended for my personal use. I may consider sharing it with a small number of family
members or friends in the future, but no such sharing or public release is currently scheduled. Each running copy of
the app:

- searches only after the user types at least 3 characters (or a 6-digit postal code), waits 350 ms after the last
  keystroke, reads page 1 only, and sends **at most one search request per second**;
- remembers each search's results in memory for 5 minutes (at most 50 searches), so repeated searches send nothing;
- requests tiles only while the user has the map open, for the area on screen and a one-tile margin around it. It
  never prefetches or downloads tiles for offline use, and never retries a failed tile automatically.

**4. Manner of use**

- The app is a Flutter application for the Web and for Android. It has **no server of its own**: each user's browser
  or phone calls OneMap directly. Its source code is public at https://github.com/WeeJC8954/sg-smart-commute.
- **Why no token.** I understand the search documentation says the Search API "now requires token-based
  authentication". A token comes from an account's email and password, and your API Terms of Service ask that
  credentials be kept "secure and confidential". An app with no server can only hold a token by putting it, or the
  password behind it, in its public code, so I have not done that. If OneMap starts refusing search without a token,
  the app shows "Place search is unavailable: OneMap now requires sign-in, which this app does not use" and does not
  work around it.
- **Storage.**
  - Search results are held in memory only, as described in §3, and never written to the device.
  - The Android app keeps map tiles in the phone's cache folder (trimmed to about 50 MB the first time the map
    opens in each run of the app). It follows the `Cache-Control` header your tile server sends: a tile is reused for up to 4 hours, then
    checked with your server again before it is shown, and never shown out of date when the check fails. The phone may
    clear that folder at any time.
  - The Web version keeps nothing itself; the browser's normal cache applies.
- **Attribution.**
  - Below the map, always visible: the OneMap logo and "OneMap © contributors | Singapore Land Authority", with
    "OneMap" linked to https://www.onemap.gov.sg/ and "Singapore Land Authority" to https://www.sla.gov.sg/, as in
    your snippet.
  - Under each list of search results and in the app's credits: "Place search: OneMap © Singapore Land Authority".
  - I will change either to the wording you require.
- **Development.** While building the app, I also run a few small scripts by hand on my own computer. They send a
  handful of searches and tile requests to check that the app still works. They never run automatically, and their
  output is not published.

**5. Duration**

In personal use and development: search since October 2026, map tiles since October 2026, ongoing, with no fixed end
date. No sharing or public release is currently scheduled, and there is no committed public-release date. I will stop
or change the use if SLA asks.

**6. Identity**

[Full name], an individual developer in Singapore, acting in a personal capacity. Contact: [email address].

**Questions**

1. **Search without a token.** May an app like this, with no server, keep calling the Search API without a token for
   my personal use? If not, is there an approach SLA accepts for an app that cannot keep a credential confidential?
   Or is OneMap search not available to such apps? Hypothetically, if I were later to share the app with a small
   number of family members or friends, or to release it to the public, would the answer differ?
2. **Registration.**
   - Your Terms of Use say that anyone who wishes to build web applications "using the API and the Data" must
     complete the online registration and accept the "Developer Agreement". Does this apply to an app that uses only
     the map tiles, which need no token?
   - The Developer Agreement's page now says "We have moved!". Do the API Terms of Service now take its place? What
     is the "Open Data Policy" named on the registration form?
3. **Which terms apply.** Are the search results and the map tiles governed by the API Terms of Service and the
   Singapore Open Data Licence, by the OneMap Terms of Use, or by both?
4. **Caching.**
   - Is the Android tile cache described in §4 acceptable under clause 3(b) of the Terms of Use?
   - Is the 5-minute in-memory cache of search results acceptable?
   - Would you prefer different limits?
5. **Attribution.** What wording, links and placement do you require for search results and for the map?
   - If the Singapore Open Data Licence applies, may I link to its copy on data.gov.sg? Your Terms of Use allow links
     only to OneMap's home page.
   - May the map credit keep its link to https://www.sla.gov.sg/, as your snippet gives it?
6. **Development use.** May I keep running the occasional hand-run test scripts described in §4?
7. **Rate limits.** Is there a request rate or daily volume you would like an app like this to stay under?
8. **Alternatives.** If this use is not acceptable, does SLA recommend another way for a small app with no server to
   offer place search or map tiles? I will stop using any part you ask me to.
9. **Git history.** Earlier versions of the app's public repository contained OneMap material:
   - saved search responses: a few in the tests, and, in development logs, the results of a 51-query search
     evaluation and the first characters of a few responses;
   - screenshots showing OneMap map tiles: five from an early map test, and three in the README.

   All were replaced by made-up data or removed in November 2026; the README's screenshots now use made-up places and
   invented map tiles. The earlier material remains in the repository's history. May it remain there, or should it be
   removed?

Thank you for your time. I am happy to give any further details.

Yours faithfully,

[Full name]
[Email address]
