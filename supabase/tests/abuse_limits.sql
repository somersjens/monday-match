-- Limits against a signed-in account scripting the API (202611190001). Run as
-- postgres in the Supabase SQL Editor ("Run without RLS" is fine): everything
-- rolls back. Covers: photo uploads per account, push devices per account,
-- chat envelope size, messages per minute and per day, chat devices per
-- match, the per-minute write guard, and AWS staying parked.
begin;
-- Fixture accounts have no store purchase (202611200005).
set local stop_swiping.access_check = 'off';
set local stop_swiping.matching_throttle = 'off';
create temporary table limit_results(name text primary key);
grant select, insert on limit_results to authenticated, service_role;
create function pg_temp.ok(passed boolean, label text) returns void
language plpgsql as $$ begin
    if passed is distinct from true then raise exception 'FAILED: %', label; end if;
    insert into limit_results values(label);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
    select ('a7fd0000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.as_user(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', pg_temp.id(n)::text, true),
           set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.id(n), 'role', 'authenticated')::text, true),
           set_config('role', 'authenticated', true) $$;
create function pg_temp.as_admin() returns void language sql as $$
    select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '{}', true),
           set_config('role', 'postgres', true) $$;
-- The error a statement raises, or null when it succeeds. Its changes are
-- rolled back either way when it fails.
create function pg_temp.error_of(statement text) returns text
language plpgsql as $$ begin
    execute statement;
    return null;
exception when others then return sqlstate || ' ' || sqlerrm;
end; $$;
grant execute on function pg_temp.error_of(text) to authenticated;

insert into auth.users(id, aud, role) select pg_temp.id(n), 'authenticated', 'authenticated' from generate_series(1, 4) n;

-- ===== 1. Photo uploads ======================================================
select pg_temp.ok((select file_size_limit = 2097152 from storage.buckets where id = 'profile-photos'),
    'Photos are at most 2 MB');
create function pg_temp.upload(n integer, file text) returns text language sql as $$
    select pg_temp.error_of(format('insert into storage.objects(bucket_id, name, owner) values (%L, %L, %L)',
        'profile-photos', pg_temp.id(n)::text || '/' || file, pg_temp.id(n))) $$;
select pg_temp.as_user(3);
select pg_temp.ok((select bool_and(pg_temp.upload(3, gen_random_uuid()::text || '.jpg') is null)
    from generate_series(1, 12)), 'Twelve photos upload');
select pg_temp.ok(pg_temp.upload(3, gen_random_uuid()::text || '.jpg') like '42501 %row-level security%',
    'The thirteenth photo is refused');
select pg_temp.as_user(4);
select pg_temp.ok(pg_temp.upload(4, 'old.jpg') like '42501 %', 'Only <uuid>.jpg names are accepted');
select pg_temp.ok(pg_temp.upload(4, gen_random_uuid()::text || '.png') like '42501 %', 'Only .jpg is accepted');
select pg_temp.ok(pg_temp.upload(4, 'sub/' || gen_random_uuid()::text || '.jpg') like '42501 %', 'No subfolders');
select pg_temp.ok(pg_temp.error_of(format('insert into storage.objects(bucket_id, name, owner) values (%L, %L, %L)',
    'profile-photos', pg_temp.id(3)::text || '/' || gen_random_uuid()::text || '.jpg', pg_temp.id(4))) like '42501 %',
    'Nobody uploads into another account''s folder');
select pg_temp.ok(pg_temp.upload(4, gen_random_uuid()::text || '.jpg') is null, 'A normal photo still uploads');

-- ===== 2. Push devices =======================================================
-- now() is the same for the whole transaction, so each earlier registration
-- is moved a minute back to give the seven distinct ages.
do $$ begin
    for n in 1..7 loop
        perform pg_temp.as_user(4);
        perform public.register_push_device(pg_temp.id(300 + n), lpad(to_hex(n), 64, '0'), 'sandbox', 'UTC',
            true, true, false);
        perform pg_temp.as_admin();
        update public.push_devices set updated_at = updated_at - interval '1 minute' where user_id = pg_temp.id(4);
    end loop;
