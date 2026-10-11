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

import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { api, ensureBuildingGroup, fail, findUser, listUsers, mintCode } from './lib.mjs';

const [command, ...args] = process.argv.slice(2);

switch (command) {
  case 'code': {
    const email = args[0]?.trim().toLowerCase();
    if (!email?.includes('@')) fail('Usage: accounts.mjs code <email> [Display Name]');
    const existed = Boolean(await findUser(email));
    const name = args.slice(1).join(' ').trim();
    const code = await mintCode(email, name);
    if (!existed) console.log(`Created ${email}${name ? ` (${name})` : ''}`);
    console.log(`\n  ${email}\n  code: ${code}\n\nIn the app: Profile → Sign in → enter the email → "I already have a code". Single-use, expires in an hour.`);
    break;
  }

  case 'building': {
    const { group, created } = await ensureBuildingGroup();
    console.log(created
      ? `Created building group ${group.name}. Campus users can join it from the Groups tab.`
      : `Building group already exists: ${group.name} (invite ${group.invite_code})`);
    break;
  }

  case 'list': {
    const users = await listUsers();
    const profiles = await api('GET', '/rest/v1/profiles?select=id,display_name,campus:campuses(name),home_place:places!home_place_id(name)');
    const byId = Object.fromEntries(profiles.map(p => [p.id, p]));
    if (!users.length) console.log('No users yet.');
    for (const u of users) {
      const p = byId[u.id];
      console.log(`${u.email.padEnd(34)} ${(p?.display_name ?? '').padEnd(20)} ${p?.campus?.name ?? 'no campus'}${p?.home_place ? ` · ${p.home_place.name}` : ''}`);
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
    console.log(fs.readFileSync(fileURLToPath(import.meta.url), 'utf8').split('\n').slice(1, 15).map(l => l.replace(/^\/\/ ?/, '')).join('\n'));
}
