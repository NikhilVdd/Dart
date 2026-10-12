import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Applies supabase/migrations + seed.sql to an in-memory Postgres 17 (PGlite) with a minimal
// Supabase auth stub, then exercises RLS, the lifecycle RPCs and matching as each demo user.
// Usage: cd supabase/tests/pglite && npm install && npm test
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const db = new PGlite({ extensions: { pgcrypto } });
await db.exec(fs.readFileSync(new URL('./supabase_stub.sql', import.meta.url), 'utf8'));
const migDir = path.join(root, 'supabase/migrations');
for (const f of fs.readdirSync(migDir).sort()) {
  await db.exec(fs.readFileSync(path.join(migDir, f), 'utf8'));
  console.log('applied', f);
}
await db.exec(fs.readFileSync(path.join(root, 'supabase/seed.sql'), 'utf8'));
console.log('applied seed.sql');

const U = { maya: '00000000-0000-0000-0000-000000000001', jordan: '00000000-0000-0000-0000-000000000002',
            devon: '00000000-0000-0000-0000-000000000003', nikhil: '00000000-0000-0000-0000-000000000004' };
let failures = 0;
async function as(user, sql, params = []) {
  await db.exec('reset role');
  if (user === 'anon') { await db.exec(`select set_config('request.jwt.claim.sub', '', false); set role anon`); }
  else if (user) { await db.exec(`select set_config('request.jwt.claim.sub', '${U[user]}', false); set role authenticated`); }
  else { await db.exec(`select set_config('request.jwt.claim.sub', '', false)`); }
  try { return (await db.query(sql, params)).rows; } finally { await db.exec('reset role'); }
}
function check(name, cond, extra = '') { console.log(`${cond ? 'PASS' : 'FAIL'}  ${name} ${extra}`); if (!cond) failures++; }
async function rejects(name, user, sql, params) {
  try { await as(user, sql, params); check(name, false, '(expected error)'); }
  catch (e) { check(name, true, `→ ${e.message}`); }
}

const profiles = await as(null, `select display_name, initials, campus_id is not null as has_campus from profiles order by display_name`);
check('profiles created by auth trigger with campus + initials', profiles.length === 4 && profiles.every(p => p.has_campus) && profiles.find(p => p.display_name === 'Nikhil Varma').initials === 'NV', JSON.stringify(profiles.map(p => p.initials)));
check('initials_for edge cases', JSON.stringify((await as(null, `select initials_for('Cher') a, initials_for('  ana  de la cruz ') b, initials_for('') c`))[0]) === '{"a":"C","b":"AC","c":"?"}');

check('nikhil sees 3 groups', (await as('nikhil', 'select id from groups')).length === 3);
const jg = (await as('jordan', 'select name from groups order by name')).map(r => r.name);
check('jordan sees own friend group + campus building, not Design Studio', JSON.stringify(jg) === '["Sunday Dinner","The Durant"]', JSON.stringify(jg));
check('jordan reads only Sunday Dinner chat', (await as('jordan', 'select distinct group_id from messages')).length === 1);
await rejects('jordan cannot post to Design Studio', 'jordan', `insert into messages (group_id, body) values ('20000000-0000-0000-0000-000000000002', 'hi')`);
const msg = await as('jordan', `insert into messages (group_id, body) values ('20000000-0000-0000-0000-000000000001', 'add oat milk?') returning sender_id`);
check('jordan posts to Sunday Dinner as himself (sender defaulted)', msg[0].sender_id === U.jordan);
await rejects('cannot spoof sender', 'jordan', `insert into messages (group_id, body, sender_id) values ('20000000-0000-0000-0000-000000000001', 'x', '${U.maya}')`);

const nreq = (await as('nikhil', 'select title from requests order by title')).map(r => r.title);
check('nikhil request visibility', nreq.length === 5, JSON.stringify(nreq));
const jreq = (await as('jordan', 'select title from requests order by title')).map(r => r.title);
check('jordan cannot see others’ accepted requests', JSON.stringify(jreq) === '["Blender under $50","Grab my charger from the library"]', JSON.stringify(jreq));
check('anon sees no requests', (await as('anon', 'select * from campuses')).length === 1 && await as('anon', 'select * from requests').then(() => false, () => true));

