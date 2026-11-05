# SG Smart Commute — Next-Phase Journey Routing Master Plan

**Status:** Proposed; approval required at each gate  
**Project:** Singapore Smart Commute (personal hobby project)  
**Repository:** https://github.com/WeeJC8954/sg-smart-commute  
**Platforms:** Flutter Android and Web  
**Purpose:** Self-contained handoff for a coding agent with no prior conversation context.

## 1. Mission and roadmap

Evolve the existing direct-bus suggestion app into an incremental Singapore journey planner. **Do not implement the entire roadmap at once.**

| Journey type | Scope |
|---|---|
| Direct bus | Existing behaviour; preserve |
| Bus A → Bus B | E5: next major routing enhancement |
| Direct MRT and MRT Line A → Line B | Future rail phase |
| Bus → MRT, MRT → Bus | Future multimodal phase |
| Bus → MRT → Bus | Future multimodal phase |
| Bus → MRT A → MRT B → Bus | Future multimodal phase |

The architecture should accommodate an ordered sequence of legs, but E5 implementation must remain limited to one-transfer **bus-to-bus** journeys unless explicitly approved otherwise.

## 2. Known project baseline

The application is a front-end-only Flutter app using public data sources. Confirmed current capabilities (on `main` at `600944c`) include manual/device origin selection, OneMap place search, direct-bus suggestions, live bus arrivals, nearby MRT information (not routed MRT journeys), an optional OneMap journey map, environmental information, five palettes in light/dark mode, a static estimated trip time on each direct-bus option (display-only; waiting excluded), and keyboard focus visibility. Everything else in this document is proposed, not built.

Historical E7 completion baseline (verify afresh):

- E7 implementation merge: `6178c70`.
- E7 documentation close-out merge: `600944c`.
- Flutter tests: **937 passed**; Chrome CI step: **32 passed**.
- Open issues at that point: **#80** current-location chip focus loss; **#81** retry-location focus loss; **#82** GitHub secret review. Do not change these as part of E5. #80 and #81 are addressed separately by E8 (focus continuity, `docs/e8-focus-continuity-implementation-plan.md`, planned 2026-11-05); check their current state on GitHub.
- Some physical-device and screen-reader checks remain **Not run**; Flutter licence-page package-list focus contrast remains unresolved.

The historical E5 feasibility report and E6 addendum are unavailable. Known fragments mention per-bus-leg fields `service`, `direction`, `boardIndex`, `stopCount`; reuse of E2's `estimateBusMinutes`; and an ordered leg-sequence concept. **Do not fabricate the missing reports or assign a meaning to E6.**

## 3. Mandatory zero-context discovery (Gate 0)

Before any implementation:

1. Read `CLAUDE.md`, `README.md`, `docs/architecture.md`, `docs/data-sources.md`, `docs/assumptions.md`, `docs/testing.md`, and relevant E2/E7 plans.
2. Inspect `git status`, current main HEAD, open PRs/issues, workflows and latest CI; record the current verified baseline.
3. Locate and inspect the direct-bus routing code, bus-network model, route/stop indexes, journey cards, map rendering, location search, MRT station asset, and E2 estimation logic/tests.
4. Identify exact reusable types and file paths. Do not assume names in this document are implemented classes.
5. Inspect data licensing, freshness, network requirements, CSP restrictions, memory and CPU constraints of the front-end-only architecture.
6. Produce a **discovery report** separating confirmed facts, assumptions, risks, and recommended decisions.

**Stop for owner approval after Gate 0.** No production changes, implementation PR, or unrelated work.

## 4. Proposed architecture (not yet approved)

Use a journey represented as an ordered sequence of legs, rather than hardcoding exactly two buses:

```text
JourneyPlan
  legs: [WalkLeg, BusLeg, WalkLeg, BusLeg, WalkLeg]
  totalDurationEstimate
  transferCount
  rankingInformation
```

Future extensions could introduce `MrtLeg` and explicit interchange metadata. Determine whether a Dart sealed hierarchy, immutable value objects, adapter, or an extension of current models is the smallest viable design. Avoid building unused rail abstractions in E5.

Proposed invariants:

- Legs are chronologically and geographically ordered.
- Every bus leg has a valid service, direction, boarding index, alighting position and positive stop count.
- Transfers have valid boarding/alighting points and permitted walking connections.
- No impossible, circular, duplicate or unreasonable-detour journeys.
- Durations are non-negative, finite and labelled as estimates; missing waiting-time data is never presented as known.
- Direct-bus behaviour remains backward compatible.
- Domain routing logic should be deterministic and testable with fixed datasets, independent of Flutter widgets.

