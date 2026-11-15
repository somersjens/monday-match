-- End-to-end walk through matching v3 (migration 010). Run as postgres in the
-- Supabase SQL Editor ("Run without RLS" is fine): everything rolls back.
-- Covers: admission to the pool, skipping unchanged saves, automatic matching,
-- E2EE message storage, breaking, readable history after a break, account
-- deletion, never matching the same people again (also via a recreated
-- account), and the report flow: warning → 7-day block → ban.
begin;
create temporary table v3_results(name text primary key);
grant select, insert on v3_results to authenticated;
create function pg_temp.ok(passed boolean, label text) returns void
language plpgsql as $$ begin
    if passed is distinct from true then raise exception 'FAILED: %', label; end if;
    insert into v3_results values(label);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
    select ('a7fb0000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.as_user(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', pg_temp.id(n)::text, true), set_config('role', 'authenticated', true) $$;
create function pg_temp.as_admin() returns void language sql as $$
    select set_config('role', 'postgres', true) $$;
create function pg_temp.match_of(n integer) returns uuid language sql as $$
    select match_id from matching_private.matched_users where user_id = pg_temp.id(n) $$;
create function pg_temp.waiting(n integer) returns boolean language sql as $$
    select exists(select 1 from matching_private.pool where user_id = pg_temp.id(n)) $$;
create function pg_temp.key(seed text) returns jsonb language sql as $$
    select jsonb_build_object('protocol','hpke-auth-x25519-v1','key',encode(sha256(convert_to(seed,'UTF8')),'base64')) $$;