const feed = (await as('nikhil', `select title from open_requests_nearby(37.8679, -122.2589, 5000)`)).map(r => r.title);
check('earn feed for nikhil, nearest first (any-store blender ranks by drop-off)', JSON.stringify(feed) === '["Blender under $50","Grab my charger from the library"]', JSON.stringify(feed));

const runMatches = await as('devon', `select q.title, m.detour_minutes from match_requests_for_run('30000000-0000-0000-0000-000000000003') m join requests q on q.id = m.request_id`);
check('devon’s Target→Unit 2 trip picks up the blender, not the charger', runMatches.length === 1 && runMatches[0].title === 'Blender under $50', JSON.stringify(runMatches));
const chargerDetour = await as(null, `select detour_minutes(s.lat,s.lng,d.lat,d.lng,p.lat,p.lng,q.lat,q.lng) m from places s, places d, places p, places q
  where s.name='Target' and d.name='Unit 2' and p.name='Moffitt Library' and q.name='Ida Sproul Hall'`);
console.log('      (charger detour on that trip would be', chargerDetour[0].m, 'min vs 8 allowed)');

const reqMatches = await as('jordan', `select * from match_runs_for_request('10000000-0000-0000-0000-000000000003')`);
check('blender request finds devon’s campus run', reqMatches.length === 1 && reqMatches[0].run_id === '30000000-0000-0000-0000-000000000003', JSON.stringify(reqMatches));
const mayaMatches = await as('maya', `select q.title, m.detour_minutes from match_requests_for_run('30000000-0000-0000-0000-000000000002') m join requests q on q.id = m.request_id`);
console.log('      maya building-run matches:', JSON.stringify(mayaMatches));

await rejects('jordan cannot accept own request', 'jordan', `select accept_request('10000000-0000-0000-0000-000000000003')`);
await rejects('nikhil cannot attach to devon’s run', 'nikhil', `select accept_request('10000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000003')`);
const acc = await as('devon', `select status, helper_id, run_id from accept_request('10000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000003')`);
check('devon accepts blender onto his run', acc[0].status === 'accepted' && acc[0].helper_id === U.devon);
await rejects('second accept fails', 'nikhil', `select accept_request('10000000-0000-0000-0000-000000000003')`);
await rejects('requester cannot write status directly', 'jordan', `update requests set status='completed' where id='10000000-0000-0000-0000-000000000003'`);
await rejects('requester cannot advance to picking_up', 'jordan', `select advance_request('10000000-0000-0000-0000-000000000003', 'picking_up')`);
await as('devon', `select advance_request('10000000-0000-0000-0000-000000000003', 'picking_up')`);
await rejects('no moving backwards', 'devon', `select advance_request('10000000-0000-0000-0000-000000000003', 'accepted')`);
await as('devon', `select advance_request('10000000-0000-0000-0000-000000000003', 'on_the_way')`);
await rejects('helper cannot mark completed (requester confirms)', 'devon', `select advance_request('10000000-0000-0000-0000-000000000003', 'completed')`);
const done = await as('jordan', `select status from advance_request('10000000-0000-0000-0000-000000000003', 'completed')`);
check('requester confirms receipt', done[0].status === 'completed');
const ev = (await as('jordan', `select status from request_events where request_id='10000000-0000-0000-0000-000000000003' order by id`)).map(r => r.status);
check('timeline has every step', JSON.stringify(ev) === '["open","accepted","picking_up","on_the_way","completed"]', JSON.stringify(ev));
const earn = await as('devon', 'select * from my_earnings()');
check('devon earnings', earn[0].completed_count === 1 && Number(earn[0].earned_cents) === 800, JSON.stringify(earn));

