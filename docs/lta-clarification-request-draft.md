# Draft: Clarification Request to LTA on Bus Data Use (owner decision A-5a)

**Status: DRAFT for the owner's review. NOT SENT.** Nothing in this file has been sent to LTA or anyone else, and it
must not be sent without the owner's explicit approval. Until LTA answers, the app's runtime use of the busrouter
data is **not** treated as permitted (`docs/runtime-data-rights-assessment.md` §5.1).

## Notes for the owner (not part of the letter)

- **Why this form.** LTA's website terms (last updated 3 December 2021) say: "To use the Contents of this website or
  any part thereof, the user must seek permission in writing, stating the Contents for use; intent of use; manner of
  use; time frame of use and identity of the user." The letter states each of the five, in that order (§1–§5), then
  asks the questions.
- **Channel: not confirmed.** I have not checked which LTA address or form handles permission requests for website
  content, or whether LTA DataMall has its own contact. Please pick the channel; LTA's "Contact Us" page on
  lta.gov.sg is the likely start.
- **Placeholders** are in square brackets: your name, contact address, repository and app links. Decide whether to
  give the public app's URL.
- **Facts in the letter** come from the repository on 2026-11-07: the three endpoints (`app_config.dart`), what is
  shown (`docs/runtime-data-rights-assessment.md` §2), the provenance chain (§3), and the start date (the first
  busrouter code, 2 October 2026). Please check the "users" sentence: the repository does not record how many people
  use the app.
- **Before sending, check the repository sentence in §3.** `docs/probe-output/curl-probes.txt` and `map-probes.txt`
  still hold the first 220 bytes of each busrouter file (October 2026 probes). If they stay, add "and some
  development logs hold the first few lines" to that sentence.
- **Left out on purpose.** Live arrival times (LTA DataMall via ArriveLah) are not asked about: DataMall data is
  under the Singapore Open Data Licence, and the open point there concerns ArriveLah, not LTA's website terms. Add
  question 8 below if you want LTA's view on it too.
- **Optional question 8:** "The app also shows live bus arrival times from LTA DataMall's Bus Arrival API, obtained
  through ArriveLah, a community service that relays it. The app shows the Singapore Open Data Licence notice and
  link. Does LTA consider data relayed in this way to be covered by that licence?"

---

**Subject:** Request for permission and clarification: use of LTA bus stop, bus route and route-line data in a
personal, non-commercial app

Dear Sir or Madam,

I am writing, as your website's terms of use ask, to seek permission in writing, and some clarification, for the
use of LTA bus data in a small personal project. The details below follow the order in your terms: the contents,
the intent, the manner, the time frame and my identity.

**1. Contents for use**

- Bus stops: stop code, name and position.
- Bus services: service number, name, directions, and the order of stops in each direction.
- Bus route lines: the drawn path of each service direction.

I understand that this data was first published on lta.gov.sg (the bus stop, bus service and bus route XML and KML
files), and that it reaches my app through two community projects that compile and re-host it: `sgbusdata`
(github.com/cheeaun/sgbusdata) and `busrouter.sg`. My app downloads these files from busrouter.sg:

- `https://data.busrouter.sg/v1/stops.min.json`
- `https://data.busrouter.sg/v1/services.min.json`
- `https://data.busrouter.sg/v1/routes.min.json`

I do not know whether those projects hold LTA's permission, and I do not rely on them for it.

**2. Intent of use**

"Singapore Smart Commute" is a personal, non-commercial hobby project. It has no advertising, no fees and no sign-in,
and it has no server, so it collects no user data. It shows current weather and air quality, lets a user search for a place, and suggests
direct bus journeys with live arrival times and the nearest MRT station.

**3. Manner of use**

- The app is a Flutter application for the Web and for Android. It has no server of its own.
- Each user's device downloads the files above directly, at most once per session, and only when the user asks for a
  bus journey (route lines only when the user opens the map).
- From the data, the app shows the suggested boarding and alighting stops (code, name and position), the service
  number and its direction, the number of stops, and, on an optional map, the stops and the bus's route line.
- The app does not republish the files: it does not host, bundle or offer them for download. Its source code is
  public at [repository link]. Its tests of this data use made-up data; earlier versions held small extracts of the files, which
  remain in the repository's history.
- The app's data credits show "Bus data: busrouter.sg (data © LTA)". I will change this to any wording
  LTA requires.
- For development only, I have also downloaded the same files to my own computer, to test and to measure the speed of
  journey planning. These copies are not shared or published.

**4. Time frame of use**

From October 2026, ongoing, with no fixed end date. I will stop or change the use if LTA asks.

**5. Identity of the user**

[Full name], an individual developer in Singapore, acting in a personal capacity. Contact: [email address]. App:
[public app link, if you choose to give it].

**Questions**

1. May a public Flutter Web and Android app, as described above, use this data at runtime? If so, on what terms?
2. Is it acceptable that the app obtains the data through busrouter.sg (that is, from `sgbusdata`) rather than from
   lta.gov.sg?
3. Is attribution required? If so, what wording and placement do you require?
4. Are there any other conditions, for example on how often the data may be downloaded, on storing it on the user's
   device, or on showing it on a map?
5. May I keep downloading the data to my own computer for local development and benchmarking, without publishing
   it?
6. Is there an officially licensed source for this data? I understand that LTA DataMall's `BusStops` and `BusRoutes`
   datasets are available under the Singapore Open Data Licence. Is there also an official source for bus route
   lines?
7. If the data may not be used in this way, please let me know, and I will stop using it.

Thank you for your time. I am happy to give any further details.

Yours faithfully,

[Full name]
[Email address]
