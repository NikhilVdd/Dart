#!/usr/bin/env node
// Demo data for screen recordings, built against the linked Supabase project.
//
//   node supabase/dev/demo.mjs setup   reset, then create a live campus scene and print sign-in codes
//   node supabase/dev/demo.mjs codes   print fresh sign-in codes for the two presenter accounts
//   node supabase/dev/demo.mjs reset   delete every demo account and everything they created
//
// Presenters: Alex Kim (requester) and Sam Rivera (runner). Background: Maya, Jordan, Devon, Priya.
// All demo accounts use grabdemo.*@berkeley.edu addresses; no email is ever sent to them.
// Background activity is created as each person through the same RLS and RPCs the app uses,
// with times relative to now, so run `setup` shortly before recording (runs close within the hour).

import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { api, asUser, createSession, ensureBuildingGroup, fail, listUsers, mintCode, ref } from './lib.mjs';

const PREFIX = 'grabdemo.';
const email = handle => `${PREFIX}${handle}@berkeley.edu`;
const PRESENTERS = [
  { handle: 'alex', name: 'Alex Kim', role: 'requester' },
  { handle: 'sam', name: 'Sam Rivera', role: 'runner' },
];
const BACKGROUND = [
  { handle: 'maya', name: 'Maya Chen' },
  { handle: 'jordan', name: 'Jordan Lee' },
  { handle: 'devon', name: 'Devon Park' },
  { handle: 'priya', name: 'Priya Shah' },
];

// Launch places from migration 20261011000004.
const PLACE = {
  target: 'a0000000-0000-0000-0000-000000000001',
  traderJoes: 'a0000000-0000-0000-0000-000000000002',
  cvs: 'a0000000-0000-0000-0000-000000000003',
  moffitt: 'a0000000-0000-0000-0000-000000000004',
  idaSproul: 'a0000000-0000-0000-0000-000000000005',
  blackwell: 'a0000000-0000-0000-0000-000000000006',
  durant: 'a0000000-0000-0000-0000-000000000007',
  unit2: 'a0000000-0000-0000-0000-000000000008',
  satherGate: 'a0000000-0000-0000-0000-00000000000a',
};
const LABEL = {
  target: 'Target · Shattuck Avenue', traderJoes: "Trader Joe's · University Avenue", cvs: 'CVS · Shattuck Avenue',
  moffitt: 'Moffitt Library · Front desk', idaSproul: 'Ida Sproul Hall · Unit 3', blackwell: 'Blackwell Hall',
  durant: 'The Durant · Lobby', unit2: 'Unit 2 · Cunningham Hall', satherGate: 'Sather Gate',
};

const inMinutes = m => new Date(Date.now() + m * 60_000).toISOString();
const ONE = { Accept: 'application/vnd.pgrst.object+json' };

async function demoUsers() {
  return (await listUsers()).filter(u => u.email?.startsWith(PREFIX) && u.email.endsWith('@berkeley.edu'));
}

async function reset({ quiet = false } = {}) {
  const users = await demoUsers();
  if (users.length) {
    const ids = `(${users.map(u => u.id).join(',')})`;
    // Things that would otherwise survive with the author cleared.
    await api('DELETE', `/rest/v1/messages?sender_id=in.${ids}`);
    await api('DELETE', `/rest/v1/list_items?added_by=in.${ids}`);
    await api('DELETE', `/rest/v1/groups?kind=eq.friends&created_by=in.${ids}`);
    await api('DELETE', `/rest/v1/places?created_by=in.${ids}`);
    // Requests, runs, memberships and profiles cascade from the auth user.
    for (const u of users) await api('DELETE', `/auth/v1/admin/users/${u.id}`);
  }
  if (!quiet) console.log(users.length ? `Removed ${users.length} demo accounts and their data.` : 'Nothing to reset.');
}

async function printCodes() {
  console.log('\nSign in on each simulator: Profile → Sign in → email → "I already have a code"\n');
  for (const p of PRESENTERS) {
    const code = await mintCode(email(p.handle), p.name);
    console.log(`  ${p.name.padEnd(11)} (${p.role.padEnd(9)})  ${email(p.handle).padEnd(28)}  code ${code}`);
  }
  console.log('\nCodes are single-use and expire in an hour. Run `node supabase/dev/demo.mjs codes` for new ones.');
}

