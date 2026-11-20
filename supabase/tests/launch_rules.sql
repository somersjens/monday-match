-- Launch rules (202611200005): only proven photo scans, only paying accounts in
-- the pool, and reports pushed to administrators. Run as postgres in the
-- Supabase SQL Editor ("Run without RLS" is fine): everything rolls back, and
-- the last line reports how many checks passed. The access check stays ON here.
begin;
set local stop_swiping.matching_throttle = 'off';
create temporary table launch_results(name text primary key);
create function pg_temp.ok(passed boolean, label text) returns void
language plpgsql as $$ begin
    if passed is distinct from true then raise exception 'FAILED: %', label; end if;
    insert into launch_results values(label);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
    select ('1a0c0000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.photo(n integer) returns text language sql immutable as $$
    select pg_temp.id(n)::text || '/' || lower(pg_temp.id(500 + n)::text) || '.jpg' $$;
create function pg_temp.in_pool(n integer) returns boolean language sql as $$
    select exists(select 1 from matching_private.pool where user_id = pg_temp.id(n)) $$;
create function pg_temp.buy(n integer, env text, product text default 'lifetime_access',
    expires timestamptz default null) returns void language sql as $$
    insert into public.store_entitlements(user_id, store, product_id, original_transaction_id, purchased_at,
        environment, expires_at)
    values (pg_temp.id(n), 'app_store', product, 'fixture-' || n || '-' || product, now(), env, expires) $$;

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

-- ===== 1. Only proven photo scans ==========================================
select pg_temp.ok(not has_function_privilege('authenticated', 'public.record_device_photo_verification(uuid)', 'execute'),
    'The app can no longer report an unproven scan');
insert into public.profiles(id, profile, backup) select pg_temp.id(9), '{"displayName":"Scan"}',
    jsonb_build_object('state', jsonb_build_object(
        'storedAutoMatching', jsonb_build_object('photoID', pg_temp.id(509)),
        'profilePrivacyConsent', jsonb_build_object('version', '2026-11-15.v2')));
insert into storage.objects(bucket_id, name, owner) values ('profile-photos', pg_temp.photo(9), pg_temp.id(9));
select matching_private.record_photo_scan(pg_temp.id(9), pg_temp.id(509), false);
select pg_temp.ok(not matching_private.has_verified_photo(pg_temp.id(9), lower(pg_temp.id(509)::text)),
    'An unproven device record never counts');
select public.record_attested_photo_verification(pg_temp.id(9), pg_temp.id(509));
select pg_temp.ok(matching_private.has_verified_photo(pg_temp.id(9), lower(pg_temp.id(509)::text)),
    'A proven scan counts');

-- ===== 2. Only paying accounts in the pool =================================
select pg_temp.join(1);
select pg_temp.ok(not pg_temp.in_pool(1), 'A complete profile without a purchase stays out of the pool');
select pg_temp.buy(1, 'production');
select pg_temp.ok(pg_temp.in_pool(1), 'A purchase puts the waiting profile in the pool at once');
update public.store_entitlements set revoked_at = now() where user_id = pg_temp.id(1);
select pg_temp.ok(not pg_temp.in_pool(1), 'A refund takes it out at once');

select pg_temp.buy(2, 'sandbox');
select pg_temp.join(2, true, 'man');
select pg_temp.ok(pg_temp.in_pool(2), 'A TestFlight purchase counts during the beta');
update matching_private.settings set enabled = false where name = 'sandbox_purchases_count';
select pg_temp.ok(not matching_private.has_access(pg_temp.id(2)), 'Not once the beta switch is off');
select matching_private.remove_dormant_from_pool();
select pg_temp.ok(not pg_temp.in_pool(2), 'The daily sweep then takes it out');
update matching_private.settings set enabled = true where name = 'sandbox_purchases_count';

select pg_temp.buy(3, 'production', 'monthly_access', now() - interval '1 day');
select pg_temp.ok(not matching_private.has_access(pg_temp.id(3)), 'An expired monthly plan is no access');
select pg_temp.buy(4, 'production', 'monthly_access', now() + interval '20 days');
select pg_temp.ok(matching_private.has_access(pg_temp.id(4)), 'A running monthly plan is');
select pg_temp.ok(matching_private.has_access(pg_temp.id(5)) = false, 'No purchase, no access');

-- ===== 3. Reports reach the administrators =================================
insert into matching_private.admins(user_id) values (pg_temp.id(8));
insert into public.push_devices(device_id, user_id, token, environment)
    values (pg_temp.id(801), pg_temp.id(8), repeat('ab', 32), 'sandbox');
insert into public.matches(id, user_low, user_high, score_low, score_high) values (pg_temp.id(700), pg_temp.id(6), pg_temp.id(7), 80, 80);
insert into public.match_reports(match_id, reported_id, reason, details, counts_as_strike)
    values (pg_temp.id(700), pg_temp.id(7), 'underage', 'Secret explanation', true);
select pg_temp.ok(exists (select 1 from notification_private.outbox where user_id = pg_temp.id(8)
    and kind = 'moderation_report' and detail = 'underage'), 'A report queues a push for the administrator');
select pg_temp.ok(not exists (select 1 from notification_private.outbox where kind = 'moderation_report'
    and user_id <> pg_temp.id(8)), 'Only for administrators');
create temporary table claimed as select public.push_claim_due(500) as entries;
select pg_temp.ok((select exists (select 1 from jsonb_array_elements(entries) e
    where e->>'kind' = 'moderation_report' and e->>'detail' = 'underage' and (e->>'visible')::boolean) from claimed),
    'The push carries the reason, always visible');
select pg_temp.ok((select entries::text not like '%Secret explanation%' from claimed), 'Never the explanation');

do $$ begin
    raise exception 'TEST RESULT: % checks passed', (select count(*) from launch_results);
end; $$;
rollback;
