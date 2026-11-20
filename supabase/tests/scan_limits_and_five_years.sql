-- Scan limits per route and the five-year end date (202611200004). Run as
-- postgres in the Supabase SQL Editor ("Run without RLS" is fine): everything
-- rolls back, and the last line reports how many checks passed.
begin;
-- Fixture accounts have no store purchase (202611200005).
set local stop_swiping.access_check = 'off';
create temporary table five_results(name text primary key);
grant select, insert on five_results to authenticated;
create function pg_temp.ok(passed boolean, label text) returns void
language plpgsql as $$ begin
    if passed is distinct from true then raise exception 'FAILED: %', label; end if;
    insert into five_results values(label);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
    select ('f1ae0000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.error_of(statement text) returns text
language plpgsql as $$ begin
    execute statement;
    return null;
exception when others then return sqlstate || ' ' || sqlerrm;
end; $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.id(integer), pg_temp.error_of(text) to authenticated;

insert into auth.users(id, aud, role) select pg_temp.id(n), 'authenticated', 'authenticated' from generate_series(1, 2) n;
insert into public.profiles(id, profile, backup) select pg_temp.id(n), '{"displayName":"Scan"}',
    jsonb_build_object('state', jsonb_build_object(
        'storedAutoMatching', jsonb_build_object('photoID', pg_temp.id(100 + n)),
        'profilePrivacyConsent', jsonb_build_object('version', '2026-11-15.v2'))) from generate_series(1, 2) n;
insert into storage.objects(bucket_id, name, owner) select 'profile-photos',
    pg_temp.id(n)::text || '/' || pg_temp.id(100 + n)::text || '.jpg', pg_temp.id(n) from generate_series(1, 2) n;

-- ===== 1. Scans on the phone have no daily limit ============================
-- Since 202611200005 only the app-attest function records a scan.
select pg_temp.ok(public.record_attested_photo_verification(pg_temp.id(1), pg_temp.id(101)), format('Phone scan %s recorded', n))
    from generate_series(1, 7) n;
select pg_temp.ok((select count(*) = 7 from matching_private.verification_attempts where user_id = pg_temp.id(1)),
    'Seven phone scans in a day are all kept');
select pg_temp.ok(exists (select 1 from matching_private.search_state where user_id = pg_temp.id(1)),
    'A scan searches through the one-a-minute rule');
select pg_temp.ok(public.record_attested_photo_verification(pg_temp.id(1), pg_temp.id(101)),
    'An attested scan after seven others is recorded too');

-- ===== 2. AWS keeps 5 a day, counting only AWS ==============================
select set_config('request.jwt.claim.sub', pg_temp.id(1)::text, true);
select pg_temp.ok((public.begin_photo_verification(pg_temp.id(101), '2026-11-14.aws.v1') ? 'request_id'),
    format('AWS session %s starts despite the phone scans', n)) from generate_series(1, 5) n;
select pg_temp.ok(pg_temp.error_of(format('select public.begin_photo_verification(%L, %L)',
    pg_temp.id(101), '2026-11-14.aws.v1')) like '% Daily verification limit reached',
    'The sixth AWS session of the day is refused');
select pg_temp.ok(not has_function_privilege('authenticated', 'public.begin_photo_verification(uuid, text)', 'execute'),
    'AWS stays parked for the app');

-- ===== 3. Five years ========================================================
insert into auth.users(id, aud, role) select pg_temp.id(n), 'authenticated', 'authenticated' from generate_series(11, 18) n;
insert into public.matches(id, user_low, user_high, score_low, score_high, matched_at, ended_at, end_reason) values
    (pg_temp.id(201), pg_temp.id(11), pg_temp.id(12), 80, 80, now() - interval '6 years', now() - interval '5 years 1 day', 'broken'),
    (pg_temp.id(202), pg_temp.id(13), pg_temp.id(14), 80, 80, now() - interval '5 years', now() - interval '4 years', 'broken'),
    (pg_temp.id(203), pg_temp.id(15), pg_temp.id(16), 80, 80, now() - interval '6 years', now() - interval '5 years 1 day', 'reported'),
    (pg_temp.id(204), pg_temp.id(17), pg_temp.id(18), 80, 80, now() - interval '6 years', null, null);
insert into matching_private.match_identities(match_id, user_id, identity_hashes)
    select pg_temp.id(200 + n), pg_temp.id(10 + 2 * n), array['fixture:' || n] from generate_series(1, 4) n;
insert into public.match_reports(match_id, reported_id, reason, details, created_at, counts_as_strike) values
    (pg_temp.id(203), pg_temp.id(16), 'spam', '', now() - interval '4 years', true),
    (pg_temp.id(202), pg_temp.id(14), 'spam', '', now() - interval '5 years 1 day', true);

select matching_private.purge_expired();

select pg_temp.ok(not exists (select 1 from public.matches where id = pg_temp.id(201)),
    'A match that ended over five years ago goes');
select pg_temp.ok(not exists (select 1 from matching_private.match_identities where match_id = pg_temp.id(201)),
    'Its identity hashes go with it');
select pg_temp.ok(exists (select 1 from public.matches where id = pg_temp.id(202)),
    'A match that ended four years ago stays');
select pg_temp.ok(exists (select 1 from public.matches where id = pg_temp.id(203)),
    'An old match stays while a report about it remains');
select pg_temp.ok(exists (select 1 from public.matches where id = pg_temp.id(204)),
    'An active match is never removed');
select pg_temp.ok(not exists (select 1 from public.match_reports where match_id = pg_temp.id(202)),
    'A report over five years old goes, and its strike with it');
select pg_temp.ok(exists (select 1 from public.match_reports where match_id = pg_temp.id(203)),
    'A four-year-old report stays');

do $$ begin
    raise exception 'TEST RESULT: % checks passed', (select count(*) from five_results);
end; $$;
rollback;
