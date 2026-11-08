# Draft: Clarification Request to LTA on Bus Data Use (owner decision A-5a)

**Status: DRAFT for the owner's review. NOT SENT.** Nothing in this file has been sent to LTA or anyone else, and it
must not be sent without the owner's explicit approval. Until LTA answers, the app's runtime use of the busrouter
data is **not** treated as permitted (`docs/runtime-data-rights-assessment.md` §5.1).

## Notes for the owner (not part of the letter)

- **Why this form.** LTA's website terms (last updated 3 December 2021) say: "To use the Contents of this website or
  any part thereof, the user must seek permission in writing, stating the Contents for use; intent of use; manner of
  use; time frame of use and identity of the user." The letter states each of the five, in that order (§1–§5), then
  asks the questions.
- **Channel: LTA's Contact Us online form, yours to confirm.**
  - LTA's Contact Us page (https://www.lta.gov.sg/content/ltagov/en/contact_us.html, read 2026-11-08) says: "Send your
    feedback or submit your enquiries via our online form", linking to
    https://www.lta.gov.sg/content/ltagov/en/contact_us/contact_form.html. It lists no email address, and the hotline
    1800 2255 582 (+65 6225 5582 from overseas) for LTA-related matters.
  - The page does not mention data licensing or permission to use website content, and LTA DataMall's own contact
    was not checked. So the letter's first paragraph asks for the enquiry to be passed to the team that handles
    permission for LTA data, such as a licensing or DataMall team.
  - **The form was inspected on 2026-11-08** (read only, nothing submitted; `docs/testing.md`, 2026-11-08 terms row):
    - no category field; the fields are: reply wanted (yes/no), salutation, name (letters, spaces and `_ . ' -`
      only), contact number (required when a reply is wanted), email entered twice, previous feedback number,
      subject (at most 150 characters), message (at most 5,000 characters), incident location ("Not Applicable"),
      attachments, and a CAPTCHA;
    - the subject and message reject any non-ASCII character other than curly quotes and dashes, so `§` and `©`
      fail;
    - attachments: doc, docx, ppt, pptx, xls, xlsx, pdf, txt, img, jpg, jpeg, png, gif or zip; at most 20 MB in
      total; file names of at most 50 characters;
    - LTA aims to reply "within 5 working days", or in 14–20 days for complex cases.
  - The letter (about 6,700 characters, with `§` and `©`) does not fit the message box. **Approved approach
    (owner, 2026-11-08):** the subject line in the subject field, the approved ASCII cover note (about 750
    characters) in the message, and this letter attached as a PDF. The send-ready copies are kept outside the
    repository, because they will carry your details.
- **Placeholders** are in square brackets: your name and email address only. The form also asks for a contact
  number if you want a reply; it is not in the letter.
- **Repository and use** (checked 2026-11-08; framing decided by the owner on 2026-11-08):
  - the repository is https://github.com/WeeJC8954/sg-smart-commute, public and not archived on GitHub;
  - no public deployment of the app was found: no GitHub Pages site, homepage URL, deployment or release, and no
    hosting address in the repository's docs;
  - so the letter describes current personal, non-commercial use, possible limited sharing with family and friends,
    no immediate plans for a public release, and a possible later public release with no committed date, and gives
    no app link. If any of this changes before you send, revise §2, §4 and question 1, and the cover note.
  - The approved cover note says "under development and intended for public release"; it needs the same change
    and your approval again before sending.
- **Facts in the letter** were rechecked against `main` at `725dc79` (2026-11-08):
  - the three endpoints and the credit (`lib/core/config/app_config.dart`, `lib/app/home_screen.dart`);
  - the loading and retry rules (`busNetworkProvider`, `routeGeometryProvider` and `MapExpanded.show`);
  - what is shown (`docs/runtime-data-rights-assessment.md` §2) and the provenance chain (§3);
  - the start date (the first busrouter code, `50de76a`, 2 October 2026).
