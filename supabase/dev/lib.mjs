// Shared helpers for the dev scripts. Talks to the project linked with `npx supabase link`,
// using the service_role key read from the Supabase CLI at runtime (never written to disk).

import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

export function fail(message) {
  console.error(message);
  process.exit(1);
}

const refFile = path.join(repo, 'supabase/.temp/project-ref');
if (!fs.existsSync(refFile)) fail('No linked project. Run `npx supabase login` and `npx supabase link --project-ref <ref>` first.');
export const ref = fs.readFileSync(refFile, 'utf8').trim();
export const baseURL = `https://${ref}.supabase.co`;

function readKeys() {
  const raw = execFileSync('npx', ['supabase', 'projects', 'api-keys', '--project-ref', ref, '-o', 'json'],
    { cwd: repo, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  const start = Math.min(...[raw.indexOf('['), raw.indexOf('{')].filter(i => i >= 0));
  const parsed = JSON.parse(raw.slice(start));
  return Array.isArray(parsed) ? parsed : parsed.keys;
}

const keys = readKeys();
// New-style secret keys come back masked from the CLI, so admin calls use the legacy service_role JWT.
const serviceKey = keys.find(k => k.name === 'service_role')?.api_key;
const publicKey = keys.find(k => k.type === 'publishable')?.api_key ?? keys.find(k => k.name === 'anon')?.api_key;
if (!serviceKey || !publicKey) fail('Could not read API keys from the Supabase CLI.');

async function request(method, route, body, { token, admin = false, headers = {} } = {}) {
  const key = admin ? serviceKey : publicKey;
  const res = await fetch(baseURL + route, {
    method,
    headers: {
      apikey: key,
      Authorization: `Bearer ${admin ? serviceKey : token ?? publicKey}`,
      'Content-Type': 'application/json',
      Prefer: 'return=representation',
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) throw new Error(`${method} ${route} → ${res.status} ${data?.msg ?? data?.message ?? text}`);
  return data;
}

/** Admin call (service_role): bypasses row level security. */
export const api = (method, route, body, headers) => request(method, route, body, { admin: true, headers });

/** Call as a signed-in user: goes through row level security like the app does. */
export const asUser = (token, method, route, body, headers) => request(method, route, body, { token, headers });

export async function listUsers() {
  const all = [];
  for (let page = 1; ; page++) {
    const { users } = await api('GET', `/auth/v1/admin/users?page=${page}&per_page=200`);
    all.push(...users);
    if (users.length < 200) return all;
  }
}

export async function findUser(email) {
  return (await listUsers()).find(u => u.email?.toLowerCase() === email.toLowerCase());
}

/** Creates the user if needed and returns a single-use 6-digit sign-in code (no email is sent). */
export async function mintCode(email, displayName) {
  if (!(await findUser(email))) {
    await api('POST', '/auth/v1/admin/users', {
      email, email_confirm: true, user_metadata: displayName ? { display_name: displayName } : {},
    });
  }
  const link = await api('POST', '/auth/v1/admin/generate_link', { type: 'magiclink', email });
  const code = link.properties?.email_otp ?? link.email_otp;
  if (!code) fail('Supabase did not return a code.');
  return code;
}

/** Creates (or recreates) a user with a throwaway password and returns { id, token }. */
export async function createSession(email, displayName) {
  const existing = await findUser(email);
  if (existing) await api('DELETE', `/auth/v1/admin/users/${existing.id}`);
  const password = randomUUID();
  const user = await api('POST', '/auth/v1/admin/users', {
    email, password, email_confirm: true, user_metadata: { display_name: displayName },
  });
  const session = await request('POST', '/auth/v1/token?grant_type=password', { email, password });
  return { id: user.id, token: session.access_token };
}

/** Ensures the launch building group for The Durant exists and returns it. */
export async function ensureBuildingGroup() {
  const [place] = await api('GET', `/rest/v1/places?select=id,campus_id&name=eq.${encodeURIComponent('The Durant')}`);
  if (!place) fail('Place "The Durant" not found. Has migration 20261011000004 been pushed?');
  const existing = await api('GET', `/rest/v1/groups?select=id,name,invite_code&kind=eq.building&place_id=eq.${place.id}`);
  if (existing.length) return { group: existing[0], created: false };
  const [group] = await api('POST', '/rest/v1/groups', {
    name: 'The Durant', kind: 'building', campus_id: place.campus_id, place_id: place.id,
  });
  return { group, created: true };
}