create temporary table v3_fixture(p jsonb, b jsonb);
insert into v3_fixture
select jsonb_build_object(
    'displayName','V3 fixture','autoMatchingEnabled',true,'profileComplete',true,
    'dateOfBirth','1995-06-15T12:00:00Z','gender','nonBinary','interestedIn',jsonb_build_array('nonBinary'),
    'languages',jsonb_build_array('nl'),'heightCentimeters',175,
    'ownAttractiveness',7,'partnerMinimumAttractiveness',5,'minimumMatchPercent',70,
    'coarseLatitude',-89,'coarseLongitude',170,'preferredRadiusKilometers',1,
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
    '{"state":{"profilePrivacyConsent":{"version":"2026-11-14.v1"},"storedAutoMatching":{"privacyConsent":{"version":"2026-11-14.v1"}}}}'::jsonb;
create function pg_temp.join(n integer) returns void language sql as $$
    insert into public.profiles(id, profile, backup) select pg_temp.id(n), p, b from v3_fixture $$;
create function pg_temp.pause(n integer) returns void language sql as $$
    update public.profiles set profile = profile || '{"autoMatchingEnabled":false}' where id = pg_temp.id(n) $$;
-- Scores between two edited copies of the fixture, through the pool columns.
create function pg_temp.score(s jsonb, c jsonb) returns integer language sql as $$
    select matching_private.directional_score(
        matching_private.pool_entry(pg_temp.id(900), s, f.b), matching_private.pool_entry(pg_temp.id(901), c, f.b))
    from v3_fixture f $$;

-- ===== Scoring through the precomputed pool columns ======================
select pg_temp.ok((matching_private.pool_entry(pg_temp.id(900), p, b)).user_id is not null, 'Complete profile yields a pool entry') from v3_fixture;
select pg_temp.ok(matching_private.pool_entry(pg_temp.id(900), p, '{}') is null, 'Missing consent yields no pool entry') from v3_fixture;
select pg_temp.ok(array_length((matching_private.pool_entry(pg_temp.id(900), p, b)).answers, 1) = 50, 'All 50 answers precomputed') from v3_fixture;
select pg_temp.ok(pg_temp.score(p, p) = 100, 'Identical answers score 100') from v3_fixture;
select pg_temp.ok(pg_temp.score(p, p || '{"gender":"man"}') is null, 'Gender requirement') from v3_fixture;
select pg_temp.ok(pg_temp.score(p, p || '{"dateOfBirth":"1940-01-01"}') is null, 'Age requirement') from v3_fixture;
select pg_temp.ok(pg_temp.score(p || '{"preferredPartnerMaximumHeight":170}', p) is null, 'Height requirement') from v3_fixture;
select pg_temp.ok(pg_temp.score(p, p || '{"religion":"atheist"}') is null, 'Religion requirement') from v3_fixture;
select pg_temp.ok(pg_temp.score(p, p || '{"languages":["en"]}') is null, 'Shared language requirement') from v3_fixture;
select pg_temp.ok(pg_temp.score(p, p || '{"coarseLatitude":-85}') is null, 'Distance requirement') from v3_fixture;
select pg_temp.ok(pg_temp.score(p, p || '{"ownAttractiveness":4}') is null, 'Appearance requirement') from v3_fixture;
select pg_temp.ok(pg_temp.score(p, jsonb_set(p,'{relationshipPreferences,sexualArrangement}','["noSex"]')) is null, 'Arrangement requirement') from v3_fixture;
select pg_temp.ok(pg_temp.score(jsonb_set(p,'{lifestyle,openToPartnerWithChildren}','false'), jsonb_set(p,'{lifestyle,hasChildren}','true')) is null, 'Children requirement') from v3_fixture;
select pg_temp.ok(pg_temp.score(jsonb_set(p,'{lifestyle,futureChildren}','"yes"'), jsonb_set(p,'{lifestyle,futureChildren}','"no"')) is null, 'Future children requirement') from v3_fixture;
select pg_temp.ok(pg_temp.score(jsonb_set(p,'{lifestyle,substances,smoking,partnerMaximumLevel}','0'), jsonb_set(p,'{lifestyle,substances,smoking,ownLevel}','1')) is null, 'Substance limit') from v3_fixture;
select pg_temp.ok(pg_temp.score(p, jsonb_set(p,'{lifestyle,substances,smoking,ownLevel}','5')) = 100, 'Habits within the limit do not change the score') from v3_fixture;
do $$ declare p jsonb; c jsonb; q text; begin
    select f.p into p from v3_fixture f; c := p;
    foreach q in array matching_private.question_ids() loop
        if q = 'aloneTime' then c := jsonb_set(c, '{lifestyle,aloneTime,own}', '4');
        else c := jsonb_set(c, array['lifestyle','storedCompatibilityAnswers',q,'own'], '4'); end if;
    end loop;
    perform pg_temp.ok(pg_temp.score(p, c) = 75, 'One step off on every question scores 75');
end; $$;

-- ===== Admission, unchanged saves, automatic match =======================
insert into auth.users(id, aud, role) select pg_temp.id(n), 'authenticated', 'authenticated' from generate_series(1, 12) n;
select pg_temp.join(1);
select pg_temp.ok(pg_temp.waiting(1), 'First complete profile waits in the pool');
create temporary table v3_joined as select joined_at, inputs_hash from matching_private.pool where user_id = pg_temp.id(1);
update public.profiles set profile = profile where id = pg_temp.id(1);
update public.profiles set backup = backup || '{"unrelated":"ui state"}' where id = pg_temp.id(1);
select pg_temp.ok((select joined_at = (select joined_at from v3_joined) and inputs_hash = (select inputs_hash from v3_joined)
    from matching_private.pool where user_id = pg_temp.id(1)), 'Unchanged matching inputs keep the queue place and skip the search');
select pg_temp.join(2);
select pg_temp.ok(pg_temp.match_of(1) is not null and pg_temp.match_of(1) = pg_temp.match_of(2), 'Second arrival is matched automatically');
select pg_temp.ok(not pg_temp.waiting(1) and not pg_temp.waiting(2), 'Matched people leave the pool');
select pg_temp.ok((select count(*) = 2 from matching_private.match_identities where match_id = pg_temp.match_of(1)), 'Both sign-in identities stored with the match');
select pg_temp.ok(matching_private.try_match(pg_temp.id(1)) = pg_temp.match_of(1), 'Retry returns the same match');
create temporary table v3_match(name text primary key, id uuid);
insert into v3_match values ('first', pg_temp.match_of(1));
grant select on v3_match to authenticated;

-- ===== Conversation =======================================================
select pg_temp.as_user(1);
select pg_temp.ok((public.current_match()->>'id')::uuid = (select id from v3_match where name='first'), 'current_match returns the match');
select public.register_chat_device((select id from v3_match where name='first'), pg_temp.id(101), pg_temp.key('device-1'));
select pg_temp.as_user(2);
select public.register_chat_device((select id from v3_match where name='first'), pg_temp.id(102), pg_temp.key('device-2'));
select public.send_encrypted_message((select id from v3_match where name='first'), pg_temp.id(202), pg_temp.id(102), pg_temp.id(101), 'opaque-from-2');
select pg_temp.as_user(1);
select public.send_encrypted_message((select id from v3_match where name='first'), pg_temp.id(201), pg_temp.id(101), pg_temp.id(102), 'opaque-from-1');
select public.send_encrypted_message((select id from v3_match where name='first'), pg_temp.id(201), pg_temp.id(101), pg_temp.id(102), 'opaque-from-1');
select pg_temp.ok((select count(*) = 2 from public.encrypted_messages), 'Messages stored once each, retries deduplicated');
do $$ begin
    begin
        perform public.send_encrypted_message((select id from v3_match where name='first'), gen_random_uuid(), pg_temp.id(101), pg_temp.id(102), 'x', 'e2ee-v1');
        raise exception 'Legacy protocol accepted';
    exception when raise_exception then
        if SQLERRM <> 'Unsupported protocol' then raise; end if;
        perform pg_temp.ok(true, 'New messages must use the HPKE protocol');
    end;
end; $$;
select pg_temp.as_user(3);
select pg_temp.ok((select count(*) = 0 from public.encrypted_messages) and (select count(*) = 0 from public.matches)
    and public.my_matches() = '[]'::jsonb, 'Outsider sees no matches or ciphertext');
do $$ begin
    begin
        perform public.break_match((select id from v3_match where name='first'));
        raise exception 'Outsider broke a match';
    exception when insufficient_privilege then perform pg_temp.ok(true, 'Outsider cannot break a match');
    end;
    begin
        perform public.report_partner((select id from v3_match where name='first'), 'spam', '');
        raise exception 'Outsider reported';
    exception when insufficient_privilege then perform pg_temp.ok(true, 'Outsider cannot report');
    end;
    begin
        perform matching_private.try_match(pg_temp.id(3));
        raise exception 'Client reached the engine';
    exception when insufficient_privilege then perform pg_temp.ok(true, 'Engine is not callable by clients');
    end;
end; $$;

-- ===== Breaking keeps a readable, closed history ==========================
select pg_temp.as_user(2);
select public.break_match((select id from v3_match where name='first'));
select public.break_match((select id from v3_match where name='first'));
select pg_temp.as_user(1);
select pg_temp.ok((select end_reason = 'broken' and ended_by = pg_temp.id(2) from public.matches
    where id = (select id from v3_match where name='first')), 'Break is recorded once, with who broke it');
select pg_temp.ok(public.current_match() is null, 'No current match after the break');
select pg_temp.ok((select jsonb_array_length(public.my_matches()) = 1
    and public.my_matches()->0->>'end_reason' = 'broken'
    and (public.my_matches()->0->>'ended_by_me')::boolean = false
    and public.my_matches()->0->>'partner_id' = pg_temp.id(2)::text), 'Broken match stays in my_matches, marked inactive');
select pg_temp.ok((select count(*) = 2 from public.encrypted_messages where match_id = (select id from v3_match where name='first')),
    'Both sides of the conversation stay readable after the break');
select pg_temp.ok((select count(*) = 2 from public.match_key_bundles where match_id = (select id from v3_match where name='first')),
    'Key bundles stay available to decrypt the history');
do $$ begin
    begin
        perform public.send_encrypted_message((select id from v3_match where name='first'), gen_random_uuid(), pg_temp.id(101), pg_temp.id(102), 'late');
        raise exception 'Broken match accepted a message';
    exception when insufficient_privilege then perform pg_temp.ok(true, 'A broken match accepts no new messages');
    end;
end; $$;
select pg_temp.ok(public.matching_status()->>'state' = 'waiting', 'Both people search again after a break');
select pg_temp.ok(public.retry_matching() is null, 'The same two people never match again');
select pg_temp.as_admin();
select pg_temp.pause(1);
select pg_temp.pause(2);
select pg_temp.ok(not pg_temp.waiting(1) and not pg_temp.waiting(2), 'Turning matching off leaves the pool');
update public.profiles set profile = profile || '{"autoMatchingEnabled":true}' where id in (pg_temp.id(1), pg_temp.id(2));
select pg_temp.ok(pg_temp.match_of(1) is null and pg_temp.waiting(1) and pg_temp.waiting(2), 'Off/on keeps the pair excluded');
select pg_temp.pause(1); select pg_temp.pause(2);

-- ===== Account deletion and a recreated account ===========================
insert into auth.identities(provider_id, user_id, identity_data, provider)
    values ('apple-sub-3', pg_temp.id(3), '{"sub":"apple-sub-3"}', 'apple');
select pg_temp.join(3);
select pg_temp.join(4);
insert into v3_match values ('deleted', pg_temp.match_of(3));
select pg_temp.ok((select id from v3_match where name='deleted') = pg_temp.match_of(4), 'Third and fourth match');
select pg_temp.as_user(3);
select public.register_chat_device((select id from v3_match where name='deleted'), pg_temp.id(103), pg_temp.key('device-3'));
select pg_temp.as_user(4);
select public.register_chat_device((select id from v3_match where name='deleted'), pg_temp.id(104), pg_temp.key('device-4'));
select pg_temp.as_user(3);
select public.send_encrypted_message((select id from v3_match where name='deleted'), pg_temp.id(203), pg_temp.id(103), pg_temp.id(104), 'opaque-from-3');
select pg_temp.as_admin();
delete from auth.users where id = pg_temp.id(3);
select pg_temp.ok((select end_reason = 'profile_deleted' and user_low is not null and user_high is not null
    from public.matches where id = (select id from v3_match where name='deleted')), 'Deleting an account ends its match but keeps the pair');
select pg_temp.ok(pg_temp.waiting(4), 'The partner of a deleted account searches again');
select pg_temp.ok((select count(*) = 1 from public.encrypted_messages where match_id = (select id from v3_match where name='deleted')),
    'The survivor keeps the conversation of a deleted account');
select pg_temp.as_user(4);
select pg_temp.ok(public.my_matches()->0->>'end_reason' = 'profile_deleted', 'Survivor sees why the match ended');
select pg_temp.as_admin();
-- Same Apple ID, new account: still never matched with 4 again.
insert into auth.users(id, aud, role) values (pg_temp.id(13), 'authenticated', 'authenticated');
insert into auth.identities(provider_id, user_id, identity_data, provider)
    values ('apple-sub-3', pg_temp.id(13), '{"sub":"apple-sub-3"}', 'apple');
select pg_temp.join(13);
select pg_temp.ok(pg_temp.match_of(13) is null and pg_temp.waiting(13) and pg_temp.waiting(4),
    'A recreated account with the same sign-in never rematches a past partner');
delete from auth.users where id = pg_temp.id(4);
select pg_temp.ok((select count(*) = 0 from public.encrypted_messages where match_id = (select id from v3_match where name='deleted')),
    'A conversation with no remaining participant is removed');
select pg_temp.pause(13);

-- ===== Reports: warning, 7-day block, ban =================================
-- Person 5 is reported by 6, 7 and 8, one match each.
insert into auth.identities(provider_id, user_id, identity_data, provider)
    values ('google-sub-5', pg_temp.id(5), '{"sub":"google-sub-5"}', 'google');
select pg_temp.join(5);
select pg_temp.join(6);
insert into v3_match values ('report1', pg_temp.match_of(5));
select pg_temp.as_user(6);
select public.report_partner((select id from v3_match where name='report1'), 'harassment', 'first');
select public.report_partner((select id from v3_match where name='report1'), 'spam', 'second reason, same match');
select pg_temp.as_user(5);
select pg_temp.ok((public.matching_status()->'moderation'->>'strikes')::integer = 1, 'First report is a warning (1 strike)');
select pg_temp.ok(public.matching_status()->>'state' = 'matched', 'A warning leaves the match active');
select pg_temp.ok((public.matching_status()->'moderation'->>'strikes_seen')::integer = 0, 'The warning is unseen');
select public.acknowledge_moderation();
select pg_temp.ok((public.matching_status()->'moderation'->>'strikes_seen')::integer = 1, 'Acknowledging marks the warning seen');
select pg_temp.as_user(6);
select public.break_match((select id from v3_match where name='report1'));
select pg_temp.as_admin();
select pg_temp.pause(6);
select pg_temp.join(7);
insert into v3_match values ('report2', pg_temp.match_of(5));
select pg_temp.ok((select id from v3_match where name='report2') = pg_temp.match_of(7), 'A warned person can still match');
select pg_temp.as_user(7);
select public.report_partner((select id from v3_match where name='report2'), 'fakeProfile', '', true);
select pg_temp.as_user(5);
select pg_temp.ok(public.matching_status()->>'state' = 'suspended', 'Second report blocks the person');
select pg_temp.ok((public.matching_status()->'moderation'->>'suspended_until')::timestamptz between now() + interval '6 days 23 hours' and now() + interval '7 days 1 hour',
    'The block lasts 7 days');
select pg_temp.as_admin();
select pg_temp.ok((select end_reason = 'reported' from public.matches where id = (select id from v3_match where name='report2')), 'Report with break ends the match as reported');
select pg_temp.ok(not pg_temp.waiting(5), 'A blocked person is out of the pool');
update public.profiles set profile = profile || '{"displayName":"Still blocked"}' where id = pg_temp.id(5);
select pg_temp.ok(not pg_temp.waiting(5), 'Saving the profile does not lift a block');
select pg_temp.pause(7);
-- Eight days later.
update public.match_reports set created_at = created_at - interval '8 days' where reported_id = pg_temp.id(5);
update public.profiles set profile = profile || '{"displayName":"Back"}' where id = pg_temp.id(5);
select pg_temp.ok(pg_temp.waiting(5), 'After 7 days the next save returns the person to the pool');
select pg_temp.join(8);
insert into v3_match values ('report3', pg_temp.match_of(5));
select pg_temp.ok((select id from v3_match where name='report3') = pg_temp.match_of(8), 'Third match for the reported person');
select pg_temp.as_user(8);
select public.report_partner((select id from v3_match where name='report3'), 'offlineBehavior', '');
select pg_temp.as_user(5);
select pg_temp.ok(public.matching_status()->>'state' = 'banned', 'Third report bans the account');
select pg_temp.as_admin();
select pg_temp.ok((select end_reason = 'moderation' and ended_by is null from public.matches where id = (select id from v3_match where name='report3')),
    'A ban ends the current match even when the reporter kept it');
select pg_temp.ok(pg_temp.waiting(8), 'The reporter searches again');
select pg_temp.pause(8);
-- An admin dismisses the third report: the ban lifts.
select matching_private.dismiss_report((select id from public.match_reports where match_id = (select id from v3_match where name='report3')));
select pg_temp.ok(pg_temp.waiting(5), 'Dismissing a report lifts the ban');
update public.match_reports set dismissed_at = null where match_id = (select id from v3_match where name='report3');
select matching_private.try_match(pg_temp.id(5));
select pg_temp.ok(not pg_temp.waiting(5), 'Restoring the report bans again');
-- Ban evasion: delete and come back with the same Google account.
delete from auth.users where id = pg_temp.id(5);
insert into auth.users(id, aud, role) values (pg_temp.id(15), 'authenticated', 'authenticated');
insert into auth.identities(provider_id, user_id, identity_data, provider)
    values ('google-sub-5', pg_temp.id(15), '{"sub":"google-sub-5"}', 'google');
select pg_temp.join(15);
select pg_temp.ok(not pg_temp.waiting(15) and pg_temp.match_of(15) is null, 'A new account with a banned sign-in stays banned');
select pg_temp.as_user(15);
select pg_temp.ok(public.matching_status()->>'state' = 'banned', 'The new account sees it is banned');
select pg_temp.ok((select count(*) = 0 from public.match_reports), 'Nobody reads reports about themselves');
select pg_temp.as_admin();
select pg_temp.ok((select count(*) = 3 from public.match_reports where counts_as_strike), 'Only the first report per match counts');

-- ===== Privileges =========================================================
select pg_temp.ok(not has_function_privilege('anon', 'public.my_matches()', 'execute'), 'Anonymous cannot list matches');
select pg_temp.ok(not has_function_privilege('authenticated', 'matching_private.dismiss_report(uuid)', 'execute'), 'Clients cannot dismiss reports');
select pg_temp.ok(not exists (select 1 from pg_proc where pronamespace in ('public'::regnamespace, 'matching_private'::regnamespace)
    and (proname in ('publish_match_key_bundle', 'current_chat_match', 'report_match', 'reconcile', 'verified_photo')
        or (proname = 'end_match' and pronamespace = 'public'::regnamespace)))
    and not has_function_privilege('authenticated', 'matching_private.end_match(uuid,text,uuid)', 'execute'), 'Old entry points are gone');
select pg_temp.ok(not exists (select 1 from pg_tables where schemaname in ('public', 'matching_private') and not rowsecurity), 'Every table has RLS');

select name, 'PASS' as result, count(*) over () as total_passed from v3_results order by name;
rollback;
