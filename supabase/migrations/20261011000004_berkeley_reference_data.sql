-- Launch reference data: UC Berkeley and the first places on the map (coordinates approximate).
-- Anyone who signs up with an @berkeley.edu address is linked to this campus automatically.
-- Add more places with plain inserts; the matching engine only needs lat/lng and kind.

insert into public.campuses (id, slug, name, email_domains, lat, lng) values
  ('c0000000-0000-0000-0000-000000000001', 'uc-berkeley', 'UC Berkeley', '{berkeley.edu}', 37.8719, -122.2585);

insert into public.places (id, campus_id, name, detail, kind, address, lat, lng) values
  ('a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'Target', 'Shattuck Avenue', 'store', '2187 Shattuck Ave', 37.8701, -122.2682),
  ('a0000000-0000-0000-0000-000000000002', 'c0000000-0000-0000-0000-000000000001', 'Trader Joe''s', 'University Avenue', 'store', '1885 University Ave', 37.8716, -122.2730),
  ('a0000000-0000-0000-0000-000000000003', 'c0000000-0000-0000-0000-000000000001', 'CVS', 'Shattuck Avenue', 'store', '2300 Shattuck Ave', 37.8676, -122.2679),
  ('a0000000-0000-0000-0000-000000000004', 'c0000000-0000-0000-0000-000000000001', 'Moffitt Library', 'Front desk', 'library', null, 37.8726, -122.2607),
  ('a0000000-0000-0000-0000-000000000005', 'c0000000-0000-0000-0000-000000000001', 'Ida Sproul Hall', 'Unit 3', 'residence', null, 37.8675, -122.2547),
  ('a0000000-0000-0000-0000-000000000006', 'c0000000-0000-0000-0000-000000000001', 'Blackwell Hall', null, 'residence', null, 37.8672, -122.2593),
  ('a0000000-0000-0000-0000-000000000007', 'c0000000-0000-0000-0000-000000000001', 'The Durant', 'Lobby', 'residence', '2500 Durant Ave', 37.8679, -122.2589),
  ('a0000000-0000-0000-0000-000000000008', 'c0000000-0000-0000-0000-000000000001', 'Unit 2', 'Cunningham Hall', 'residence', null, 37.8660, -122.2555),
  ('a0000000-0000-0000-0000-000000000009', 'c0000000-0000-0000-0000-000000000001', 'Downtown Berkeley BART', null, 'transit', '2160 Shattuck Ave', 37.8701, -122.2681),
  ('a0000000-0000-0000-0000-00000000000a', 'c0000000-0000-0000-0000-000000000001', 'Sather Gate', null, 'campus', null, 37.8703, -122.2595);