const canc = await as('nikhil', `select status from cancel_request('10000000-0000-0000-0000-000000000002')`);
check('nikhil cancels accepted shampoo', canc[0].status === 'cancelled');
await as('nikhil', `select accept_request('10000000-0000-0000-0000-000000000001')`);
const rel = await as('nikhil', `select status, helper_id from release_request('10000000-0000-0000-0000-000000000001')`);
check('helper can release back to open', rel[0].status === 'open' && rel[0].helper_id === null);

await rejects('cannot post request as someone else', 'jordan', `insert into requests (requester_id, title, pickup_label, destination_label, deliver_by) values ('${U.nikhil}', 'x', 'a', 'b', now() + interval '1 hour')`);
const newReq = await as('jordan', `insert into requests (title, pickup_label, destination_label, deliver_by, reward_cents) values ('Ice', 'Any store', 'Unit 2', now() + interval '1 hour', 300) returning requester_id, campus_id, status`);
check('request insert defaults requester + campus', newReq[0].requester_id === U.jordan && newReq[0].campus_id && newReq[0].status === 'open');

const fromRun = await as('nikhil', `select title, group_id, reward_cents, pickup_label from request_from_run('30000000-0000-0000-0000-000000000002', 'Dish soap', '', 600)`);
check('request_from_run inherits building group + fee', fromRun[0].group_id === '20000000-0000-0000-0000-000000000003' && fromRun[0].reward_cents === 500, JSON.stringify(fromRun));
check('jordan (not in Durant) cannot see building request', (await as('jordan', `select 1 from requests where title='Dish soap'`)).length === 0);

const g = await as('jordan', `select id, invite_code from create_group('Climbing crew')`);
await as('devon', `select join_group($1)`, [g[0].invite_code.toLowerCase()]);
const roster = await as('devon', `select user_id, role from group_members where group_id = $1 order by role`, [g[0].id]);
check('create + join group by invite', roster.length === 2 && roster[0].role === 'owner', JSON.stringify(roster));
const jb = await as('jordan', `select name from join_building_group('20000000-0000-0000-0000-000000000003')`);
check('join building group on campus', jb[0].name === 'The Durant');

const li = await as('nikhil', `insert into list_items (group_id, run_id, body) values ('20000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', 'Lemons') returning id, added_by`);
check('list item added_by defaulted', li[0].added_by === U.nikhil);
const upd = await as('maya', `update list_items set status='picked' where id=$1 returning updated_by`, [li[0].id]);
check('check-off stamps editor', upd[0].updated_by === U.maya);
await rejects('list item cannot reference another group’s run', 'nikhil', `insert into list_items (group_id, run_id, body) values ('20000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001', 'x')`);
await rejects('friend runs must be free', 'maya', `insert into runs (group_id, audience, store_label, destination_label, closes_at, fee_cents) values ('20000000-0000-0000-0000-000000000001', 'friends', 'a', 'b', now() + interval '1 hour', 300)`);

const pr = await as('nikhil', `update profiles set display_name='Nikhil V' where id=$1 returning initials`, [U.nikhil]);
check('profile rename updates initials', pr[0].initials === 'NV');
await rejects('cannot change own campus', 'nikhil', `update profiles set campus_id=null where id='${U.nikhil}'`);
check('cannot edit others’ profiles', (await as('nikhil', `update profiles set display_name='x' where id='${U.maya}' returning id`)).length === 0);

const nr = await as('jordan', `insert into runs (audience, store_place_id, store_label, destination_place_id, destination_label, closes_at, fee_cents)
  values ('campus', 'a0000000-0000-0000-0000-000000000003', 'CVS', 'a0000000-0000-0000-0000-000000000008', 'Unit 2', now() + interval '30 minutes', 400) returning runner_id, campus_id`);
check('campus run insert returns row with runner + campus defaulted', nr[0].runner_id === U.jordan && !!nr[0].campus_id);
check('campus run visible to others on campus', (await as('maya', `select 1 from runs where store_label='CVS'`)).length === 1);
await rejects('anon cannot call lifecycle RPCs', 'anon', `select accept_request('10000000-0000-0000-0000-000000000001')`);
await rejects('anon cannot call matching RPCs', 'anon', `select * from open_requests_nearby()`);

