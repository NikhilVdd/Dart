# Dart: Project Context

## Before doing anything
This repo already has code and context. At the start of every session:
1. Scan the repo: README files, existing docs, folder structure, package or dependency files, existing models and types, API routes, tests, and any config.
2. Identify the existing backend language, framework, database, frontend setup, test framework, and code conventions.
3. Look for existing definitions of runners, users, orders, requests, stores, and locations.
4. Summarize what you found in a few lines before writing code.

Rules:
- Use the existing stack, patterns, and naming. Do not introduce a new language, framework, or major library without asking first.
- Extend existing types and models instead of creating parallel ones.
- If something in this file conflicts with the repo, the repo wins. Flag the conflict instead of forcing a change.
- If the repo has no answer for something (for example, no mapping library yet), propose an option and ask before adding it.

## What Dart is
Dart is a peer-to-peer campus delivery app at UC Berkeley. "Dart" is the company name, not the Dart programming language (unless the repo is written in Dart).

Students who are already heading somewhere ("runners," also called "darters") pick up items from stores or restaurants for other students and drop them off along the way. Because runners are already making the trip, delivery stays cheap. Dart does not own stores or inventory.

The core technical problem: given delivery requests and runners with known starting points, destinations, and availability, find which runner can fulfill each request with the least disruption to their original trip.

## System components
1. Routing and detour: computes a runner's original route, the modified route with a store pickup and drop-off added, and the extra time and distance. Picks the best store when an item is sold at several locations. Flags whether the detour is within the allowed maximum.
2. Matching: takes requests, runners, and detour estimates; filters eligible runners; ranks them; assigns across many requests at once; handles declines, conflicts, and requests with no match.
3. Frontend prototype: browser geolocation (with permission), manual or simulated location entry, and a map showing original and modified routes.

Matching never computes routes itself. It only consumes detour estimates through a shared interface.

## The shared contract between routing and matching
Matching and routing must agree on one interface: given a runner and a request, return a detour estimate. Name and shape it to fit the repo's conventions. It must carry at least:
- runner and request identifiers
- which store was chosen
- original route distance and duration
- modified route distance and duration
- added distance and added duration
- estimated pickup time and estimated drop-off time
- feasible yes/no, and a reason code when not feasible
- route geometry (for the map only)

Runner data needs at least: start location, destination, departure time, availability end time, max acceptable detour, and status.
Request data needs at least: one or more store options, drop-off location, deliver-by time.

There must be two implementations of the interface:
- A simulated one: deterministic, no network, based on straight-line distance with a road factor. Used for matching development and tests.
- A real one: backed by the routing component.

## Constraints
- No paid APIs or subscriptions.
- Tests must not depend on the network. Use simulated or recorded route data.
- No continuous live tracking or background location.
- Every matching decision must come with a plain-English explanation of why a runner was chosen or rejected.

## Ownership
- Kanishk: shared contract, simulated detour provider, multi-store selection and feasibility rules, matching, integration, scenarios, tests, docs.
- Rijul: routing and detour engine, real detour provider, geolocation, map visualization.
Do not edit code owned by the other person without flagging it in your summary.

## Finishing any task
Run the existing test suite plus new tests, fix failures, then summarize: what changed, what is left, and any change to the shared contract the other owner needs to know about.