- **What is in the repository (§3).** Checked at `725dc79`:
  - the busrouter test files were replaced by made-up data on 2026-11-06 (`test/fixtures/busrouter/`);
  - the first 220 bytes of each busrouter file in `docs/probe-output/curl-probes.txt` and `map-probes.txt` were
    redacted in PR #101 (merged 2026-11-07, `98f3652`; `docs/captured-data-inventory.md` §4);
  - the README screenshots, which showed stop names, a ride line and live arrival times, were replaced by
    screenshots over made-up data in PR #108 (merged 2026-11-08, `5a05ca2`); the map-spike screenshots, two of which
    drew a busrouter ride line, were removed in PR #106 (merged 2026-11-08, `f02ac08`);
  - all of these remain in Git history (C-7: no history rewrite);
  - still in the tree, kept provisionally (C-5): the E5 benchmark's expected output
    (`tool/e5_transfer_bench/expected_results.txt`) and its named pairs (`bench.dart`), with stop codes, service
    numbers, road names and counts derived from the data. §3 says so; LTA's answer may reopen C-5.
  - Question 7 (owner, 2026-11-08) asks whether everything §3 discloses may remain in the repository, including in
    Git history: the benchmark output and pairs, the earlier test extracts, the development-log lines and the
    screenshots.
- **Sources other than LTA (§1).** The source list comes from `docs/runtime-data-rights-assessment.md` §3 (sgbusdata's
  scripts, read 2026-11-06). LTA can only answer for its own content: the SimplyGo name corrections and the OneMap and
  Citymapper route patches stay open whatever LTA says, and the OneMap part belongs with the SLA letter. The app's
  credit "Bus data: busrouter.sg (data © LTA)" names only LTA, while busrouter's README credits "LTA © OneMap © OSM
  contributors"; that wording is your decision, not part of this letter.
- **Question 8 (ArriveLah), kept by the owner on 2026-11-08.** Live arrival times come from LTA DataMall's Bus Arrival
  API through ArriveLah. The open point there concerns ArriveLah, not LTA's website terms, so §1–§5 leave it out and
  question 8 asks LTA's view. The facts in it: `ArriveLahEndpoints` and `arrivalsLicenceNotice` in `app_config.dart`;
  the footer notice links to https://data.gov.sg/open-data-licence.
- **Closing sentence.** "If the data may not be used in this way…" was question 7; it asks nothing, so it now follows
  the questions unnumbered.

---

**Subject:** Request for permission and clarification: use of LTA bus stop, bus route and route-line data in a
personal, non-commercial app

Dear Sir or Madam,

I would be grateful if this enquiry could be passed to the team that handles permission to use LTA data, such as a
licensing or DataMall team.

I am writing, as your website's terms of use ask, to seek permission in writing, and some clarification, for the
use of LTA bus data in a small personal project. The details below follow the order in your terms: the contents,
the intent, the manner, the time frame and my identity.

**1. Contents for use**

- Bus stops: stop code, name and position.
- Bus services: service number, name, directions, and the order of stops in each direction.
- Bus route lines: the drawn path of each service direction.

The data reaches my app through two community projects that compile and re-host it: `sgbusdata`
(github.com/cheeaun/sgbusdata) and `busrouter.sg`. My app downloads these files from busrouter.sg:

- `https://data.busrouter.sg/v1/stops.min.json`
- `https://data.busrouter.sg/v1/services.min.json`
- `https://data.busrouter.sg/v1/routes.min.json`

From `sgbusdata`'s published scripts, I understand that the data comes from several sources, not only LTA:

- Stop codes and positions: from the lta.gov.sg bus stop XML; no other source found.
- Stop names: from the lta.gov.sg bus stop XML; some names corrected from SimplyGo.
- Stop road names: from LTA DataMall `BusStops`; no other source found.
- Services and the order of their stops: from the lta.gov.sg bus service and bus route XML; gaps filled from OneMap
  (SLA) and Citymapper.
- Route lines: from the lta.gov.sg bus route KML; gaps filled from OneMap (SLA) and Citymapper.

busrouter.sg also credits OpenStreetMap contributors, but I have not found which fields that applies to. I ask
only about the parts that come from LTA (lta.gov.sg and LTA DataMall). I understand that LTA cannot give permission
for the parts that come from SLA, SimplyGo, Citymapper or OpenStreetMap, and I will raise those separately.

