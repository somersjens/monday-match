-- Fewer requests per poll, and retention (202611190002). Run as postgres in
-- the Supabase SQL Editor ("Run without RLS" is fine): everything rolls back.
-- Covers: current_match leaving out a card the phone has, chat_poll for
-- participants and outsiders, the key fingerprint, and what the retention
-- job removes and keeps.
begin;
set local stop_swiping.matching_throttle = 'off';
create temporary table retention_results(name text primary key);
grant select, insert on retention_results to authenticated;
create function pg_temp.ok(passed boolean, label text) returns void
language plpgsql as $$ begin
    if passed is distinct from true then raise exception 'FAILED: %', label; end if;
    insert into retention_results values(label);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
    select ('b8de0000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.as_user(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', pg_temp.id(n)::text, true), set_config('role', 'authenticated', true) $$;
create function pg_temp.as_admin() returns void language sql as $$
    select set_config('role', 'postgres', true) $$;
create function pg_temp.match_of(n integer) returns uuid language sql as $$
    select match_id from matching_private.matched_users where user_id = pg_temp.id(n) $$;
create function pg_temp.photo(n integer) returns text language sql immutable as $$
    select pg_temp.id(n)::text || '/' || lower(pg_temp.id(500 + n)::text) || '.jpg' $$;
create function pg_temp.due(n integer, what text) returns boolean language sql as $$
    select exists(select 1 from matching_private.retention_due where user_id = pg_temp.id(n) and action = what) $$;
create function pg_temp.stored(name text) returns boolean language sql as $$
    select exists(select 1 from storage.objects where bucket_id = 'profile-photos' and storage.objects.name = stored.name) $$;
-- Moves a profile's last save into the past. Only updated_at changes, so
-- the matching trigger (on profile and backup) does not run either.
create function pg_temp.age(n integer, ago interval) returns void language plpgsql as $$ begin
    alter table public.profiles disable trigger profiles_updated_at;
    update public.profiles set updated_at = now() - ago where id = pg_temp.id(n);
    alter table public.profiles enable trigger profiles_updated_at;
end; $$;