// --- delivered -> confirmation, expiry, housekeeping ---------------------------------------
const q2 = await as('jordan', `insert into requests (title, pickup_label, destination_label, deliver_by, reward_cents) values ('Snacks', 'Any store', 'Unit 2', now() + interval '1 hour', 500) returning id`);
await as('maya', `select accept_request($1)`, [q2[0].id]);
await as('maya', `select advance_request($1, 'delivered')`, [q2[0].id]);
const dl = await as('jordan', `select status, delivered_at is not null as stamped from requests where id = $1`, [q2[0].id]);
check('helper can mark delivered (skipping steps forward)', dl[0].status === 'delivered' && dl[0].stamped);
check('delivered counts as active in earnings', (await as('maya', 'select active_count from my_earnings()'))[0].active_count >= 1);
const conf = await as('jordan', `select status from advance_request($1, 'completed')`, [q2[0].id]);
check('requester confirms a delivered request', conf[0].status === 'completed');

const q3 = await as('jordan', `insert into requests (title, pickup_label, destination_label, deliver_by) values ('Old ask', 'Any store', 'Unit 2', now() + interval '1 hour') returning id`);
const q4 = await as('jordan', `insert into requests (title, pickup_label, destination_label, deliver_by, reward_cents) values ('Unconfirmed', 'Any store', 'Unit 2', now() + interval '1 hour', 300) returning id`);
await as('nikhil', `select accept_request($1)`, [q4[0].id]);
await as('nikhil', `select advance_request($1, 'delivered')`, [q4[0].id]);
await as(null, `update requests set deliver_by = now() - interval '1 minute' where id = $1`, [q3[0].id]);
await as(null, `update requests set delivered_at = now() - interval '25 hours' where id = $1`, [q4[0].id]);
await as(null, `update runs set closes_at = now() - interval '4 hours' where id = '30000000-0000-0000-0000-000000000001'`);
await rejects('clients cannot run housekeeping', 'nikhil', `select expire_stale()`);
const hk = (await as(null, `select expire_stale() r`))[0].r;
check('expire_stale reports work done', hk.expired_requests >= 1 && hk.auto_completed === 1 && hk.closed_runs >= 1, JSON.stringify(hk));
const states = await as(null, `select title, status from requests where id in ($1, $2) order by title`, [q3[0].id, q4[0].id]);
check('overdue open request expired; old delivery auto-completed', states[0].status === 'expired' && states[1].status === 'completed', JSON.stringify(states));
check('stale run closed', (await as(null, `select status from runs where id = '30000000-0000-0000-0000-000000000001'`))[0].status === 'completed');
check('expired requests leave the Earn feed', (await as('nikhil', `select 1 from open_requests_nearby() where id = $1`, [q3[0].id])).length === 0);
const ev3 = (await as('jordan', `select status from request_events where request_id = $1 order by id`, [q3[0].id])).map(r => r.status);
check('expiry is on the timeline', JSON.stringify(ev3) === '["open","expired"]', JSON.stringify(ev3));

