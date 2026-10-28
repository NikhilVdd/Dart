#!/usr/bin/env node

// Hosted smoke test for requester / darter account roles. Creates disposable users through the
// public Auth API, checks the server enforces each role, and deletes the accounts in finally.
// It never posts a request, so it works whether or not payment_settings.required is on.
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

async function call(user, method, path, body) {
  const response = await fetch(`${baseURL}${path}`, {
    method,
    headers: {
      apikey: publicKey,
      Authorization: `Bearer ${user?.token ?? publicKey}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
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

async function expectDenied(label, pattern, operation) {
  try {
    await operation();
  } catch (error) {
    assert(pattern.test(error.message), label, error.message.replace(/\s+/g, ' ').slice(0, 150));
    return;
  }
  throw new Error(`FAIL  ${label} — operation unexpectedly succeeded`);
}

async function signUp(role, displayName) {
  const email = `dart-e2e-${role ?? 'legacy'}-${stamp}@example.com`;
  const password = `Dart-${randomUUID()}-Aa1!`;
  const data = role ? { display_name: displayName, role } : { display_name: displayName };
  const response = await call(null, 'POST', '/auth/v1/signup', { email, password, data });
  if (!response?.access_token || !response?.user?.id) {
    throw new Error('Hosted Auth requires email confirmation. Disable confirmation on development/staging.');
  }
  const user = { role, id: response.user.id, token: response.access_token };
  users.push(user);
  return user;
}

const roles = async (user) =>
  (await call(user, 'GET', `/rest/v1/profiles?id=eq.${user.id}&select=is_requester,is_darter`))[0];

const run = (user) => call(user, 'POST', '/rest/v1/runs?select=id', {
  audience: 'campus',
  store_label: 'Gateway Cafe',
  destination_label: 'Unit 2',
  closes_at: new Date(Date.now() + 30 * 60 * 1000).toISOString(),
  fee_cents: 0,
});

try {
  const requester = await signUp('requester', 'Dart E2E Requester');
  const darter = await signUp('darter', 'Dart E2E Darter');
  const legacy = await signUp(null, 'Dart E2E Legacy');

  const r = await roles(requester);
  const d = await roles(darter);
  const l = await roles(legacy);
  assert(r.is_requester && !r.is_darter, 'requester signup is requester-only');
  assert(!d.is_requester && d.is_darter, 'darter signup is darter-only');
  assert(l.is_requester && l.is_darter, 'signup without a role (older clients) gets both');

  await expectDenied('users cannot grant themselves a role', /permission denied/i, () =>
    call(requester, 'PATCH', `/rest/v1/profiles?id=eq.${requester.id}`, { is_darter: true }));

  await expectDenied('darter-only accounts cannot post requests', /requester accounts/, () =>
    call(darter, 'POST', '/rest/v1/requests', {
      title: 'Grubhub order from Gateway Cafe',
      pickup_label: 'Gateway Cafe',
      destination_label: 'Unit 2',
      deliver_by: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    }));
  await expectDenied('requester-only accounts cannot share trips', /darter accounts/, () => run(requester));

  const trip = (await run(darter))[0];
  assert(trip?.id, 'darters can share trips');
  await call(darter, 'PATCH', `/rest/v1/runs?id=eq.${trip.id}`, { status: 'cancelled' });

  await expectDenied('add_my_role rejects unknown roles', /Unknown role/, () =>
    call(requester, 'POST', '/rest/v1/rpc/add_my_role', { p_role: 'admin' }));
  await call(requester, 'POST', '/rest/v1/rpc/add_my_role', { p_role: 'darter' });
  const both = await roles(requester);
  assert(both.is_requester && both.is_darter, 'add_my_role adds delivering to a requester');
  const second = (await run(requester))[0];
  assert(second?.id, 'after adding the role, the requester can share a trip');
  await call(requester, 'PATCH', `/rest/v1/runs?id=eq.${second.id}`, { status: 'cancelled' });

  await expectDenied('signed-out callers cannot add roles', /permission denied/i, () =>
    call(null, 'POST', '/rest/v1/rpc/add_my_role', { p_role: 'darter' }));

  console.log(`\nHOSTED ACCOUNT ROLES PASSED (${passed} assertions)`);
} finally {
  for (const user of users.reverse()) {
    try {
      await call(user, 'POST', '/rest/v1/rpc/delete_my_account', {});
      console.log(`CLEAN ${user.role ?? 'legacy'} account deleted`);
    } catch (error) {
      console.error(`CLEANUP FAILED for ${user.role ?? 'legacy'}: ${error.message}`);
    }
  }
}
