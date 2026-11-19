-- Store entitlements (202611190011) and App Attest (202611190012). Run as
-- postgres in the Supabase SQL Editor ("Run without RLS" is fine):
-- everything rolls back.
begin;
create temporary table ready_results(name text primary key);
grant select, insert on ready_results to authenticated, service_role;
create function pg_temp.ok(passed boolean, label text) returns void
language plpgsql as $$ begin
    if passed is distinct from true then raise exception 'FAILED: %', label; end if;
    insert into ready_results values(label);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
    select ('a7fe0000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.as_user(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', pg_temp.id(n)::text, true),
           set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.id(n), 'role', 'authenticated')::text, true),
           set_config('role', 'authenticated', true) $$;
create function pg_temp.as_admin() returns void language sql as $$
    select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '{}', true),
           set_config('role', 'postgres', true) $$;
create function pg_temp.error_of(statement text) returns text
language plpgsql as $$ begin
    execute statement;
    return null;
exception when others then return sqlstate || ' ' || sqlerrm;
end; $$;
grant execute on function pg_temp.error_of(text) to authenticated, service_role;

insert into auth.users(id, aud, role) select pg_temp.id(n), 'authenticated', 'authenticated' from generate_series(1, 2) n;

-- ===== Store entitlements ====================================================
select pg_temp.ok(public.record_store_entitlement(pg_temp.id(1), 'app_store', 'lifetime_access', '2000000123',
    now() - interval '1 day', null, 'sandbox') = 'recorded', 'A verified purchase is recorded');
select pg_temp.ok(public.record_store_entitlement(pg_temp.id(1), 'app_store', 'lifetime_access', '2000000123',
    now() - interval '1 day', null, 'sandbox') = 'updated', 'Sending it again changes nothing');
select pg_temp.ok(public.record_store_entitlement(pg_temp.id(2), 'app_store', 'lifetime_access', '2000000123',
    now() - interval '1 day', null, 'sandbox') = 'other_account', 'One purchase belongs to the first account');
select public.record_store_entitlement(pg_temp.id(1), 'app_store', 'lifetime_access', '2000000123',
    now() - interval '1 day', now(), 'sandbox');
select public.record_store_entitlement(pg_temp.id(1), 'app_store', 'lifetime_access', '2000000123',
    now() - interval '1 day', null, 'sandbox');
select pg_temp.ok((select revoked_at is not null from public.store_entitlements where original_transaction_id = '2000000123'),
    'A refund is kept, never undone');
select pg_temp.as_user(1);
select pg_temp.ok((select count(*) = 1 and bool_and(revoked) from public.my_store_entitlements()),
    'An account sees its own purchases');
select pg_temp.ok(pg_temp.error_of('select * from public.store_entitlements') like '42501 %',
    'Nobody reads the table directly');
select pg_temp.ok(pg_temp.error_of(format(
    'select public.record_store_entitlement(%L, %L, %L, %L, now(), null, %L)',
    pg_temp.id(1), 'app_store', 'lifetime_access', '999', 'production')) like '42501 %',
    'The app cannot record a purchase itself');
select pg_temp.as_user(2);
select pg_temp.ok(not exists (select 1 from public.my_store_entitlements()), 'Another account sees nothing');
select pg_temp.as_admin();

-- ===== App Attest ============================================================
create temporary table ready_challenge as select public.app_attest_issue_challenge(pg_temp.id(1)) as c;
select pg_temp.ok((select length(decode(c->>'challenge', 'base64')) = 32 from ready_challenge),
    'A challenge is 32 random bytes');
select pg_temp.ok(public.app_attest_take_challenge(pg_temp.id(2), (select (c->>'id')::uuid from ready_challenge)) is null,
    'A challenge is only valid for its own account');
select pg_temp.ok(public.app_attest_take_challenge(pg_temp.id(1), (select (c->>'id')::uuid from ready_challenge))
    = (select c->>'challenge' from ready_challenge), 'A challenge can be used');
select pg_temp.ok(public.app_attest_take_challenge(pg_temp.id(1), (select (c->>'id')::uuid from ready_challenge)) is null,
    'A challenge is used only once');
select public.app_attest_issue_challenge(pg_temp.id(2)) from generate_series(1, 20);
select pg_temp.ok(pg_temp.error_of(format('select public.app_attest_issue_challenge(%L)', pg_temp.id(2))) like '54000 %',
    'At most 20 challenges an hour');

