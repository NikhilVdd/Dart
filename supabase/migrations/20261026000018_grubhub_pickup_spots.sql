-- Dart v1 pickups: requesters choose one of four campus eateries where their GrubHub order is
-- waiting. Golden Bear Cafe is already seeded by the Berkeley places expansion
-- (a1000000-...-000000000101); this adds the other three with fixed IDs the iOS app references
-- (DartApp/Dart/Domain/Models.swift, PickupSpot).
--
-- Monsoon Kitchens and Ladle & Leaf are Cal Dining eateries on the first floor of the MLK Jr.
-- Student Union (2495 Bancroft Way). Gateway Cafe is in the Gateway building at Hearst Avenue and
-- Arch Street. Like create_place(), a row is skipped when a place within 150 m already has a
-- matching name; the app then falls back to that place by name.

insert into public.places (id, campus_id, name, detail, kind, address, lat, lng)
select v.id::uuid, 'c0000000-0000-0000-0000-000000000001', v.name, v.detail, v.kind::public.place_kind, v.address, v.lat, v.lng
from (values
  ('a2000000-0000-0000-0000-000000000001', 'Monsoon Kitchens', 'MLK Student Union', 'restaurant', '2495 Bancroft Way', 37.86882, -122.25960),
  ('a2000000-0000-0000-0000-000000000002', 'Ladle & Leaf', 'MLK Student Union', 'restaurant', '2495 Bancroft Way', 37.86885, -122.25952),
  ('a2000000-0000-0000-0000-000000000003', 'Gateway Cafe', 'Gateway building', 'restaurant', 'Hearst Avenue & Arch Street', 37.87414, -122.26348)
) as v (id, name, detail, kind, address, lat, lng)
where not exists (
  select 1 from public.places p
  where p.campus_id = 'c0000000-0000-0000-0000-000000000001'
    and (strpos(lower(p.name), lower(v.name)) > 0 or strpos(lower(v.name), lower(p.name)) > 0)
    and public.distance_m(p.lat, p.lng, v.lat, v.lng) < 150
)
on conflict (id) do nothing;
