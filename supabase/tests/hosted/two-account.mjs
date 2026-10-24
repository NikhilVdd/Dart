#!/usr/bin/env node

// Hosted, destructive-to-fixtures-only smoke test. It creates three disposable users through the
// public Auth API, exercises the same REST/RPC paths as the app, and deletes the accounts in finally.
// Run only against development or staging. Never provide a production URL.

import { randomUUID } from 'node:crypto';

const baseURL = process.env.SUPABASE_URL?.replace(/\/$/, '');
const publicKey = process.env.SUPABASE_ANON_KEY;
const environment = process.env.DART_ENVIRONMENT?.toLowerCase();

if (!baseURL || !publicKey) throw new Error('Set SUPABASE_URL and SUPABASE_ANON_KEY.');
if (!['development', 'staging'].includes(environment)) {
  throw new Error('Set DART_ENVIRONMENT=development or staging. This test refuses production.');
}

const stamp = `${Date.now()}-${randomUUID().slice(0, 8)}`;
const users = [];
let passed = 0;

function pass(label, detail = '') {
  passed += 1;
  console.log(`PASS  ${label}${detail ? ` — ${detail}` : ''}`);
}

function assert(condition, label, detail = '') {
  if (!condition) throw new Error(`FAIL  ${label}${detail ? ` — ${detail}` : ''}`);
  pass(label, detail);
}

function first(value) {
  return Array.isArray(value) ? value[0] : value;
}

