# Recording a demo

A three-minute, two-phone demo of Dart against the hosted Supabase project. **Alex Kim** asks for
something; **Sam Rivera** is already heading that way. Background people (Maya, Jordan, Devon, Priya)
fill the feeds, groups and chat so the app looks alive.

## One-time setup

1. **Xcode.** Install it from the Mac App Store (about 15 GB), open it once, and install an iOS simulator
   runtime when prompted.
2. **Supabase CLI login.** From the repo root, run `npx supabase login` in your own terminal (it opens a browser).
   The repo is already linked to the project.
3. **First build.** Open `DartApp/Dart.xcodeproj`, let Swift Package Manager fetch `supabase-swift`,
   choose **iPhone 16**, and press ⌘R. Then pick **iPhone 16 Plus** and press ⌘R again. Relaunch the
   first simulator's app from its home screen so both run. Put the two windows side by side.
4. **Clean status bars.** Run once per simulator while it's booted:
   ```sh
   xcrun simctl status_bar booted override --time 9:41 --batteryLevel 100 --cellularBars 4 --wifiBars 3
   ```

## Before each recording (about 5 minutes)

1. **Build the scene.** Runs close within 30–60 minutes, so do this right before recording:
   ```sh
   node supabase/dev/demo.mjs setup
   ```
   It prints a sign-in code for Alex and Sam.
2. **Sign in.** On the left simulator, go to **Profile → Sign in with campus email**, enter `grabdemo.alex@berkeley.edu`,
   tap **I already have a code**, and type Alex's code. Do the same for `grabdemo.sam@berkeley.edu` on the right.
   (Codes expire in an hour; `node supabase/dev/demo.mjs codes` prints new ones.)
3. **Starting positions.** Alex on **Home → Request**; Sam on **Home → Earn**.
4. **Record.** Press ⌘⇧5 → *Record Selected Portion* and drag over both simulators. Or record one phone with
   `xcrun simctl io booted recordVideo demo.mov` (Ctrl-C to stop).

## Script

| # | Who | Do | Shows |
| - | --- | --- | --- |
| 1 | Alex | Scroll Home: the map card with pins, Maya's Trader Joe's and Target runs, Devon's CVS run | A live campus network |
| 2 | Sam | Earn feed: charger $10, book return $4, ice & cups $6 | Paid errands nearby |
| 3 | Alex | **What do you need?** → *Request something* → "Blender under $50", **Pick up from: Any store**, **Deliver to: Unit 2**, 1 hr, reward $8, budget $50 → **Post request**. The result says no trip fits yet | Asking for an outcome, not choosing a store |
| 4 | Sam | **What do you need?** → *Announce a store run* → **Store**: search "Target" → **Heading back to: Unit 2**, everyone on campus, fee $6, max detour 8 min → **Announce run** | Movement that's already happening |
| 5 | Sam | The result shows **Blender under $50 · +5 min · $8** → **Accept** | The matching engine |
| 6 | Alex | The active card flips to **Accepted** on its own | Realtime |
| 7 | Sam | Activity → Helping → the blender → **Mark picking up**, **Mark on the way**, **Mark delivered** | Delivery lifecycle |
| 8 | Alex | Open the request → **Confirm I received it** → show the six-step timeline and the walking-route map | Requester confirmation, maps |
| 9 | Sam | Profile: earnings go from **$4 to $12** | Rewards tracking |
| 10 | Alex | Groups → **Sunday Dinner**: Maya's chat, the shared list; check off *Sparkling water* | Free friend runs |
| 11 | Alex | Groups → **+** → *New friend group* "Demo crew"; Sam joins with the invite code; send a message each way | Social layer, live chat |
| 12 | Alex | New request → **Pick up from** → search "Berkeley Bowl" → add as **Store** | Places come from Apple Maps |

## Things not to show

- A live email sign-in for anyone but the project owner (Resend only delivers to you until a domain is verified).
- Payments or notifications. Neither exists yet. Earnings are tracked, not paid.
- If step 6 doesn't update on its own, pull to refresh. Realtime hasn't been exercised on a device yet; note what happened.

## After recording

```sh
node supabase/dev/demo.mjs reset    # removes every grabdemo.* account and everything they created
```

Run `setup` again for another take. It resets first, so you can also just rerun it.