Compare **(A)** an ordered-leg model introduced during E5 versus **(B)** an adapter around existing direct-bus types. Document migration cost, complexity, risk, and recommendation.

## 5. E5: one-transfer Bus → Bus

### 5.1 User-facing scope

```text
Origin → walk → Bus A → transfer (possibly walk) → Bus B → walk → Destination
```

Retain direct-bus options. Present each bus leg in order, its boarding and alighting stops, transfer instructions, walking and ride estimates, and clear waiting-time exclusions. Map both bus legs and transfer connectors.

### 5.2 Required design decisions

| ID | Decision | Required analysis |
|---|---|---|
| F1 | Transfer discovery | Shared stop vs nearby stops; direction, order and valid service continuity |
| F2 | Transfer walking | Maximum permitted distance; straight-line vs routed walking; accessibility limitations |
| F3 | Ranking | Duration, walking, transfer penalty, tie-breakers, direct-route preference |
| F4 | Waiting time | Exclude, approximate, or use live data; disclose uncertainty clearly |
| F5 | Search performance | Stop-to-service indexes, candidate pruning, duplicate elimination, bounded results and time |
| F6 | Failure modes | Missing network data, absent arrivals, invalid geometry, no route, partial API failures |
| F7 | Data and cache | Actual source coverage, first-load costs, freshness, memory, licensing and CSP impact |
| F8 | UI/Map | Multi-leg cards, transfer instructions, map geometry, themes, text scaling and accessibility |

Choose thresholds only after inspecting real network data and benchmarking representative searches; distinguish proposed limits from measured ones.

### 5.3 E5 acceptance criteria

- Finds valid one-transfer routes in deterministic fixtures.
- Enforces correct service direction and boarding/alighting order for both legs.
- Applies approved same-stop/nearby-stop transfer rules.
- Rejects loops, duplicates, impossible transfers and excessive detours.
- Keeps direct-bus results working and avoids unexpected changes in their ranking/display.
- Calculates and labels durations consistently; no invented waiting-time or live information.
- Handles no-route, missing/invalid data and API failures gracefully.
- Displays both legs and transfer on journey cards and maps in the correct order.
- Preserves ten-theme support, keyboard focus, touch, responsive layout and meaningful semantics.
- Meets measured, approved search-time and resource limits on target platforms.

## 6. Future rail phase (not part of E5)

Within the hard constraints of `CLAUDE.md` (public, keyless data readable directly from the browser, allowed by the CSP; a source that needs a key or a proxy, such as LTA DataMall, is out of scope), investigate authoritative, licensed, maintainable data for station IDs, coordinates, line membership, station order, interchanges, platform or walking connections, service constraints, and travel-time information. A list of MRT stations alone cannot establish valid routes.

Target direct MRT and MRT Line A → interchange → Line B. Distinguish stations passed, train changes, line changes, and walking connections. Never invent rail links or service frequency. Submit a separate feasibility report and approval gate before rail implementation.

## 7. Future multimodal phase (not part of E5)

Target Bus → MRT, MRT → Bus, Bus → MRT → Bus, and Bus → MRT A → MRT B → Bus. Evaluate a graph of stop/station/platform nodes with ride, walk and transfer edges, and appropriately bounded multi-criteria or shortest-path search. Do not assume Dijkstra or A* is automatically correct. Time-dependent routing requires reliable time data and a separate decision.

Propose explicit limits for transfer count, walking distance, candidates, search duration, detours and deduplication. Test the performance and route quality impact of each limit.

## 8. UX and accessibility

Users should see transport mode, service/line, boarding/alighting, transfer instructions, walking and riding time, total estimated time, and clear uncertainty/waiting exclusions. Distinguish bus, rail and walking legs without relying on colour alone. Preserve the existing explicit location-result selection behaviour. Apply E7 focus behaviour to all new interactive elements; do not claim real screen-reader testing unless performed.

A separate potential enhancement is exact **five-digit bus stop code search**. Investigate it independently; do not silently add it to E5.

## 9. Non-functional requirements

