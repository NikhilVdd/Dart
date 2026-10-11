-- Let signed-in users add places (from Apple Maps search in the app) instead of seeding them by SQL.
--
-- create_place():
--   * requires a campus (from a campus email) and a point within 15 km of that campus
--   * de-duplicates: a place within 150 m whose name matches (or contains / is contained in) the
--     new name is returned instead, so "CVS" and Apple Maps' "CVS Pharmacy" are one place
--   * limits each user to 25 new places per day
--   * records who added the place

-- Align the launch places with Apple Maps so search results de-duplicate against them.
-- (Ida Sproul Hall was ~550 m off and Blackwell Hall ~170 m; the rest move by under 80 m.)
update public.places as p set lat = v.lat, lng = v.lng
from (values
  ('a0000000-0000-0000-0000-000000000001'::uuid, 37.86962, -122.26755),  -- Target
  ('a0000000-0000-0000-0000-000000000002'::uuid, 37.87200, -122.27322),  -- Trader Joe's
  ('a0000000-0000-0000-0000-000000000003'::uuid, 37.86745, -122.26804),  -- CVS (2300 Shattuck)
  ('a0000000-0000-0000-0000-000000000004'::uuid, 37.87252, -122.26077),  -- Moffitt Library
  ('a0000000-0000-0000-0000-000000000005'::uuid, 37.86693, -122.26093),  -- Ida Sproul Hall
  ('a0000000-0000-0000-0000-000000000006'::uuid, 37.86770, -122.26109),  -- Blackwell Hall
  ('a0000000-0000-0000-0000-000000000007'::uuid, 37.86766, -122.25866),  -- The Durant
  ('a0000000-0000-0000-0000-000000000008'::uuid, 37.86631, -122.25526),  -- Unit 2 · Cunningham Hall
  ('a0000000-0000-0000-0000-000000000009'::uuid, 37.87010, -122.26815),  -- Downtown Berkeley BART
  ('a0000000-0000-0000-0000-00000000000a'::uuid, 37.87022, -122.25948)   -- Sather Gate
) as v (id, lat, lng)
where p.id = v.id;

alter table public.places
  add column created_by uuid references public.profiles (id) on delete set null;

create index places_created_by_idx on public.places (created_by, created_at);

create function public.create_place(
  p_name text,
  p_kind public.place_kind,
  p_lat double precision,
  p_lng double precision,
  p_detail text default null,
  p_address text default null
)
returns public.places
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_campus public.campuses;
  v_name text := btrim(coalesce(p_name, ''));
  v_place public.places;
begin
  if v_uid is null then
    raise exception 'sign in required' using errcode = '42501';
  end if;

  select c.* into v_campus from public.campuses c where c.id = public.my_campus_id();
  if not found then
    raise exception 'sign in with a campus email to add places' using errcode = '42501';
  end if;

  if char_length(v_name) not between 1 and 80 then
    raise exception 'place name must be 1–80 characters' using errcode = '22023';
  end if;
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'invalid coordinates' using errcode = '22023';
  end if;
  if public.distance_m(v_campus.lat, v_campus.lng, p_lat, p_lng) > 15000 then
    raise exception 'that place is too far from %', v_campus.name using errcode = '22023';
  end if;

  -- Same place nearby: reuse it rather than creating a duplicate.
  select p.* into v_place
  from public.places p
  where p.campus_id = v_campus.id
    and (strpos(lower(p.name), lower(v_name)) > 0 or strpos(lower(v_name), lower(p.name)) > 0)
    and public.distance_m(p.lat, p.lng, p_lat, p_lng) < 150
  order by (lower(p.name) = lower(v_name)) desc, public.distance_m(p.lat, p.lng, p_lat, p_lng)
  limit 1;
  if found then
    return v_place;
  end if;

  if (select count(*) from public.places
      where created_by = v_uid and created_at > now() - interval '1 day') >= 25 then
    raise exception 'you can add up to 25 places a day' using errcode = 'P0001';
  end if;

  insert into public.places (campus_id, name, detail, kind, address, lat, lng, created_by)
  values (v_campus.id, v_name, nullif(btrim(coalesce(p_detail, '')), ''), p_kind,
          nullif(btrim(coalesce(p_address, '')), ''), p_lat, p_lng, v_uid)
  returning * into v_place;
  return v_place;
end;
$$;

revoke execute on function public.create_place(text, public.place_kind, double precision, double precision, text, text) from public, anon;
grant execute on function public.create_place(text, public.place_kind, double precision, double precision, text, text) to authenticated;
