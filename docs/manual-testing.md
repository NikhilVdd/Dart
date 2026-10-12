# Manual testing with two accounts

Grab needs two people: one who asks and one who is already moving. This walks through every live
feature with two test accounts on two simulators, against the hosted Supabase project.

## Setup (once)

1. **Supabase CLI logged in and linked**: `npx supabase login` and `npx supabase link` (already done on this machine).
2. **A building group to test with:**
   ```sh
   node supabase/dev/accounts.mjs building
   ```
3. **Two simulators.** In Xcode, open `GrabApp/Grab.xcodeproj`, pick a simulator (e.g. *iPhone 16*), and Run (⌘R).
   Then switch the destination to a second one (e.g. *iPhone 16 Plus*) and Run again. The first simulator
   keeps the app installed; relaunch it from its home screen. Each simulator has its own keychain, so each
   stays signed in as a different person.

## Sign in as two people

Resend only delivers to your own address until a domain is verified, so mint codes instead:

```sh
node supabase/dev/accounts.mjs code alex@berkeley.edu "Alex Requester"
node supabase/dev/accounts.mjs code sam@berkeley.edu "Sam Runner"
```

On each simulator, tap **Continue with campus email** on the launch screen, enter the email, tap
**I already have a code**, and type the printed code. Don't tap *Email me a code* for test addresses:
Resend can't deliver to them, and requesting a new email invalidates the minted code. If a code is
rejected, run the `code` command again for a fresh one.

Use `@berkeley.edu` addresses so both accounts are linked to UC Berkeley. Unsupported domains are
rejected before an email is sent, rather than creating an account with no campus feed.

## Test plan

Mark each as you go. **A** = Alex (requester), **B** = Sam (runner).

### Profile and groups
- [ ] A and B: Profile shows the right name, initials, campus *UC Berkeley*, and **Signed in**
- [ ] A: Profile → **Edit name** → change it; the header updates
- [ ] A and B: Groups → join **The Durant**. Profile now shows Home = The Durant
- [ ] A: Profile → **Home** → pick *Unit 2*. Groups now shows a **Unit 2** building group instead of The Durant
      (created on the spot). Pick The Durant again to switch back
- [ ] A user with no building sees **Where do you live?** under *Your building* in Groups; choosing a residence joins it
- [ ] A: Groups → **+** → *New friend group* "Test crew". Open it and note the invite code
- [ ] B: Groups → **+** → *Join with invite code*. "Test crew" appears
- [ ] A sends a message; it appears on B **without pulling to refresh** (realtime). B replies; A sees it
- [ ] A adds "Lemons" to the shopping list; B checks it off; both see the strike-through
- [ ] A: touch and hold (right-click on Mac) "Lemons" → **Remove from list**. It disappears for B too
- [ ] B: open Test crew → **⋯** → **Leave group**. It disappears from B's Groups; A sees 1 member. B rejoins with the code
- [ ] With B not looking at Test crew, A sends a message: B gets a notification banner

### The core loop: a request rides on a trip already happening
- [ ] A: Home → **What do you need?** → *Request something*. "Blender under $50", pickup **Any store**,
      deliver to **Unit 2 · Cunningham Hall**, within 1 hr, reward $8, budget $50, visible to everyone on campus → **Post request**