end $$;
select pg_temp.ok((select count(*) = 5 from public.push_devices where user_id = pg_temp.id(4)),
    'An account keeps at most five push devices');
select pg_temp.ok(exists (select 1 from public.push_devices where device_id = pg_temp.id(307))
    and not exists (select 1 from public.push_devices where device_id in (pg_temp.id(301), pg_temp.id(302))),
    'The oldest registrations go first');
-- Re-registering the oldest one remaining keeps it, now as the newest.
select pg_temp.as_user(4);
select public.register_push_device(pg_temp.id(303), lpad(to_hex(3), 64, '0'), 'sandbox', 'UTC', true, true, false);
select pg_temp.as_admin();
select pg_temp.ok((select count(*) = 5 from public.push_devices where user_id = pg_temp.id(4))
    and exists (select 1 from public.push_devices where device_id = pg_temp.id(303)),
    'Updating a registered phone keeps it');

-- ===== 3. Chat ===============================================================
create temporary table limit_fixture(p jsonb, b jsonb);
insert into limit_fixture
select jsonb_build_object(
    'displayName','Limit fixture','autoMatchingEnabled',true,'profileComplete',true,
    'dateOfBirth','1995-06-15T12:00:00Z','gender','nonBinary','interestedIn',jsonb_build_array('nonBinary'),
    'languages',jsonb_build_array('nl'),'heightCentimeters',175,
    'ownAttractiveness',7,'partnerMinimumAttractiveness',5,'minimumMatchPercent',70,
    'coarseLatitude',-86.5,'coarseLongitude',150,'preferredRadiusKilometers',1,
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
insert into public.profiles(id, profile, backup) select pg_temp.id(n), p, b from limit_fixture, generate_series(1, 2) n;
create temporary table limit_match as
    select match_id as id from matching_private.matched_users where user_id = pg_temp.id(1);
grant select on limit_match to authenticated;
select pg_temp.ok((select count(*) = 1 from limit_match)
    and (select match_id from matching_private.matched_users where user_id = pg_temp.id(2)) = (select id from limit_match),
    'The two chat fixtures are matched');

create function pg_temp.key(seed text) returns jsonb language sql immutable as $$
    select jsonb_build_object('protocol', 'hpke-auth-x25519-v1',
        'key', encode(substring(extensions.digest(seed, 'sha256') from 1 for 32), 'base64')) $$;
select pg_temp.as_user(1);
select public.register_chat_device((select id from limit_match), pg_temp.id(101), pg_temp.key('device-1'));
select pg_temp.as_user(2);
select public.register_chat_device((select id from limit_match), pg_temp.id(102), pg_temp.key('device-2'));

-- Person n sends message m of the given size to the other person.
create function pg_temp.send(n integer, m integer, size integer) returns text language sql as $$
    select pg_temp.error_of(format('select public.send_encrypted_message(%L, %L, %L, %L, %L)',
        (select id from limit_match), pg_temp.id(1000 * n + m), pg_temp.id(100 + n), pg_temp.id(103 - n),
        repeat('x', size))) $$;
grant execute on function pg_temp.send(integer, integer, integer) to authenticated;

select pg_temp.as_user(1);
select pg_temp.ok(pg_temp.send(1, 1, 32768) is null, 'A 32 kB envelope is accepted');
select pg_temp.ok(pg_temp.send(1, 2, 32769) like '% Message too large', 'A larger envelope is refused');
select pg_temp.ok((select bool_and(pg_temp.send(1, m, 600) is null) from generate_series(3, 61) m),
    'Sixty messages in a minute are accepted');
select pg_temp.ok(pg_temp.send(1, 62, 600) like 'PT429 Message limit reached',
    'The sixty-first message in a minute is refused with 429');
select pg_temp.ok(pg_temp.send(1, 3, 600) is null, 'Retrying a message that already arrived still works');

-- 5 MB a day: 159 envelopes of 32 kB sent hours ago leave exactly 32 kB of room.
select pg_temp.as_admin();
insert into public.encrypted_messages(match_id, sender_id, client_message_id, sender_device_id, recipient_device_id,
        ciphertext, protocol_version, created_at)
    select (select id from limit_match), pg_temp.id(2), gen_random_uuid(), pg_temp.id(102), pg_temp.id(101),
        repeat('y', 32768), 'hpke-auth-x25519-v1', now() - interval '2 hours'
    from generate_series(1, 159);
select pg_temp.as_user(2);
select pg_temp.ok(pg_temp.send(2, 1, 100) is null, 'Under the daily budget a message goes out');
select pg_temp.ok(pg_temp.send(2, 2, 32768) like 'PT429 Message limit reached', 'Past 5 MB a day messages wait');

-- Chat devices: ten per person per match, including revoked ones.
select pg_temp.as_user(2);
select public.register_chat_device((select id from limit_match), pg_temp.id(110 + n), pg_temp.key('switch-' || n), true)
    from generate_series(1, 9) n;
select pg_temp.ok(pg_temp.error_of(format('select public.register_chat_device(%L, %L, %L, true)',
    (select id from limit_match), pg_temp.id(120), pg_temp.key('switch-10'))) like 'PT429 Too many chat devices',
    'The eleventh chat device in one match is refused');
select pg_temp.ok(pg_temp.error_of(format('select public.register_chat_device(%L, %L, %L, true)',
    (select id from limit_match), pg_temp.id(119), pg_temp.key('switch-9'))) is null,
    'Registering the current device again still works');

-- ===== 4. Writes per minute ==================================================
select pg_temp.as_user(3);
select pg_temp.ok((select bool_and(pg_temp.error_of('select api_guard.check_request()') is null)
    from generate_series(1, 120)), '120 writes in a minute pass');
select pg_temp.ok(pg_temp.error_of('select api_guard.check_request()') like 'PT429 Too many requests%',
    'The 121st write in a minute is refused with 429');
select pg_temp.as_user(4);
select pg_temp.ok(pg_temp.error_of('select api_guard.check_request()') is null, 'Another account is not affected');
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '{"role":"service_role"}', true),
       set_config('role', 'service_role', true);