// --- account deletion --------------------------------------------------------------------------
const q5 = await as('jordan', `insert into requests (title, pickup_label, destination_label, deliver_by) values ('Mid-delivery', 'Any store', 'Unit 2', now() + interval '1 hour') returning id`);
await as('maya', `select accept_request($1)`, [q5[0].id]);
await as('maya', `select advance_request($1, 'picking_up')`, [q5[0].id]);
await rejects('anon cannot delete accounts', 'anon', `select delete_my_account()`);
await as('maya', `select delete_my_account()`);
check('deleted user is gone from auth and profiles', (await as(null, `select (select count(*) from auth.users where id = '${U.maya}')::int + (select count(*) from profiles where id = '${U.maya}')::int n`))[0].n === 0);
const handed = await as('jordan', `select status, helper_id from requests where id = $1`, [q5[0].id]);
check('in-flight delivery handed back to open', handed[0].status === 'open' && handed[0].helper_id === null, JSON.stringify(handed));
const sunday = await as(null, `select user_id, role from group_members where group_id = '20000000-0000-0000-0000-000000000001' and role = 'owner'`);
check('group ownership passed to the longest-standing member', sunday.length === 1 && sunday[0].user_id !== U.maya, JSON.stringify(sunday));
check('completed deliveries survive with helper cleared', (await as(null, `select count(*)::int n from requests where id = $1 and status = 'completed' and helper_id is null`, [q2[0].id]))[0].n === 1);
check('her messages remain with author cleared', (await as(null, `select count(*)::int n from messages where sender_id is null`))[0].n >= 2);


// --- adding places -----------------------------------------------------------------------------
const np = await as('nikhil', `select id, name, kind, campus_id, created_by from create_place('Walgreens', 'store', 37.8679, -122.2590, 'Telegraph Avenue', '2310 Telegraph Ave')`);
check('signed-in user adds a place on their campus', np[0].kind === 'store' && np[0].created_by === U.nikhil && !!np[0].campus_id);
const dup = await as('jordan', `select id from create_place('walgreens', 'store', 37.8680, -122.2591)`);
check('same name within 150 m returns the existing place', dup[0].id === np[0].id);
const twin = await as('jordan', `select id from create_place('Walgreens', 'store', 37.8790, -122.2690)`);
check('same name far away is a different place', twin[0].id !== np[0].id);
await rejects('places far from campus are refused', 'nikhil', `select create_place('Times Square', 'other', 40.7580, -73.9855)`);
await rejects('blank names are refused', 'nikhil', `select create_place('  ', 'store', 37.87, -122.26)`);
await rejects('anon cannot add places', 'anon', `select create_place('X', 'store', 37.87, -122.26)`);
await as(null, `insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-0000000000aa', 'pat@gmail.com', '{}')`);
U.pat = '00000000-0000-0000-0000-0000000000aa';
check('any email gets the default campus', (await as('pat', `select campus_id is not null as assigned from profiles where id = auth.uid()`))[0].assigned);
check('standard account can add places', (await as('pat', `select id from create_place('Corner store', 'store', 37.87, -122.26)`)).length === 1);
await rejects('clients cannot insert places directly', 'nikhil', `insert into places (campus_id, name, kind, lat, lng) values ('c0000000-0000-0000-0000-000000000001', 'Sneaky', 'store', 37.87, -122.26)`);
await as(null, `insert into places (campus_id, name, kind, lat, lng, created_by) select 'c0000000-0000-0000-0000-000000000001', 'Bulk ' || g, 'other', 37.87, -122.26, '${U.jordan}' from generate_series(1, 25) g`);
await rejects('25 new places per user per day', 'jordan', `select create_place('One too many', 'other', 37.871, -122.261)`);
const cvs = await as('nikhil', `select id from create_place('CVS Pharmacy', 'store', 37.86750, -122.26800)`);
check('"CVS Pharmacy" from Apple Maps matches the seeded "CVS"', cvs[0].id === 'a0000000-0000-0000-0000-000000000003');
check('new places are visible to everyone signed in', (await as('devon', `select 1 from places where name = 'Walgreens'`)).length === 2);

