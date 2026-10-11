#!/usr/bin/env node
// Test-account helper for manual testing against the linked Supabase project.
//
// Mints email sign-in codes with the Auth admin API, which returns the code instead of emailing
// it, so you can sign in as any number of test users even while Resend only delivers to you.
//
//   node supabase/dev/accounts.mjs code <email> [Display Name]   create the user if needed, print a code
//   node supabase/dev/accounts.mjs building                      create "The Durant" building group if missing
//   node supabase/dev/accounts.mjs list                          list users
//   node supabase/dev/accounts.mjs delete <email>                delete a user and their data
//
// Requirements: Node 18+, `npx supabase login`, and `npx supabase link` run in this repo.
// The service_role key is read from the Supabase CLI at runtime and never written to disk.
// This is an admin tool: anyone with it can sign in as any user. Use it on dev/staging projects.

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const refFile = path.join(repo, 'supabase/.temp/project-ref');
if (!fs.existsSync(refFile)) fail('No linked project. Run `npx supabase link --project-ref <ref>` first.');
const ref = fs.readFileSync(refFile, 'utf8').trim();
const URL_ = `https://${ref}.supabase.co`;

const serviceKey = (() => {
  const raw = execFileSync('npx', ['supabase', 'projects', 'api-keys', '--project-ref', ref, '-o', 'json'],
    { cwd: repo, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
  const start = Math.min(...[raw.indexOf('['), raw.indexOf('{')].filter(i => i >= 0));
  const parsed = JSON.parse(raw.slice(start));
  const keys = Array.isArray(parsed) ? parsed : parsed.keys;
  // New-style secret keys come back masked from the CLI, so use the legacy service_role JWT.
  const key = keys.find(k => k.name === 'service_role')?.api_key;
  if (!key) fail('Could not read the service_role key from the Supabase CLI.');
  return key;
})();

async function api(method, route, body) {
  const res = await fetch(URL_ + route, {
    method,
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json',
               Prefer: 'return=representation' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) throw new Error(`${method} ${route} → ${res.status} ${data?.msg ?? data?.message ?? text}`);
  return data;
}

async function findUser(email) {
  for (let page = 1; ; page++) {
    const { users } = await api('GET', `/auth/v1/admin/users?page=${page}&per_page=200`);
    const hit = users.find(u => u.email?.toLowerCase() === email.toLowerCase());
    if (hit || users.length < 200) return hit;
  }
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

const [command, ...args] = process.argv.slice(2);

switch (command) {
  case 'code': {
    const email = args[0]?.trim().toLowerCase();
    if (!email?.includes('@')) fail('Usage: accounts.mjs code <email> [Display Name]');
    const name = args.slice(1).join(' ').trim();
    if (!(await findUser(email))) {
      await api('POST', '/auth/v1/admin/users', {
        email, email_confirm: true, user_metadata: name ? { display_name: name } : {},
      });
      console.log(`Created ${email}${name ? ` (${name})` : ''}`);
    }
    const link = await api('POST', '/auth/v1/admin/generate_link', { type: 'magiclink', email });
    const code = link.properties?.email_otp ?? link.email_otp;
    if (!code) fail('Supabase did not return a code.');
    console.log(`\n  ${email}\n  code: ${code}\n\nEnter it in the app (Profile → Sign in). It's single-use and expires in an hour.`);
    break;
  }

  case 'building': {
    const [place] = await api('GET', `/rest/v1/places?select=id,campus_id&name=eq.${encodeURIComponent('The Durant')}`);
    if (!place) fail('Place "The Durant" not found. Has migration 20261011000004 been pushed?');
    const existing = await api('GET', `/rest/v1/groups?select=id,name,invite_code&kind=eq.building&place_id=eq.${place.id}`);
    if (existing.length) {
      console.log(`Building group already exists: ${existing[0].name} (invite ${existing[0].invite_code})`);
      break;
    }
    const [group] = await api('POST', '/rest/v1/groups', {
      name: 'The Durant', kind: 'building', campus_id: place.campus_id, place_id: place.id,
    });
    console.log(`Created building group ${group.name}. Campus users can join it from the Groups tab.`);
    break;
  }

  case 'list': {
    const { users } = await api('GET', '/auth/v1/admin/users?page=1&per_page=200');
    const profiles = await api('GET', '/rest/v1/profiles?select=id,display_name,campus:campuses(name),home_place:places!home_place_id(name)');
    const byId = Object.fromEntries(profiles.map(p => [p.id, p]));
    if (!users.length) console.log('No users yet.');
    for (const u of users) {
      const p = byId[u.id];
      console.log(`${u.email.padEnd(32)} ${(p?.display_name ?? '').padEnd(20)} ${p?.campus?.name ?? 'no campus'}${p?.home_place ? ` · ${p.home_place.name}` : ''}`);
    }
    break;
  }

  case 'delete': {
    const email = args[0]?.trim();
    if (!email) fail('Usage: accounts.mjs delete <email>');
    const user = await findUser(email);
    if (!user) fail(`No user ${email}.`);
    await api('DELETE', `/auth/v1/admin/users/${user.id}`);
    console.log(`Deleted ${email} (their profile, requests, runs and memberships go with it).`);
    break;
  }

  default:
    console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1, 16).map(l => l.replace(/^\/\/ ?/, '')).join('\n'));
}
