-- The partner's photo in an active match (202611160003). Run as postgres in
-- the Supabase SQL Editor ("Run without RLS" is fine): everything rolls back.
-- Covers: the photo and its verification in current_match, Storage access for
-- the partner only, nothing for outsiders, and nothing once the match ends.
begin;
-- Saves follow each other within milliseconds here: no one-minute search limit
-- (202611180005). Its own checks are at the end of matching_regression.sql.
set local stop_swiping.matching_throttle = 'off';
create temporary table photo_results(name text primary key);
grant select, insert on photo_results to authenticated;
create function pg_temp.ok(passed boolean, label text) returns void
language plpgsql as $$ begin
    if passed is distinct from true then raise exception 'FAILED: %', label; end if;
    insert into photo_results values(label);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
    select ('a7fc0000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.as_user(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', pg_temp.id(n)::text, true), set_config('role', 'authenticated', true) $$;
create function pg_temp.as_admin() returns void language sql as $$
    select set_config('role', 'postgres', true) $$;
create function pg_temp.match_of(n integer) returns uuid language sql as $$
    select match_id from matching_private.matched_users where user_id = pg_temp.id(n) $$;
-- The photo's object name, as the app uploads it.
create function pg_temp.photo(n integer) returns text language sql immutable as $$
    select pg_temp.id(n)::text || '/' || lower(pg_temp.id(500 + n)::text) || '.jpg' $$;
create function pg_temp.sees(n integer) returns boolean language sql as $$
    select exists(select 1 from storage.objects where bucket_id = 'profile-photos' and name = pg_temp.photo(n)) $$;

create temporary table photo_fixture(p jsonb, b jsonb);
insert into photo_fixture
select jsonb_build_object(
    'displayName','Photo fixture','autoMatchingEnabled',true,'profileComplete',true,
    'dateOfBirth','1995-06-15T12:00:00Z','gender','nonBinary','interestedIn',jsonb_build_array('nonBinary'),
    'languages',jsonb_build_array('nl'),'heightCentimeters',175,
    'ownAttractiveness',7,'partnerMinimumAttractiveness',5,'minimumMatchPercent',70,
    'coarseLatitude',-88,'coarseLongitude',-170,'preferredRadiusKilometers',1,
    'preferredPartnerMinimumAge',18,'preferredPartnerMaximumAge',80,
    'religion','other','acceptedPartnerReligions',jsonb_build_array('other'),
    'requiresVerifiedPartnerPhoto',false,
    'relationshipPreferences',jsonb_build_object('sexualArrangement',jsonb_build_array('partnerOnly')),
    'lifestyle',jsonb_build_object('hasChildren',false,'openToPartnerWithChildren',true,'futureChildren','notSure',
        'aloneTime',jsonb_build_object('own',3,'partner',3,'importance',3),
        'storedCompatibilityAnswers',(select jsonb_object_agg(q,jsonb_build_object('own',3,'partner',3,'importance',3))
            from unnest(matching_private.question_ids()) q where q <> 'aloneTime'),
        'substances',jsonb_build_object(
            'alcohol',jsonb_build_object('ownLevel',0,'partnerMaximumLevel',5),
            'smoking',jsonb_build_object('ownLevel',0,'partnerMaximumLevel',5),
            'drugs',jsonb_build_object('ownLevel',0,'partnerMaximumLevel',5)))),
    '{"state":{"profilePrivacyConsent":{"version":"2026-11-15.v2"},"storedAutoMatching":{"privacyConsent":{"version":"2026-11-15.v2"}}}}'::jsonb;
-- Joins with a matching photo; the app stores its ID upper-cased.
create function pg_temp.join(n integer) returns void language sql as $$
    insert into storage.objects(bucket_id, name, owner) values ('profile-photos', pg_temp.photo(n), pg_temp.id(n));
    insert into public.profiles(id, profile, backup)
        select pg_temp.id(n), p, jsonb_set(b, '{state,storedAutoMatching,photoID}', to_jsonb(upper(pg_temp.id(500 + n)::text)))
        from photo_fixture $$;

insert into auth.users(id, aud, role) select pg_temp.id(n), 'authenticated', 'authenticated' from generate_series(1, 3) n;
select pg_temp.join(1);
select pg_temp.join(2);
select pg_temp.ok(pg_temp.match_of(1) is not null and pg_temp.match_of(1) = pg_temp.match_of(2), 'Both are matched');
-- Only person 2's photo was verified with a live scan.
insert into matching_private.photo_verifications(object_id, object_updated_at)
    select id, updated_at from storage.objects where bucket_id = 'profile-photos' and name = pg_temp.photo(2);
select pg_temp.join(3);

-- ===== Active match =======================================================
select pg_temp.as_user(1);
select pg_temp.ok(public.current_match()->>'partner_photo' = pg_temp.photo(2), 'current_match names the partner''s photo');
select pg_temp.ok((public.current_match()->>'partner_photo_verified')::boolean, 'A verified partner photo is marked verified');
select pg_temp.ok(pg_temp.sees(2), 'The partner''s photo can be downloaded');
select pg_temp.ok(pg_temp.sees(1), 'Your own photo can still be downloaded');
select pg_temp.ok(not pg_temp.sees(3), 'Someone you are not matched with stays hidden');
select pg_temp.as_user(2);
select pg_temp.ok(public.current_match()->>'partner_photo' = pg_temp.photo(1), 'The other side gets your photo too');
select pg_temp.ok(not (public.current_match()->>'partner_photo_verified')::boolean, 'An unverified photo is not marked verified');
select pg_temp.ok(pg_temp.sees(1), 'Both sides can download');
select pg_temp.as_user(3);
select pg_temp.ok(not pg_temp.sees(1) and not pg_temp.sees(2), 'An outsider sees neither photo');
select pg_temp.ok(not public.can_view_match_photo(pg_temp.photo(1)), 'An outsider is never allowed a match photo');

-- ===== Changing the photo =================================================
-- An older photo of the partner is never shared, only the current one.
select pg_temp.as_admin();
insert into storage.objects(bucket_id, name, owner) values ('profile-photos', pg_temp.id(2)::text || '/old.jpg', pg_temp.id(2));
select pg_temp.as_user(1);
select pg_temp.ok(not exists(select 1 from storage.objects where name = pg_temp.id(2)::text || '/old.jpg'),
    'Other photos of the partner stay hidden');

-- ===== After the match ends ===============================================
-- Clients cannot read matching_private, so the match ID is looked up first.
select pg_temp.as_admin();
create temporary table photo_match as select pg_temp.match_of(1) as id;
grant select on photo_match to authenticated;
select pg_temp.as_user(1);
select public.break_match((select id from photo_match));
-- Breaking puts person 1 back in the pool, where person 3 is waiting.
select pg_temp.ok((select m->'partner_photo' = 'null'::jsonb and not (m->>'partner_photo_verified')::boolean
    from jsonb_array_elements(public.my_matches()) m where m->>'partner_id' = pg_temp.id(2)::text),
    'A broken match carries no photo');
select pg_temp.ok(not pg_temp.sees(2), 'The photo can no longer be downloaded once the match ends');

-- ===== Privileges =========================================================
select pg_temp.as_admin();
select pg_temp.ok(not has_function_privilege('anon', 'public.can_view_match_photo(text)', 'execute'), 'Anonymous cannot ask');
select pg_temp.ok(not has_function_privilege('authenticated', 'matching_private.matching_photo_name(uuid)', 'execute'),
    'Clients cannot look up anyone''s photo name');

select name, 'PASS' as result, count(*) over () as total_passed from photo_results order by name;
rollback;
