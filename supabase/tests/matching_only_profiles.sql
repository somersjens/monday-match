-- Only profiles in automatic matching stay on the server, and a match can be
-- deleted from one's own list (202611200002). Run as postgres in the Supabase
-- SQL Editor ("Run without RLS" is fine): everything rolls back.
begin;
-- Fixture accounts have no store purchase (202611200005).
set local stop_swiping.access_check = 'off';
set local stop_swiping.matching_throttle = 'off';
create temporary table leave_results(name text primary key);
grant select, insert on leave_results to authenticated;
create function pg_temp.ok(passed boolean, label text) returns void
language plpgsql as $$ begin
    if passed is distinct from true then raise exception 'FAILED: %', label; end if;
    insert into leave_results values(label);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
    select ('c9ef0000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
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
create function pg_temp.has_profile(n integer) returns boolean language sql as $$
    select exists(select 1 from public.profiles where id = pg_temp.id(n)) $$;
create function pg_temp.in_pool(n integer) returns boolean language sql as $$
    select exists(select 1 from matching_private.pool where user_id = pg_temp.id(n)) $$;
create function pg_temp.age(n integer, ago interval) returns void language plpgsql as $$ begin
    alter table public.profiles disable trigger profiles_updated_at;
    update public.profiles set updated_at = now() - ago where id = pg_temp.id(n);
    alter table public.profiles enable trigger profiles_updated_at;
end; $$;
create function pg_temp.set_matching(n integer, matching boolean) returns void language sql as $$
    update public.profiles set profile = profile || jsonb_build_object('autoMatchingEnabled', matching)
        where id = pg_temp.id(n) $$;

create temporary table leave_fixture(p jsonb, b jsonb);
insert into leave_fixture
select jsonb_build_object(
    'displayName','Leave fixture','autoMatchingEnabled',true,'profileComplete',true,
    'dateOfBirth','1995-06-15T12:00:00Z','gender','nonBinary','interestedIn',jsonb_build_array('nonBinary'),
    'languages',jsonb_build_array('nl'),'heightCentimeters',175,
    'ownAttractiveness',7,'partnerMinimumAttractiveness',5,'minimumMatchPercent',70,
    'coarseLatitude',-86,'coarseLongitude',-170,'preferredRadiusKilometers',1,
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
create function pg_temp.join(n integer, matching boolean default true, gender text default 'nonBinary') returns void
language sql as $$
    insert into storage.objects(bucket_id, name, owner, created_at)
        values ('profile-photos', pg_temp.photo(n), pg_temp.id(n), now() - interval '3 hours');
    insert into public.profiles(id, profile, backup)
        select pg_temp.id(n),
            p || jsonb_build_object('autoMatchingEnabled', matching, 'gender', gender,
                'interestedIn', jsonb_build_array(gender),
                'photoURLs', jsonb_build_array('https://x.test/storage/v1/object/authenticated/profile-photos/'
                    || pg_temp.id(n)::text || '/' || upper(pg_temp.id(500 + n)::text) || '.jpg')),
            jsonb_set(jsonb_set(jsonb_set(b, '{state,storedAutoMatching,photoID}', to_jsonb(upper(pg_temp.id(500 + n)::text))),
                '{draft,autoMatching,photoID}', to_jsonb(upper(pg_temp.id(500 + n)::text))),
                '{photos}', jsonb_build_array(jsonb_build_object('id', upper(pg_temp.id(500 + n)::text), 'order', 0)))
        from leave_fixture $$;

insert into auth.users(id, aud, role, last_sign_in_at)
    select pg_temp.id(n), 'authenticated', 'authenticated', now() from generate_series(1, 9) n;

-- ===== leave_matching ======================================================
select pg_temp.join(1, true, 'man');
select pg_temp.ok(pg_temp.in_pool(1), 'Fixture: 1 waits in the pool');
select pg_temp.as_user(1);
select pg_temp.ok(public.leave_matching(), 'Leaving without a match removes the profile');
select pg_temp.as_admin();
select pg_temp.ok(not pg_temp.has_profile(1), 'The profile row is gone');
select pg_temp.ok(not pg_temp.in_pool(1), 'So is the pool entry');
select pg_temp.ok(not exists(select 1 from matching_private.search_state where user_id = pg_temp.id(1)),
    'So is the search throttle state');
select pg_temp.ok(exists(select 1 from auth.users where id = pg_temp.id(1)), 'The account itself stays');
select pg_temp.as_user(1);
select pg_temp.ok(public.leave_matching(), 'Leaving again is harmless');
select pg_temp.as_admin();

-- 2 and 3 match; 2 leaving during the match removes nothing.
select pg_temp.join(2);
select pg_temp.join(3);
select pg_temp.ok(pg_temp.match_of(2) is not null and pg_temp.match_of(2) = pg_temp.match_of(3), 'Fixture: 2 and 3 are matched');
create temporary table chat as select pg_temp.match_of(2) as id;
grant select on chat to authenticated;
select pg_temp.set_matching(2, false);
select pg_temp.as_user(2);
select pg_temp.ok(not public.leave_matching(), 'Leaving during a match is refused');
select pg_temp.as_admin();
select pg_temp.ok(pg_temp.has_profile(2) and pg_temp.match_of(2) = (select id from chat),
    'The profile and the match stay');
select pg_temp.age(2, interval '3 days');
select pg_temp.ok(not pg_temp.due(2, 'leave'), 'The job leaves a matched profile alone');

-- ===== The daily job =====================================================
select pg_temp.join(4, false, 'woman');
select pg_temp.join(5, false, 'woman');
select pg_temp.join(6, true, 'woman');
select pg_temp.age(4, interval '2 days');
select pg_temp.age(5, interval '2 hours');
select pg_temp.age(6, interval '2 days');
select pg_temp.ok(pg_temp.due(4, 'leave'), 'Matching off, saved two days ago: due');
select pg_temp.ok(not pg_temp.due(5, 'leave'), 'Matching off, saved two hours ago: not yet');
select pg_temp.ok(not pg_temp.due(6, 'leave'), 'Matching on: never');
select pg_temp.ok(not exists(select 1 from matching_private.retention_due where action = 'photos'),
    'The 30-day photo rule is gone');
create temporary table removed4 as select public.retention_apply(pg_temp.id(4), 'leave') as names;
select pg_temp.ok(not pg_temp.has_profile(4), 'The job removes the profile');
select pg_temp.ok((select names from removed4) = array[pg_temp.photo(4)], 'And names its photo for deletion');
select pg_temp.ok(public.retention_apply(pg_temp.id(5), 'leave') = array[]::text[] and pg_temp.has_profile(5),
    'Apply refuses a cleanup that is not due');
select pg_temp.ok(public.retention_apply(pg_temp.id(6), 'leave') = array[]::text[] and pg_temp.has_profile(6),
    'Apply never removes a matching profile');
update storage.objects set created_at = now() - interval '2 days' where name = pg_temp.photo(4);
select pg_temp.ok(pg_temp.due(4, 'orphans'), 'A photo left behind by a failed delete is an orphan the next day');

-- ===== Breaking the match: 2 had matching off ============================
select pg_temp.as_user(3);
select public.break_match((select id from chat));
select pg_temp.as_admin();
select pg_temp.ok(pg_temp.due(2, 'leave'), 'Once the match ended, the job removes a profile with matching off');
select pg_temp.ok(not pg_temp.in_pool(2), 'Matching off: not back in the pool');
select pg_temp.ok(pg_temp.in_pool(3), 'Matching on: back in the pool');

-- ===== delete_match ======================================================
insert into public.match_key_bundles(match_id, user_id, device_id, public_bundle) values
    ((select id from chat), pg_temp.id(2), pg_temp.id(102), '{"protocol":"hpke-auth-x25519-v1","key":"AAAA"}'),
    ((select id from chat), pg_temp.id(3), pg_temp.id(103), '{"protocol":"hpke-auth-x25519-v1","key":"BBBB"}');
insert into public.encrypted_messages(match_id, sender_id, client_message_id, sender_device_id, recipient_device_id,
        ciphertext, protocol_version)
    values ((select id from chat), pg_temp.id(2), gen_random_uuid(), pg_temp.id(102), pg_temp.id(103),
        'envelope', 'hpke-auth-x25519-v1');
insert into public.match_cards(match_id, user_id, card) values ((select id from chat), pg_temp.id(2), 'card-of-2');

select pg_temp.as_user(2);
select pg_temp.ok(jsonb_array_length(public.my_matches()) = 1, 'Fixture: the broken match is listed');
select public.delete_match((select id from chat));
select pg_temp.ok(jsonb_array_length(public.my_matches()) = 0, 'Deleted: no longer in my own list');
select public.delete_match((select id from chat));
select pg_temp.ok(true, 'Deleting twice is harmless');
select pg_temp.as_user(3);
select pg_temp.ok(jsonb_array_length(public.my_matches()) = 1, 'The other person still has it');
select pg_temp.ok(exists(select 1 from public.encrypted_messages where match_id = (select id from chat)),
    'And can still read the conversation');
select pg_temp.as_admin();
create function pg_temp.refused(n integer) returns boolean language plpgsql as $$ begin
    perform pg_temp.as_user(n);
    perform public.delete_match((select id from chat));
    return false;
exception when others then return true;
end; $$;
select pg_temp.ok(pg_temp.refused(4), 'An outsider cannot delete it');
select pg_temp.as_admin();
select pg_temp.ok(exists(select 1 from public.match_cards where match_id = (select id from chat)),
    'Nothing is removed while one side still has it');
select pg_temp.as_user(3);
select public.delete_match((select id from chat));
select pg_temp.as_admin();
select pg_temp.ok(not exists(select 1 from public.encrypted_messages where match_id = (select id from chat))
    and not exists(select 1 from public.match_key_bundles where match_id = (select id from chat))
    and not exists(select 1 from public.match_cards where match_id = (select id from chat)),
    'Both deleted it: the conversation goes');
select pg_temp.ok(exists(select 1 from public.matches where id = (select id from chat))
    and exists(select 1 from matching_private.match_identities where match_id = (select id from chat)),
    'The match row and identity hashes stay (never the same two again)');

-- An active match cannot be deleted.
select pg_temp.join(7, true, 'man');
select pg_temp.join(8, true, 'man');
select pg_temp.ok(pg_temp.match_of(7) is not null, 'Fixture: 7 and 8 are matched');
create temporary table active_chat as select pg_temp.match_of(7) as id;
grant select on active_chat to authenticated;
create function pg_temp.refuses_active() returns boolean language plpgsql as $$ begin
    perform pg_temp.as_user(7);
    perform public.delete_match((select id from active_chat));
    return false;
exception when others then return true;
end; $$;
select pg_temp.ok(pg_temp.refuses_active(), 'An active match cannot be deleted');

-- One side deletes, the other deletes their account: the conversation goes.
select pg_temp.as_user(8);
select public.break_match((select id from active_chat));
select pg_temp.as_admin();
insert into public.match_cards(match_id, user_id, card) values ((select id from active_chat), pg_temp.id(7), 'card-of-7');
select pg_temp.as_user(8);
select public.delete_match((select id from active_chat));
select pg_temp.as_admin();
select pg_temp.ok(exists(select 1 from public.match_cards where match_id = (select id from active_chat)), 'Fixture: 7 still has it');
delete from public.profiles where id = pg_temp.id(7);
delete from auth.users where id = pg_temp.id(7);
select pg_temp.ok(not exists(select 1 from public.match_cards where match_id = (select id from active_chat)),
    'Deleted on one side, account gone on the other: the conversation goes');

-- ===== Privileges ========================================================
select pg_temp.ok(has_function_privilege('authenticated', 'public.leave_matching()', 'execute')
    and has_function_privilege('authenticated', 'public.delete_match(uuid)', 'execute'), 'Signed-in users can call both');
select pg_temp.ok(not has_function_privilege('anon', 'public.leave_matching()', 'execute')
    and not has_function_privilege('anon', 'public.delete_match(uuid)', 'execute'), 'Anonymous cannot');
select pg_temp.ok(not has_function_privilege('authenticated', 'public.retention_apply(uuid, text)', 'execute'),
    'Only the service role runs retention');

select pg_temp.ok(not has_function_privilege('authenticated', 'public.retention_secret_matches(text)', 'execute')
    and has_function_privilege('service_role', 'public.retention_secret_matches(text)', 'execute'),
    'Only the service role checks the retention secret');
select pg_temp.ok(exists(select 1 from vault.secrets where name = 'retention_secret'), 'The retention secret exists in Vault');
select pg_temp.ok(public.retention_secret_matches((select decrypted_secret from vault.decrypted_secrets
        where name = 'retention_secret')), 'The right secret matches');
select pg_temp.ok(not public.retention_secret_matches('wrong') and not public.retention_secret_matches('')
    and not public.retention_secret_matches(null), 'A wrong or empty one does not');

select name, 'PASS' as result, count(*) over () as total_passed from leave_results order by name;
rollback;