async function setup() {
  await reset({ quiet: true });
  const { group: durant } = await ensureBuildingGroup();

  const people = {};
  for (const p of [...PRESENTERS, ...BACKGROUND]) people[p.handle] = await createSession(email(p.handle), p.name);
  const { maya, jordan, devon, priya, alex, sam } = Object.fromEntries(Object.entries(people).map(([k, v]) => [k, v.token]));
  const rpc = (token, fn, params, headers) => asUser(token, 'POST', `/rest/v1/rpc/${fn}`, params, headers);
  const insert = async (token, table, row) => (await asUser(token, 'POST', `/rest/v1/${table}`, row, ONE));

  // Building community: everyone but Jordan lives at The Durant.
  for (const token of [maya, devon, priya, alex, sam]) await rpc(token, 'join_building_group', { p_group_id: durant.id }, ONE);
  await asUser(jordan, 'PATCH', `/rest/v1/profiles?id=eq.${people.jordan.id}`, { home_place_id: PLACE.unit2 });

  // Friend group with a free Trader Joe's run in progress.
  const dinner = await rpc(maya, 'create_group', { p_name: 'Sunday Dinner' }, ONE);
  for (const token of [jordan, alex]) await rpc(token, 'join_group', { p_invite_code: dinner.invite_code }, ONE);
  const tjRun = await insert(maya, 'runs', {
    group_id: dinner.id, audience: 'friends', store_place_id: PLACE.traderJoes, store_label: LABEL.traderJoes,
    destination_place_id: PLACE.durant, destination_label: 'Friends: Sunday Dinner',
    note: 'Add something before I check out.', closes_at: inMinutes(40), fee_cents: 0, max_added_minutes: 15,
  });
  await asUser(maya, 'PATCH', `/rest/v1/runs?id=eq.${tjRun.id}`, { status: 'shopping' });
  await insert(maya, 'messages', { group_id: dinner.id, run_id: tjRun.id, body: 'At Trader Joe’s now — add anything you need for Sunday.' });
  await insert(jordan, 'messages', { group_id: dinner.id, body: 'Oat milk please! I’ll pay you back.' });
  await insert(jordan, 'list_items', { group_id: dinner.id, run_id: tjRun.id, body: 'Oat milk' });
  const pasta = await insert(maya, 'list_items', { group_id: dinner.id, run_id: tjRun.id, body: 'Pasta', quantity: 2 });
  await asUser(maya, 'PATCH', `/rest/v1/list_items?id=eq.${pasta.id}`, { status: 'picked' });
  await insert(alex, 'list_items', { group_id: dinner.id, run_id: tjRun.id, body: 'Sparkling water' });

  // Paid building run to Target, with one neighbor already on it.
  const targetRun = await insert(maya, 'runs', {
    group_id: durant.id, audience: 'building', store_place_id: PLACE.target, store_label: LABEL.target,
    destination_place_id: PLACE.durant, destination_label: LABEL.durant,
    note: 'Target run for the building — ask before I check out.', closes_at: inMinutes(60), fee_cents: 500,
    max_added_minutes: 10, capacity: 3,
  });
  await insert(maya, 'messages', { group_id: durant.id, run_id: targetRun.id, body: 'Heading to Target soon. $5 per request, delivered to the lobby.' });
  await insert(devon, 'messages', { group_id: durant.id, body: 'Perfect timing, I’m out of paper towels.' });
  const towels = await rpc(devon, 'request_from_run', { p_run_id: targetRun.id, p_title: 'Paper towels', p_merchandise_budget_cents: 900 }, ONE);
  await rpc(maya, 'accept_request', { p_request_id: towels.id, p_run_id: targetRun.id });

  // Devon is walking to CVS and taking campus requests on the way back.
  await insert(devon, 'runs', {
    audience: 'campus', store_place_id: PLACE.cvs, store_label: LABEL.cvs, destination_place_id: PLACE.durant,
    destination_label: LABEL.durant, note: 'Quick CVS stop, then home.', closes_at: inMinutes(30), fee_cents: 400,
    max_added_minutes: 8,
  });

  // Open requests for the Earn feed.
  await insert(jordan, 'requests', {
    title: 'Grab my charger from the library', details: 'Labeled USB-C charger at the Moffitt front desk. Ask for Jordan.',
    pickup_place_id: PLACE.moffitt, pickup_label: LABEL.moffitt, destination_place_id: PLACE.idaSproul,
    destination_label: LABEL.idaSproul, deliver_by: inMinutes(120), reward_cents: 1000, est_minutes: 15,
  });
  await insert(priya, 'requests', {
    title: 'Return a book to Moffitt', details: 'It’s on the lobby desk with my name on it. Drop it in the return slot.',
    pickup_place_id: PLACE.durant, pickup_label: LABEL.durant, destination_place_id: PLACE.moffitt,
    destination_label: 'Moffitt Library', deliver_by: inMinutes(90), reward_cents: 400, est_minutes: 12,
  });
  await insert(priya, 'requests', {
    group_id: durant.id, title: 'Ice and cups for tonight', details: 'One bag of ice and a pack of red cups.',
    pickup_label: 'Any store', destination_place_id: PLACE.durant, destination_label: LABEL.durant,
    deliver_by: inMinutes(150), reward_cents: 600, merchandise_budget_cents: 1500,
  });

  // History, so Activity and earnings aren't empty: completed yesterday.
  const history = [];
  const shampoo = await insert(alex, 'requests', {
    title: 'Pick up shampoo from Target', details: 'Any unscented everyday shampoo.', pickup_place_id: PLACE.target,
    pickup_label: LABEL.target, destination_place_id: PLACE.durant, destination_label: LABEL.durant,
    deliver_by: inMinutes(120), reward_cents: 600, merchandise_budget_cents: 1400,
  });
  history.push(shampoo.id);
  await rpc(maya, 'accept_request', { p_request_id: shampoo.id });
  for (const status of ['picking_up', 'on_the_way', 'delivered']) await rpc(maya, 'advance_request', { p_request_id: shampoo.id, p_status: status });
  await rpc(alex, 'advance_request', { p_request_id: shampoo.id, p_status: 'completed' });

  const pkg = await insert(jordan, 'requests', {
    title: 'Pick up a package from Sather Gate', details: 'Friend is handing it off at the gate.', pickup_place_id: PLACE.satherGate,
    pickup_label: LABEL.satherGate, destination_place_id: PLACE.unit2, destination_label: LABEL.unit2,
    deliver_by: inMinutes(120), reward_cents: 400,
  });
  history.push(pkg.id);
  await rpc(sam, 'accept_request', { p_request_id: pkg.id });
  for (const status of ['picking_up', 'on_the_way', 'delivered']) await rpc(sam, 'advance_request', { p_request_id: pkg.id, p_status: status });
  await rpc(jordan, 'advance_request', { p_request_id: pkg.id, p_status: 'completed' });

  // Backdate the history to yesterday evening (admin-only columns).
  const yesterday = minutes => new Date(Date.now() - 24 * 3600_000 + minutes * 60_000).toISOString();
  for (const id of history) {
    await api('PATCH', `/rest/v1/requests?id=eq.${id}`, {
      created_at: yesterday(0), accepted_at: yesterday(4), delivered_at: yesterday(22), completed_at: yesterday(25),
      deliver_by: yesterday(120),
    });
    const events = await api('GET', `/rest/v1/request_events?select=id&request_id=eq.${id}&order=id`);
    const offsets = [0, 4, 9, 15, 22, 25];
    for (const [i, e] of events.entries()) {
      await api('PATCH', `/rest/v1/request_events?id=eq.${e.id}`, { created_at: yesterday(offsets[i] ?? 25) });
    }
  }

  console.log(`Demo scene ready on project ${ref}:
  • The Durant (building): Maya's $5 Target run with Devon's paper towels on it
  • Sunday Dinner (friends): Maya shopping at Trader Joe's, chat and a shared list (Alex is a member)
  • Devon's campus CVS run; 3 open requests (charger $10, book return $4, ice & cups $6)
  • History: Alex's shampoo delivered by Maya; Sam earned $4 delivering Jordan's package
  • Alex and Sam already live at The Durant (no need to join during the demo)`);
  await printCodes();
}

const [command] = process.argv.slice(2);
switch (command) {
  case 'setup': await setup(); break;
  case 'codes': await printCodes(); break;
  case 'reset': await reset(); break;
  default:
    console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1, 12).map(l => l.replace(/^\/\/ ?/, '')).join('\n'));
    if (command) fail(`\nUnknown command: ${command}`);
}