I do not know whether those projects hold LTA's permission, and I do not rely on them for it.

**2. Intent of use**

"Singapore Smart Commute" is a personal, non-commercial hobby project, for my own use, which I may also share with a
few family members and friends. I have no immediate plans to release it to the public; I may do so in future, but
there is no committed date. Its source code is public. It has no advertising, no fees and no sign-in, and it has no
server, so it collects no user data. It shows current weather and air quality, lets a user search for a place, and
suggests direct bus journeys with live arrival times and the nearest MRT station.

**3. Manner of use**

- The app is a Flutter application for the Web and for Android. It has no server of its own.
- Each user's device downloads the files above directly, and only when the user asks for a bus journey (the route
  lines only when the user also opens the map). Once a download succeeds, the app reuses it for the rest of the
  session. If a download fails, the app tries again only when the user asks: by tapping Retry for the stops and
  services, or by opening the map again for the route lines.
- From the data, the app shows the suggested boarding and alighting stops (code, name and position), the service
  number and its direction, the number of stops, and, on an optional map, the stops and the bus's route line.
- The app does not republish the files: it does not host, bundle or offer them for download. Its source code is
  public at https://github.com/WeeJC8954/sg-smart-commute. Its tests of this data use made-up data, and its README
  screenshots show made-up data.
- Earlier versions of the repository held small extracts of the files (in tests, and the first few lines of each
  file in development logs) and screenshots showing stop names, a route line and live arrival times. These were
  replaced by made-up data or removed in November 2026, but they remain in the repository's history.
- The repository also holds the expected output of a development benchmark of journey planning. It lists counts and
  some bus stop codes, service numbers and road names derived from the data. The benchmark's code also lists 12 pairs
  of bus stop codes that it tests.
- The app's data credits show "Bus data: busrouter.sg (data © LTA)". I will change this to any wording
  LTA requires.
- For development only, I have also downloaded the same files to my own computer, to test and to measure the speed of
  journey planning. These copies are not shared or published.

**4. Time frame of use**

In personal use and development since October 2026, ongoing, with no fixed end date. There is no committed date for
any public release. I will stop or change the use if LTA asks.

**5. Identity of the user**

[Full name], an individual developer in Singapore, acting in a personal capacity. Contact: [email address].

**Questions**

1. May a Flutter Web and Android app, as described above, use the LTA parts of this data at runtime, for my own use
   and limited sharing with family and friends? Would the answer differ if I later released it to the public? If so,
   on what terms?
2. Is it acceptable that the app obtains the data through busrouter.sg (that is, from `sgbusdata`) rather than from
   lta.gov.sg?
3. Is attribution required? If so, what wording and placement do you require?
4. Are there any other conditions, for example on how often the data may be downloaded, on storing it on the user's
   device, or on showing it on a map?
5. May I keep downloading the data to my own computer for local development and benchmarking, without publishing
   it?
6. Is there an officially licensed source for this data? My understanding is that LTA DataMall's `BusStops` and
   `BusRoutes` datasets are available under the Singapore Open Data Licence. Is that correct, and is there also an
   official source for bus route lines?
7. §3 describes material derived from the data in the public repository:
   - in its current files: the benchmark output and the 12 pairs of stop codes;
   - in its history only: the earlier extracts in tests, the first few lines of each file in development logs, and the
     screenshots showing stop names, a route line and live arrival times.

   May each of these remain in the repository, including in its history? If not, which should be removed?
8. A question about a different source: the app also shows live bus arrival times from LTA DataMall's Bus Arrival
   API, obtained through ArriveLah (arrivelah2.busrouter.sg), a community service that relays it. The app does not
   call DataMall directly. It shows a notice naming LTA DataMall and ArriveLah, with a link to the Singapore Open Data
   Licence. Does that licence cover arrival data obtained this way? If not, what would LTA require?

If the data may not be used in any of these ways, please let me know, and I will stop using it.

Thank you for your time. I am happy to give any further details.

Yours faithfully,

[Full name]
[Email address]