async function call(user, method, path, body, extraHeaders = {}) {
  const response = await fetch(`${baseURL}${path}`, {
    method,
    headers: {
      apikey: publicKey,
      Authorization: `Bearer ${user?.token ?? publicKey}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
      ...extraHeaders,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  if (!response.ok) {
    const message = data?.message ?? data?.msg ?? data?.error_description ?? data?.hint ?? text;
    throw new Error(`${method} ${path} → ${response.status} ${message}`);
  }
  return data;
}

async function expectDenied(label, operation) {
  try {
    await operation();
  } catch (error) {
    pass(label, error.message.replace(/\s+/g, ' ').slice(0, 150));
    return;
  }
  throw new Error(`FAIL  ${label} — operation unexpectedly succeeded`);
}

async function signUp(role, displayName) {
  const email = `dart-e2e-${role}-${stamp}@example.com`;
  const password = `Dart-${randomUUID()}-Aa1!`;
  const response = await call(null, 'POST', '/auth/v1/signup', {
    email,
    password,
    data: { display_name: displayName },
  });
  if (!response?.access_token || !response?.user?.id) {
    throw new Error('Hosted Auth requires email confirmation. Disable confirmation on development/staging or provision confirmed disposable accounts with supabase/dev/accounts.mjs.');
  }
  const user = { role, email, password, id: response.user.id, token: response.access_token };
  users.push(user);
  pass(`${role} signs up with email/password`);
  return user;
}

async function signIn(user) {
  const response = await call(null, 'POST', '/auth/v1/token?grant_type=password', {
    email: user.email,
    password: user.password,
  });
  assert(response?.user?.id === user.id && response?.access_token, `${user.role} signs back in`);
  user.token = response.access_token;
}

async function onboard(user, homePlaceID) {
  await call(user, 'POST', '/rest/v1/rpc/set_my_age_band', { p_age_band: '18_or_over' });
  await call(user, 'POST', '/rest/v1/rpc/accept_safety_rules', {});
  await call(user, 'POST', '/rest/v1/rpc/set_home_place', { p_place_id: homePlaceID });
  const profile = first(await call(user, 'GET', `/rest/v1/profiles?id=eq.${user.id}&select=id,display_name,age_band,safety_rules_accepted_at,home_place_id`));
  assert(profile?.age_band === '18_or_over' && profile?.safety_rules_accepted_at && profile?.home_place_id === homePlaceID,
    `${user.role} completes onboarding`);
}

async function removeUser(user) {
  if (!user?.token) return;
  try {
    await call(user, 'POST', '/rest/v1/rpc/delete_my_account', {});
    console.log(`CLEAN ${user.role} account deleted`);
  } catch (error) {
    console.error(`CLEANUP FAILED for ${user.role}: ${error.message}`);
  }
}

let requester;
let helper;
let outsider;

try {
  requester = await signUp('requester', 'Dart E2E Requester');
  helper = await signUp('helper', 'Dart E2E Helper');
  outsider = await signUp('outsider', 'Dart E2E Outsider');

  await signIn(requester);
  await signIn(helper);

  const places = await call(requester, 'GET', '/rest/v1/places?select=id,name,kind&order=name');
  const target = places.find((place) => place.name === 'Target');
  const unit2 = places.find((place) => place.name === 'Unit 2');
  assert(target && unit2, 'Berkeley launch places are available');

  await onboard(requester, unit2.id);
  await onboard(helper, unit2.id);
  await onboard(outsider, unit2.id);

  const group = first(await call(requester, 'POST', '/rest/v1/rpc/create_group', { p_name: `E2E Crew ${stamp.slice(-8)}` }));
  assert(group?.id && group?.invite_code, 'requester creates a friend group');
  const joined = first(await call(helper, 'POST', '/rest/v1/rpc/join_group', { p_invite_code: group.invite_code }));
  assert(joined?.id === group.id, 'helper joins by invite code');

  await call(requester, 'POST', '/rest/v1/messages', { group_id: group.id, body: 'Requester is ready.' });
  const helperMessages = await call(helper, 'GET', `/rest/v1/messages?group_id=eq.${group.id}&select=body,sender_id`);
  assert(helperMessages.some((message) => message.body === 'Requester is ready.'), 'helper reads requester group chat');
  await call(helper, 'POST', '/rest/v1/messages', { group_id: group.id, body: 'Helper is ready.' });

  const listItem = first(await call(requester, 'POST', '/rest/v1/list_items?select=id,status', {
    group_id: group.id,
    body: 'E2E lemons',
  }));
  await call(helper, 'PATCH', `/rest/v1/list_items?id=eq.${listItem.id}`, { status: 'picked' });
  const picked = first(await call(requester, 'GET', `/rest/v1/list_items?id=eq.${listItem.id}&select=status`));
  assert(picked?.status === 'picked', 'shared list update is visible to requester');

  const request = first(await call(requester, 'POST', '/rest/v1/requests?select=id,status,requester_id', {
    title: `E2E groceries ${stamp.slice(-8)}`,
    pickup_place_id: target.id,
    pickup_label: 'Target',
    destination_place_id: unit2.id,
    destination_label: 'Unit 2',
    deliver_by: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    audience: 'campus',
    reward_cents: 800,
    merchandise_budget_cents: 5000,
  }));
  assert(request?.status === 'open' && request?.requester_id === requester.id, 'requester posts a campus request');

  const helperFeed = await call(helper, 'POST', '/rest/v1/rpc/open_requests_nearby', { p_lat: null, p_lng: null });
  assert(helperFeed.some((item) => item.id === request.id), 'helper discovers the open request');

  const run = first(await call(helper, 'POST', '/rest/v1/runs?select=id,runner_id,status', {
    audience: 'campus',
    store_place_id: target.id,
    store_label: 'Target',
    destination_place_id: unit2.id,
    destination_label: 'Unit 2',
    closes_at: new Date(Date.now() + 45 * 60 * 1000).toISOString(),
    fee_cents: 600,
    max_added_minutes: 20,
  }));
  assert(run?.runner_id === helper.id, 'helper announces a campus store run');

  await call(helper, 'POST', '/rest/v1/rpc/accept_request', { p_request_id: request.id, p_run_id: run.id });
  const accepted = first(await call(requester, 'GET', `/rest/v1/requests?id=eq.${request.id}&select=status,helper_id,run_id`));
  assert(accepted?.status === 'accepted' && accepted?.helper_id === helper.id && accepted?.run_id === run.id,
    'requester sees helper acceptance');

  const outsiderView = await call(outsider, 'GET', `/rest/v1/requests?id=eq.${request.id}&select=id`);
  assert(outsiderView.length === 0, 'outsider cannot read an accepted private delivery');
  await expectDenied('requester cannot directly rewrite protected status', () =>
    call(requester, 'PATCH', `/rest/v1/requests?id=eq.${request.id}`, { status: 'completed' }));

  await call(requester, 'POST', '/rest/v1/request_messages', { request_id: request.id, body: 'Please meet at the lobby.' });
  await call(helper, 'POST', '/rest/v1/request_messages', { request_id: request.id, body: 'On my way.' });
  const requesterChat = await call(requester, 'GET', `/rest/v1/request_messages?request_id=eq.${request.id}&select=body,sender_id&order=created_at`);
  const helperChat = await call(helper, 'GET', `/rest/v1/request_messages?request_id=eq.${request.id}&select=body,sender_id&order=created_at`);
  const outsiderChat = await call(outsider, 'GET', `/rest/v1/request_messages?request_id=eq.${request.id}&select=id`);
  assert(requesterChat.length === 2 && helperChat.length === 2 && outsiderChat.length === 0,
    'private request chat is shared only by both participants');

  for (const status of ['picking_up', 'on_the_way', 'delivered']) {
    await call(helper, 'POST', '/rest/v1/rpc/advance_request', { p_request_id: request.id, p_status: status });
    const current = first(await call(requester, 'GET', `/rest/v1/requests?id=eq.${request.id}&select=status`));
    assert(current?.status === status, `requester sees ${status.replaceAll('_', ' ')}`);
  }

  await expectDenied('helper cannot mark the request completed', () =>
    call(helper, 'POST', '/rest/v1/rpc/advance_request', { p_request_id: request.id, p_status: 'completed' }));
  await call(requester, 'POST', '/rest/v1/rpc/advance_request', { p_request_id: request.id, p_status: 'completed' });

  const timeline = await call(requester, 'GET', `/rest/v1/request_events?request_id=eq.${request.id}&select=status&order=id`);
  const statuses = timeline.map((event) => event.status);
  assert(JSON.stringify(statuses) === JSON.stringify(['open', 'accepted', 'picking_up', 'on_the_way', 'delivered', 'completed']),
    'server records the complete lifecycle', statuses.join(' → '));

  const earnings = first(await call(helper, 'POST', '/rest/v1/rpc/my_earnings', {}));
  assert(earnings?.earned_cents >= 800 && earnings?.completed_count >= 1, 'helper earnings update after confirmation');
  await expectDenied('completed request chat is closed', () =>
    call(requester, 'POST', '/rest/v1/request_messages', { request_id: request.id, body: 'Late message' }));

  console.log(`\nHOSTED TWO-ACCOUNT E2E PASSED (${passed} assertions)`);
} finally {
  await removeUser(outsider);
  await removeUser(helper);
  await removeUser(requester);
}