- **Performance:** benchmark representative and worst-case routes using fixed fixtures; record latency, memory, candidate count and network calls.
- **Reliability:** invalid/missing data must never yield fabricated routes; degrade gracefully.
- **Privacy/security:** preserve the front-end-only, keyless design. These are hard constraints in `CLAUDE.md` (ADR-001): no backend, proxy or serverless function, and no credentials, for any phase of this roadmap. Only the owner can change them, by changing `CLAUDE.md` and ADR-001 first; no gate here can. Do not introduce tracking.
- **Maintainability:** prefer pure routing functions, small interfaces, deterministic ranking and clear data ownership.
- **Compatibility:** preserve existing direct-bus calculations, UI and live-arrival behaviour unless explicitly approved.

## 10. Testing and verification

Use test-driven development once implementation is approved:

1. Unit tests: leg invariants, stop order, direction, transfer validation, durations, ranking, tie-breakers, duplicate/cycle rejection, invalid data.
2. Property/invariant tests where useful: no negative durations, no invalid indices, no excessive transfers, deterministic output.
3. Targeted mutation checks to prove critical tests catch deliberate defects.
4. Integration tests with fixed fake network and provider data: direct route, one transfer, no route, duplicate candidates, partial failures.
5. Widget tests: journey cards, map interactions, keyboard focus, touch, semantics, ten themes, 2× text.
6. Local gates: format, analyze, full Flutter tests, Web build, Android build and available integration tests.
7. CI: all required checks green; report exact test counts and head commit.
8. Manual Web/Android checks where possible. Mark hardware, live API and screen-reader checks **Not run** when not actually performed, with reasons.
9. Independent review and regression comparison against pre-E5 direct-bus fixtures.

Do not mark a build or manual test passed merely because unit tests pass.

## 11. Approval gates and deliverables

| Gate | Agent deliverable | Authorization |
|---|---|---|
| 0 — Discovery | Repository map, factual baseline, data assessment, open decisions | Stop; owner reviews |
| 1 — Feasibility/architecture | Alternatives, ordered-leg recommendation, routing pseudocode, complexity, benchmark proposal, risks | Stop; owner reviews |
| 2 — Plan-only PR | Exact scope, files, commits, test cases, gates, rollback plan | Stop; owner approves plan |
| 3 — Implementation | Test-first E5 changes, measured evidence, independent review, implementation PR | No merge without approval |
| 4 — Close-out | Post-merge main CI, clean tree, documentation and unresolved limits | Stop before next feature |
| 5 — Rail feasibility | Data, architecture and product decisions for MRT routing | Separate approval |
| 6 — Multimodal feasibility | Combined bus/MRT model, algorithm, limits, UX and validation | Separate approval |

Do not start future gates automatically.

## 12. Mandatory agent operating rules

- Follow repository `CLAUDE.md` and existing PR/branch/merge conventions.
- Keep the current repository as source of truth; treat this document as a proposal where it differs.
- Separate confirmed facts, inferred assumptions and owner decisions.
- Do not fabricate lost E5/E6 reports or assume E6's scope.
- No silent scope expansion, unrelated dependencies, secrets, backend or data-source changes.
- Do not touch issues #80, #81 or #82 as part of E5 unless separately approved.
- No force push or history rewrite contrary to project rules.
- No implementation before plan approval; no PR merge or secret deletion without explicit owner approval.
- Record deviations, regressions and unavailable checks honestly.
- Stop and ask when a material architectural, security, cost, UX or data-source choice is unresolved.

## 13. Standard report at each gate

Provide:

1. **Current state:** branch, HEAD, clean/dirty status, relevant PRs/issues.
2. **Work completed:** exact files/commits and evidence.
3. **Findings:** confirmed facts, assumptions, risks, alternatives.
4. **Verification:** Passed / Failed / Fixed / Not run, with reasons.
5. **Owner decisions:** numbered choices, recommendations and consequences.
6. **Next action:** the smallest next approval-controlled step.

## 14. Initial prompt for a fresh agent

> You are working on **SG Smart Commute**, a personal Flutter Android/Web hobby project. You have no prior conversation context. Read this master plan and the repository's `CLAUDE.md` before doing anything else. Your **only authorized assignment is Gate 0 discovery and E5 feasibility assessment**. Inspect current main, existing direct-bus routing, bus-network data, E2 time estimates, journey UI and map, tests and constraints. Evaluate whether an ordered journey-leg model is justified now and compare it with an adapter-first approach. Produce a factual discovery and feasibility report with measured or explicitly proposed performance limits, alternatives, risks, test strategy and owner decisions. Do not write production code, create an implementation PR, start rail/multimodal work, or merge anything. Stop for owner approval.

---

**End of master plan.**