- [ ] A: the result says no trip fits yet (B hasn't announced one)
- [ ] B: Home → Earn. The blender request is in the feed
- [ ] B: Home → **What do you need?** → *Announce a store run*. Store **Target**, heading back to **Unit 2**,
      everyone on campus, fee $6, max detour 8 min → **Announce run**
- [ ] B: the result lists the blender at **+5 min**. Tap **Accept**
- [ ] A: a notification "Sam accepted “Blender under $50”" appears. Home → the active request card flips to
      **Accepted** live; Activity → Requesting shows "Accepted by Sam"
- [ ] A: open the request → **Messages** → "Room 214, the Ninja one if they have it". B opens it from
      Activity → Helping and sees the message live; B replies. A third account can't see this chat
- [ ] B: Activity → Helping → open it → **Mark picking up**, **Mark on the way**, then **Mark delivered**.
      The sheet stays open between steps. A sees each step live in an open detail sheet, with a notification for each. B has no "complete" button: B sees "Waiting for Alex to confirm"
- [ ] A: open the request → **Confirm I received it**. The timeline shows all six steps
- [ ] B: Profile → Earnings shows **$8**, 1 completed, and a "confirmed … You earned $8" notification
- [ ] After completion the chat shows "This chat is closed" with the history kept
- [ ] B (Earn): allow location when asked. The feed is sorted from where B is when that's near campus,
      otherwise from B's home. A new request posted by A raises a "New request nearby" notification on B

### Places (Apple Maps search)
- [ ] A: New request → **Pick up from** → the sheet lists *Any store* and the places already on Grab
- [ ] Type "Berkeley Bowl" → *Add from Apple Maps* shows nearby results (nothing 15+ km away) → tap one →
      it asks what kind of place it is, with *Store* first → choose it. The form now shows it as the pickup
- [ ] B: start a new run → **Store** → search "Berkeley Bowl". It now appears under *On Grab*, not as a new result
- [ ] Search "CVS" in a store picker. The Shattuck CVS appears once, under *On Grab*
- [ ] **Deliver to** → search an apartment address (e.g. "2600 Channing Way") → add as *Residence or apartment*

### Maps
- [ ] Home (Request and Earn): a map card above the feed shows a pin per item. Requests are gold packages; runs
      are blue (storefront, friends or building icons). It fits all pins
- [ ] Tap a pin: that item's detail sheet opens. Tap the expand button: a full-screen map opens; tapping a pin
      there closes it and opens the item
- [ ] Detail sheet: the route map shows pickup (blue) and drop-off (gold) with the walking route drawn and
      "N min walk · distance" below. Moffitt → Ida Sproul should read about 11 min
- [ ] An *Any store* request shows only the drop-off pin, with "Pickup from any nearby store"
- [ ] Airplane mode: the route falls back to a dashed straight line with an "as the crow flies" distance
- [ ] Signed out (preview data): the map card and route maps still work on the sample items

### Building run
- [ ] B: announce a run from **Target** to **The Durant · Lobby**, visible to *The Durant*, fee $5
- [ ] A: Home → Request shows "Sam is going to Target" → open it → **Ask Sam to grab something** → "Paper towels", budget 9
- [ ] B: open the run → the paper towels appear under **Requests that fit this trip** → **Accept**
- [ ] B: **I'm in the store** → **Heading back** → **Finish run**

### Friend run
- [ ] B: announce a run to Trader Joe's visible to **Test crew** (the fee is hidden: friend runs are free)
- [ ] A: open it from the group → **Add to the shopping list** → "Basil". It shows in Test crew's list

### Edge cases
- [ ] A: post a request, then **Cancel request** while it's open. It moves to Cancelled in Activity
- [ ] B: accept a new request, then **Release to someone else**. A sees it back to *Waiting for someone*
- [ ] A: open your own open request. There is no Accept button (and the server refuses it anyway)
- [ ] A: post a request "needed within 15 min". Within a minute of the deadline it disappears from B's
      Earn feed and shows **Expired** in A's Activity (pg_cron runs every minute)
- [ ] Turn on airplane mode on one simulator, perform an action, and check the error alert is readable
- [ ] Profile → **Sign out**. The app returns to the launch screen
- [ ] Mint a code for a third account (e.g. `jamie@berkeley.edu`), sign in, join Test crew, accept one of
      A's requests, then Profile → **Delete account** → confirm. The app signs out; A's request is back to
      *Waiting for someone*; `accounts.mjs list` no longer shows jamie

## Cleanup

```sh
node supabase/dev/accounts.mjs list
node supabase/dev/accounts.mjs delete alex@berkeley.edu
node supabase/dev/accounts.mjs delete sam@berkeley.edu
```

Deleting a user removes their profile, requests, runs, messages' authorship, and memberships.
Groups they created stay; remove leftovers in the dashboard's Table Editor if needed.

## Where to look when something fails

- **Dashboard → Logs → API**: the failing request and its error
- **Dashboard → Logs → Postgres**: errors raised by the lifecycle functions (e.g. "run is full")
- **Dashboard → Logs → Auth**: sign-in and code problems
- **Xcode console**: decoding errors from the app