select pg_temp.ok((select bool_and(pg_temp.error_of('select api_guard.check_request()') is null)
    from generate_series(1, 150)), 'The service role is never limited');
select pg_temp.as_admin();
select pg_temp.ok((select writes = 120 from matching_private.api_writes where user_id = pg_temp.id(3))
    and (select writes = 1 from matching_private.api_writes where user_id = pg_temp.id(4))
    and (select count(*) = 2 from matching_private.api_writes where user_id in (pg_temp.id(3), pg_temp.id(4))),
    'Refused writes are not counted, and each account has its own counter');
select pg_temp.ok((select setconfig::text like '%pgrst.db_pre_request=api_guard.check_request%'
    from pg_db_role_setting where setrole = 'authenticator'::regrole and setdatabase = 0),
    'PostgREST runs the guard before every request');
select pg_temp.ok(has_function_privilege('anon', 'api_guard.check_request()', 'execute')
    and has_function_privilege('authenticated', 'api_guard.check_request()', 'execute')
    and has_function_privilege('service_role', 'api_guard.check_request()', 'execute'),
    'Every API role can run the guard');
select pg_temp.ok(not has_table_privilege('authenticated', 'matching_private.api_writes', 'select'),
    'Nobody reads the counters');

-- ===== 5. AWS stays parked ===================================================
select pg_temp.ok(not has_function_privilege('authenticated', 'public.begin_photo_verification(uuid,text)', 'execute')
    and not has_function_privilege('anon', 'public.begin_photo_verification(uuid,text)', 'execute'),
    'The app cannot start a paid AWS check');
select pg_temp.ok(not has_function_privilege('authenticated', 'public.record_device_photo_verification(uuid)', 'execute'),
    'Only proven (App Attest) scans count since 202611200005');
select pg_temp.ok(has_function_privilege('authenticated', 'public.can_upload_profile_photo(text)', 'execute')
    and not has_function_privilege('anon', 'public.can_upload_profile_photo(text)', 'execute'),
    'Only signed-in accounts may upload');

select name, 'PASS' as result, count(*) over () as total_passed from limit_results order by name;
rollback;