create temporary table retention_fixture(p jsonb, b jsonb);
insert into retention_fixture
select jsonb_build_object(
    'displayName','Retention fixture','autoMatchingEnabled',true,'profileComplete',true,
    'dateOfBirth','1995-06-15T12:00:00Z','gender','nonBinary','interestedIn',jsonb_build_array('nonBinary'),
    'languages',jsonb_build_array('nl'),'heightCentimeters',175,
    'ownAttractiveness',7,'partnerMinimumAttractiveness',5,'minimumMatchPercent',70,
    'coarseLatitude',-87,'coarseLongitude',170,'preferredRadiusKilometers',1,
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
    '{"state":{"profilePrivacyConsent":{"version":"2026-11-15.v2"},"storedAutoMatching":{"privacyConsent":{"version":"2026-11-15.v2"},"hasCompletedSetup":true}},"draft":{"autoMatching":{"hasCompletedSetup":true}}}'::jsonb;
-- Joins with a photo the row names, the way the app saves it (IDs upper-cased).
create function pg_temp.join(n integer, matching boolean default true, gender text default 'nonBinary') returns void
language sql as $$
    insert into storage.objects(bucket_id, name, owner, created_at)
        values ('profile-photos', pg_temp.photo(n), pg_temp.id(n), now() - interval '90 days');
    insert into public.profiles(id, profile, backup)
        select pg_temp.id(n),
            p || jsonb_build_object('autoMatchingEnabled', matching, 'gender', gender,
                'interestedIn', jsonb_build_array(gender),
                'photoURLs', jsonb_build_array('https://x.test/storage/v1/object/authenticated/profile-photos/'
                    || pg_temp.id(n)::text || '/' || upper(pg_temp.id(500 + n)::text) || '.jpg')),
            jsonb_set(jsonb_set(jsonb_set(b, '{state,storedAutoMatching,photoID}', to_jsonb(upper(pg_temp.id(500 + n)::text))),
                '{draft,autoMatching,photoID}', to_jsonb(upper(pg_temp.id(500 + n)::text))),
                '{photos}', jsonb_build_array(jsonb_build_object('id', upper(pg_temp.id(500 + n)::text), 'order', 0)))
        from retention_fixture $$;

insert into auth.users(id, aud, role, last_sign_in_at)
    select pg_temp.id(n), 'authenticated', 'authenticated', now() - interval '2 years' from generate_series(1, 8) n;
-- 1 and 2 are matched and chat; 3 is an outsider.
select pg_temp.join(1);
select pg_temp.join(2);
select pg_temp.ok(pg_temp.match_of(1) is not null and pg_temp.match_of(1) = pg_temp.match_of(2), 'Fixture: 1 and 2 are matched');
select pg_temp.join(3, false);
create temporary table chat as select pg_temp.match_of(1) as id;
grant select on chat to authenticated;

-- ===== current_match leaves out a card the phone already has =============
insert into public.match_cards(match_id, user_id, card) values ((select id from chat), pg_temp.id(2), 'card-of-2');
select pg_temp.as_user(1);
select pg_temp.ok(public.current_match()->>'partner_card' = 'card-of-2', 'Without arguments the card comes along, as before');
select pg_temp.ok(public.current_match(pg_temp.id(999))->>'partner_card' = 'card-of-2',
    'A card kept for another match does not count');
select pg_temp.ok(not (public.current_match((select id from chat)) ? 'partner_card'),
    'The card the phone keeps for this match is left out');
select pg_temp.ok(public.current_match((select id from chat))->>'partner_photo' = pg_temp.photo(2),
    'Everything else still comes');

-- ===== chat_poll ==========================================================
select pg_temp.as_admin();
insert into public.match_key_bundles(match_id, user_id, device_id, public_bundle) values
    ((select id from chat), pg_temp.id(1), pg_temp.id(101), '{"protocol":"hpke-auth-x25519-v1","key":"AAAA"}'),
    ((select id from chat), pg_temp.id(2), pg_temp.id(102), '{"protocol":"hpke-auth-x25519-v1","key":"BBBB"}');
insert into public.encrypted_messages(match_id, sender_id, client_message_id, sender_device_id, recipient_device_id,
        ciphertext, protocol_version)
    select (select id from chat), pg_temp.id(1 + n % 2), gen_random_uuid(), pg_temp.id(101 + n % 2), pg_temp.id(102 - n % 2),
        'envelope-' || n, 'hpke-auth-x25519-v1'
    from generate_series(1, 105) n;
create temporary table chat_rows as
    select min(id) as first_id, max(id) as last_id from public.encrypted_messages where match_id = (select id from chat);
grant select on chat_rows to authenticated;
insert into public.match_read_states(match_id, user_id, last_read_message_id)
    values ((select id from chat), pg_temp.id(2), (select last_id - 5 from chat_rows));

select pg_temp.as_user(1);
create temporary table first_poll as select public.chat_poll((select id from chat)) as r;
select pg_temp.ok(not (select (r->>'closed')::boolean from first_poll), 'An active match is open');
select pg_temp.ok((select jsonb_array_length(r->'messages') from first_poll) = 100, 'The first poll returns one page');
select pg_temp.ok((select (r->'messages'->-1->>'id')::bigint from first_poll) = (select last_id from chat_rows)
    and (select (r->'messages'->0->>'id')::bigint from first_poll) = (select last_id - 99 from chat_rows),
    'The first page is the newest 100, oldest first');
select pg_temp.ok((select r->'messages'->0 ?& array['id','sender_id','client_message_id','sender_device_id',
    'recipient_device_id','ciphertext','protocol_version','created_at'] from first_poll),
    'Messages carry the columns the app decodes');
select pg_temp.ok((select (r->>'partner_read_at')::timestamptz from first_poll) = (select created_at
    from public.encrypted_messages where id = (select last_id - 5 from chat_rows)), 'The partner''s read receipt comes along');
select pg_temp.ok(jsonb_array_length(public.chat_poll((select id from chat), (select last_id - 3 from chat_rows))->'messages') = 3,
    'After a cursor only newer messages come');
select pg_temp.ok(jsonb_array_length(public.chat_poll((select id from chat), (select last_id from chat_rows))->'messages') = 0,
    'Nothing new, nothing sent');
select pg_temp.ok(public.chat_poll((select id from chat), (select last_id from chat_rows))->>'keys'
    = (select r->>'keys' from first_poll), 'The key fingerprint is stable');
select pg_temp.as_admin();
update public.match_key_bundles set revoked_at = now() where device_id = pg_temp.id(102);
select pg_temp.as_user(1);
select pg_temp.ok(public.chat_poll((select id from chat), (select last_id from chat_rows))->>'keys'
    <> (select r->>'keys' from first_poll), 'A revoked device changes the fingerprint');
select pg_temp.as_user(3);
select pg_temp.ok((public.chat_poll((select id from chat))->>'closed')::boolean
    and jsonb_array_length(public.chat_poll((select id from chat))->'messages') = 0,
    'An outsider sees a closed chat without messages');
select pg_temp.ok(public.chat_poll((select id from chat))->>'partner_read_at' is null, 'An outsider gets no read receipt');

-- ===== Live signals =======================================================
-- Inserting the 105 messages above signalled the match channel each time.
select pg_temp.as_admin();
create function pg_temp.signals(what text) returns bigint language sql as $$
    select count(*) from realtime.messages
    where topic = 'match:' || (select id from chat)::text and event = 'changed' and payload->>'what' = what $$;
select pg_temp.ok(pg_temp.signals('message') >= 105, 'Every message signals the match channel');
select pg_temp.ok(pg_temp.signals('read') >= 1, 'A read receipt signals it');
select pg_temp.ok(pg_temp.signals('keys') >= 2, 'Key bundles signal it');
select pg_temp.ok(pg_temp.signals('card') >= 1, 'A shared card signals it');
select pg_temp.ok(not exists(select 1 from realtime.messages
        where topic = 'match:' || (select id from chat)::text and payload ?| array['ciphertext','text','card']),
    'Signals carry no content');
select pg_temp.ok((select bool_and(private) from realtime.messages where topic = 'match:' || (select id from chat)::text),
    'Signals go out on a private channel');
-- Who may listen: the channel's topic is what Realtime checks the policy with.
select set_config('realtime.topic', 'match:' || (select id from chat)::text, true);
select pg_temp.as_user(1);
select pg_temp.ok(exists(select 1 from realtime.messages where topic = current_setting('realtime.topic')),
    'A participant may listen on the match channel');
select pg_temp.as_user(3);
select pg_temp.ok(not exists(select 1 from realtime.messages where topic = current_setting('realtime.topic')),
    'An outsider may not');
select set_config('realtime.topic', 'match:not-a-uuid', true);
select pg_temp.ok(not exists(select 1 from realtime.messages), 'A malformed topic is refused, not an error');
select pg_temp.as_admin();
select set_config('realtime.topic', '', true);

-- ===== Retention: matching off for 30 days ===============================
select pg_temp.as_admin();
select pg_temp.join(4, false);
select pg_temp.join(5, false);
select pg_temp.age(4, interval '40 days');
select pg_temp.age(5, interval '10 days');
select pg_temp.age(1, interval '40 days');
select pg_temp.ok(pg_temp.due(4, 'photos'), 'Matching off for 40 days: the photo is due');
select pg_temp.ok(not pg_temp.due(5, 'photos'), 'Matching off for 10 days: the photo stays');
select pg_temp.ok(not pg_temp.due(1, 'photos'), 'Matching on: the photo stays');
create temporary table removed4 as select public.retention_apply(pg_temp.id(4), 'photos') as names;
select pg_temp.ok((select names from removed4) = array[pg_temp.photo(4)], 'Apply names the photo to delete');
select pg_temp.ok((select backup->'photos' = '[]'::jsonb
        and not (backup #> '{state,storedAutoMatching}' ? 'photoID')
        and not (backup #> '{draft,autoMatching}' ? 'photoID')
        and not (backup #>> '{state,storedAutoMatching,hasCompletedSetup}')::boolean
        and profile->'photoURLs' = '[]'::jsonb
        and profile->>'displayName' = 'Retention fixture'
    from public.profiles where id = pg_temp.id(4)), 'The row names no photo any more and keeps the rest');
select pg_temp.ok(not pg_temp.due(4, 'photos'), 'Done once');
select pg_temp.ok(public.retention_apply(pg_temp.id(4), 'photos') = array[]::text[], 'Applying again does nothing');
select pg_temp.ok(public.retention_apply(pg_temp.id(5), 'photos') = array[]::text[]
    and (select jsonb_array_length(backup->'photos') from public.profiles where id = pg_temp.id(5)) = 1,
    'Apply refuses a cleanup that is not due');

-- ===== Retention: orphans =================================================
-- Person 4's photo, had the Storage delete failed, is now an orphan.
select pg_temp.ok(pg_temp.due(4, 'orphans'), 'A photo nothing names is found again');
insert into storage.objects(bucket_id, name, owner, created_at) values
    ('profile-photos', pg_temp.id(5)::text || '/old-replaced.jpg', pg_temp.id(5), now() - interval '3 days'),
    ('profile-photos', pg_temp.id(5)::text || '/just-uploaded.jpg', pg_temp.id(5), now() - interval '5 minutes');
select pg_temp.ok(public.retention_apply(pg_temp.id(5), 'orphans') = array[pg_temp.id(5)::text || '/old-replaced.jpg'],
    'Orphans: only the old unnamed photo, never the named one or one just uploaded');

-- ===== Retention: no sign of the app for 12 months =======================
select pg_temp.join(6, false);
select pg_temp.age(6, interval '13 months');
insert into public.push_devices(device_id, user_id, token, environment)
    values (pg_temp.id(106), pg_temp.id(6), repeat('a', 64), 'production');
select pg_temp.ok(pg_temp.due(6, 'profile'), '13 months without a sign of the app: the profile is due');
select pg_temp.ok(not pg_temp.due(6, 'photos'), 'Not also as photos');
insert into auth.sessions(id, user_id, created_at, updated_at) values (gen_random_uuid(), pg_temp.id(6), now(), now());
select pg_temp.ok(not pg_temp.due(6, 'profile'), 'A recent session keeps it');
delete from auth.sessions where user_id = pg_temp.id(6);
create temporary table removed6 as select public.retention_apply(pg_temp.id(6), 'profile') as names;
select pg_temp.ok(not exists(select 1 from public.profiles where id = pg_temp.id(6)), 'The profile is removed');
select pg_temp.ok(not exists(select 1 from public.push_devices where user_id = pg_temp.id(6)), 'Its push devices are removed');
select pg_temp.ok((select names from removed6) = array[pg_temp.photo(6)], 'Its photo is named for deletion');
select pg_temp.ok(exists(select 1 from auth.users where id = pg_temp.id(6)), 'The sign-in itself stays');

-- ===== Retention: dormant matchers leave the pool ========================
select pg_temp.join(7, true, 'man');
select pg_temp.join(8, true, 'woman');
select pg_temp.ok(exists(select 1 from matching_private.pool where user_id = pg_temp.id(7))
    and exists(select 1 from matching_private.pool where user_id = pg_temp.id(8)), 'Fixture: 7 and 8 wait in the pool');
select pg_temp.age(7, interval '7 months');
select pg_temp.age(8, interval '2 months');
select matching_private.remove_dormant_from_pool();
select pg_temp.ok(not exists(select 1 from matching_private.pool where user_id = pg_temp.id(7)), '7 months away: out of the pool');
select pg_temp.ok(exists(select 1 from matching_private.pool where user_id = pg_temp.id(8)), '2 months away: still in the pool');
select pg_temp.ok(exists(select 1 from public.profiles where id = pg_temp.id(7)), 'The dormant profile itself stays');
-- The app's next save puts the person back.
update public.profiles set profile = profile || jsonb_build_object('updatedAt', now()::text) where id = pg_temp.id(7);
select pg_temp.ok(exists(select 1 from matching_private.pool where user_id = pg_temp.id(7)), 'A new save returns them to the pool');

-- ===== Live signals: the end of a match ==================================
select pg_temp.as_user(2);
select public.break_match((select id from chat));
select pg_temp.as_admin();
select pg_temp.ok(pg_temp.signals('ended') = 1, 'Breaking the match signals it once');

-- ===== Privileges =========================================================
select pg_temp.ok(not has_function_privilege('authenticated', 'public.retention_claim(integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.retention_apply(uuid, text)', 'execute')
    and not has_function_privilege('anon', 'public.retention_apply(uuid, text)', 'execute'),
    'Only the service role runs retention');
select pg_temp.ok(has_function_privilege('service_role', 'public.retention_apply(uuid, text)', 'execute'), 'The service role can');
select pg_temp.ok(not has_function_privilege('anon', 'public.chat_poll(uuid, bigint)', 'execute')
    and not has_function_privilege('anon', 'public.current_match(uuid)', 'execute'), 'Anonymous cannot poll');
select pg_temp.ok(exists(select 1 from cron.job where jobname = 'retention'), 'The daily job is scheduled');

select name, 'PASS' as result, count(*) over () as total_passed from retention_results order by name;
rollback;