// --- home building, leaving groups, request chat ----------------------------------------------
const UNIT2 = 'a0000000-0000-0000-0000-000000000008', DURANT = 'a0000000-0000-0000-0000-000000000007';
const g1 = await as('jordan', `select id, name, kind, place_id from set_home_place($1)`, [UNIT2]);
check('setting a residence as home creates its building group', g1[0].kind === 'building' && g1[0].place_id === UNIT2 && g1[0].name === 'Unit 2', JSON.stringify(g1));
check('…and makes it your home', (await as('jordan', `select home_place_id from profiles where id = auth.uid()`))[0].home_place_id === UNIT2);
const g2 = await as('devon', `select id from set_home_place($1)`, [UNIT2]);
check('a neighbor joins the same group rather than creating another', g2[0].id === g1[0].id);
check('…and leaves their previous building', (await as(null, `select count(*)::int n from group_members m join groups g on g.id = m.group_id where m.user_id = '${U.devon}' and g.kind = 'building'`))[0].n === 1);
check('a non-residence home joins no group', (await as('nikhil', `select set_home_place('a0000000-0000-0000-0000-000000000004') g`))[0].g === null);
check('standard account can set a home', (await as('pat', `select set_home_place($1) g`, [UNIT2]))[0].g !== null);
await rejects('anon cannot set a home', 'anon', `select set_home_place($1)`, [UNIT2]);
const viaJoin = await as('nikhil', `select join_building_group('20000000-0000-0000-0000-000000000003') g`);
check('joining a building group makes it home', (await as('nikhil', `select home_place_id from profiles where id = auth.uid()`))[0].home_place_id === DURANT, JSON.stringify(viaJoin));

await as('devon', `select leave_group($1)`, [g1[0].id]);
check('leaving a building clears it as home', (await as('devon', `select home_place_id from profiles where id = auth.uid()`))[0].home_place_id === null);
const fg = await as('nikhil', `select id from create_group('Leavers')`);
await as(null, `insert into group_members (group_id, user_id) values ($1, '${U.jordan}')`, [fg[0].id]);
await as('nikhil', `select leave_group($1)`, [fg[0].id]);
check('when the owner leaves, the next member owns the group', (await as(null, `select role from group_members where group_id = $1 and user_id = '${U.jordan}'`, [fg[0].id]))[0]?.role === 'owner');
await as('jordan', `select leave_group($1)`, [fg[0].id]);
check('the last member out closes the group', (await as(null, `select count(*)::int n from groups where id = $1`, [fg[0].id]))[0].n === 0);
await rejects('cannot leave a group you are not in', 'devon', `select leave_group('20000000-0000-0000-0000-000000000001')`);

const cq = await as('jordan', `insert into requests (title, pickup_label, destination_label, deliver_by) values ('Chat test', 'Any store', 'Unit 2', now() + interval '1 hour') returning id`);
await rejects('no chat before anyone accepts', 'jordan', `insert into request_messages (request_id, body) values ($1, 'hello?')`, [cq[0].id]);
await as('nikhil', `select accept_request($1)`, [cq[0].id]);
const rm = await as('jordan', `insert into request_messages (request_id, body) values ($1, 'Thanks! Room 214') returning sender_id`, [cq[0].id]);
check('requester messages the helper as themselves', rm[0].sender_id === U.jordan);
await as('nikhil', `insert into request_messages (request_id, body) values ($1, 'On it')`, [cq[0].id]);
check('both participants read the chat', (await as('jordan', `select 1 from request_messages where request_id = $1`, [cq[0].id])).length === 2 && (await as('nikhil', `select 1 from request_messages where request_id = $1`, [cq[0].id])).length === 2);
check('others cannot read it', (await as('devon', `select 1 from request_messages where request_id = $1`, [cq[0].id])).length === 0);
await rejects('others cannot post to it', 'devon', `insert into request_messages (request_id, body) values ($1, 'hi')`, [cq[0].id]);
await rejects('cannot spoof the sender', 'nikhil', `insert into request_messages (request_id, body, sender_id) values ($1, 'x', '${U.jordan}')`, [cq[0].id]);
await as('nikhil', `select advance_request($1, 'delivered')`, [cq[0].id]).catch(() => {});
await as('jordan', `select advance_request($1, 'completed')`, [cq[0].id]).catch(() => {});
await rejects('chat closes when the request is finished', 'jordan', `insert into request_messages (request_id, body) values ($1, 'late')`, [cq[0].id]);

console.log(failures ? `\n${failures} FAILED` : '\nALL PASSED');
process.exit(failures ? 1 : 0);