select public.app_attest_register_key(pg_temp.id(1), repeat('k', 44), repeat('p', 120), 'development');
select pg_temp.ok((select (public.app_attest_key(pg_temp.id(1), repeat('k', 44))->>'sign_count')::integer = 0),
    'A registered key starts at counter 0');
select pg_temp.ok(public.app_attest_key(pg_temp.id(2), repeat('k', 44)) is null, 'A key belongs to its account');
select pg_temp.ok(public.app_attest_use_key(pg_temp.id(1), repeat('k', 44), 1), 'An assertion moves the counter');
select pg_temp.ok(not public.app_attest_use_key(pg_temp.id(1), repeat('k', 44), 1), 'A replayed assertion is refused');
-- now() is fixed for the transaction: make the first key visibly the oldest.
update matching_private.app_attest_keys set created_at = now() - interval '1 hour' where key_id = repeat('k', 44);
select public.app_attest_register_key(pg_temp.id(1), repeat('k', 43) || n::text, repeat('p', 120), 'production')
    from generate_series(0, 9) n;
select pg_temp.ok((select count(*) = 10 from matching_private.app_attest_keys where user_id = pg_temp.id(1))
    and not exists (select 1 from matching_private.app_attest_keys where key_id = repeat('k', 44)),
    'An account keeps at most ten keys; the oldest goes');

-- ===== Recording a scan ======================================================
insert into public.profiles(id, profile, backup) select pg_temp.id(n), '{"displayName":"Scan"}',
    jsonb_build_object('state', jsonb_build_object(
        'storedAutoMatching', jsonb_build_object('photoID', pg_temp.id(100 + n)),
        'profilePrivacyConsent', jsonb_build_object('version', '2026-11-15.v2'))) from generate_series(1, 2) n;
insert into storage.objects(bucket_id, name, owner) select 'profile-photos',
    pg_temp.id(n)::text || '/' || pg_temp.id(100 + n)::text || '.jpg', pg_temp.id(n) from generate_series(1, 2) n;
create function pg_temp.verification(n integer) returns matching_private.photo_verifications language sql as $$
    select v.* from matching_private.photo_verifications v join storage.objects o on o.id = v.object_id
    where o.name = pg_temp.id(n)::text || '/' || pg_temp.id(100 + n)::text || '.jpg' $$;

select pg_temp.as_user(1);
select pg_temp.ok(public.record_device_photo_verification(pg_temp.id(101)), 'The app still records a device scan');
select pg_temp.ok(pg_temp.error_of(format('select public.record_attested_photo_verification(%L, %L)',
    pg_temp.id(1), pg_temp.id(101))) like '42501 %', 'The app cannot claim an attested scan itself');
select pg_temp.ok(pg_temp.error_of(format('select matching_private.record_photo_scan(%L, %L, true)',
    pg_temp.id(1), pg_temp.id(101))) like '42501 %', 'Nor call the shared body');
select pg_temp.as_admin();
select pg_temp.ok((select method = 'device' and not attested from pg_temp.verification(1)), 'An unproven scan is not attested');
select pg_temp.ok(public.record_attested_photo_verification(pg_temp.id(2), pg_temp.id(102)), 'The edge function records a proven scan');
select pg_temp.ok((select method = 'device' and attested from pg_temp.verification(2)), 'A proven scan is attested');
select pg_temp.ok((select consent_version from matching_private.verification_attempts where user_id = pg_temp.id(2))
    = 'device.attested.v1', 'The attempt says which route it took');
select pg_temp.ok(pg_temp.error_of(format('select public.record_attested_photo_verification(%L, %L)',
    pg_temp.id(2), pg_temp.id(101))) like '% Selected photo unavailable', 'Only the account''s own matching photo');

-- ===== Access ================================================================
select pg_temp.ok(not has_function_privilege('authenticated', 'public.app_attest_issue_challenge(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.app_attest_take_challenge(uuid,uuid)', 'execute')
    and not has_function_privilege('authenticated', 'public.app_attest_register_key(uuid,text,text,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.app_attest_key(uuid,text)', 'execute')
    and not has_function_privilege('authenticated', 'public.app_attest_use_key(uuid,text,bigint)', 'execute')
    and not has_function_privilege('anon', 'public.app_attest_issue_challenge(uuid)', 'execute'),
    'Only the edge function handles attestation');
select pg_temp.ok((select bool_and(relrowsecurity) from pg_class where oid in ('public.store_entitlements'::regclass,
    'matching_private.app_attest_keys'::regclass, 'matching_private.app_attest_challenges'::regclass)),
    'The new tables have RLS');

select name, 'PASS' as result, count(*) over () as total_passed from ready_results order by name;
rollback;
