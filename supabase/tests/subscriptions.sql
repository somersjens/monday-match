-- The monthly plan and subscriber lifetime access (202611190013, 202611190014). Run as
-- postgres in the Supabase SQL Editor ("Run without RLS" is fine):
-- everything rolls back.
begin;
create temporary table sub_results(name text primary key);
grant select, insert on sub_results to authenticated, service_role;
create function pg_temp.ok(passed boolean, label text) returns void
language plpgsql as $$ begin
    if passed is distinct from true then raise exception 'FAILED: %', label; end if;
    insert into sub_results values(label);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
    select ('a7fe1000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
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
create function pg_temp.expiry(transaction_id text) returns timestamptz language sql as $$
    select expires_at from public.store_entitlements where original_transaction_id = transaction_id $$;
-- Read in its own query, so it sees what a function in the same statement just wrote.
create function pg_temp.renews(transaction_id text) returns boolean language sql as $$
    select auto_renews from public.store_entitlements where original_transaction_id = transaction_id $$;

insert into auth.users(id, aud, role) select pg_temp.id(n), 'authenticated', 'authenticated' from generate_series(1, 2) n;

-- ===== Monthly plan ==========================================================
select pg_temp.ok(public.record_store_entitlement(pg_temp.id(1), 'app_store', 'monthly_access', '3000000001',
    now() - interval '10 days', null, 'sandbox', now() + interval '20 days') = 'recorded',
    'A monthly plan is recorded with its period end');
select pg_temp.ok(pg_temp.error_of(format(
    'select public.record_store_entitlement(%L, %L, %L, %L, now(), null, %L)',
    pg_temp.id(1), 'app_store', 'monthly_access', '3000000002', 'sandbox')) like '23514 %',
    'A monthly plan needs a period end');
select pg_temp.ok(pg_temp.error_of(format(
    'select public.record_store_entitlement(%L, %L, %L, %L, now(), null, %L, now())',
    pg_temp.id(1), 'app_store', 'lifetime_access', '3000000003', 'sandbox')) like '23514 %',
    'Lifetime access never runs out');
select pg_temp.ok(public.record_store_entitlement(pg_temp.id(1), 'app_store', 'monthly_access', '3000000001',
    now() - interval '10 days', null, 'sandbox', now() + interval '50 days') = 'updated'
    and pg_temp.expiry('3000000001') > now() + interval '49 days', 'A renewal moves the period end forward');
select public.record_store_entitlement(pg_temp.id(1), 'app_store', 'monthly_access', '3000000001',
    now() - interval '10 days', null, 'sandbox', now() + interval '20 days');
select pg_temp.ok(pg_temp.expiry('3000000001') > now() + interval '49 days',
    'An older period sent late never moves it back');
select pg_temp.ok(public.record_store_entitlement(pg_temp.id(2), 'app_store', 'monthly_access', '3000000001',
    now(), null, 'sandbox', now() + interval '80 days') = 'other_account'
    and pg_temp.expiry('3000000001') < now() + interval '51 days', 'Another account can neither take nor extend it');

-- Refund of the current month, then a later renewal under the same ID.
select public.update_store_entitlement('app_store', '3000000001', now() + interval '50 days', now());
select pg_temp.ok((select revoked_at is not null from public.store_entitlements
    where original_transaction_id = '3000000001'), 'A refunded month ends the plan');
select public.update_store_entitlement('app_store', '3000000001', now() + interval '80 days', null);
select pg_temp.ok((select revoked_at is null and expires_at > now() + interval '79 days'
    from public.store_entitlements where original_transaction_id = '3000000001'),
    'Subscribing again later counts again');

-- ===== Server notifications ==================================================
select pg_temp.ok(public.update_store_entitlement('app_store', '3999999999', now() + interval '30 days', null)
    = 'unknown' and not exists (select 1 from public.store_entitlements where original_transaction_id = '3999999999'),
    'A notification for a purchase no account recorded changes nothing');
select pg_temp.ok(public.record_store_entitlement(pg_temp.id(1), 'app_store', 'lifetime_access_subscriber',
    '3000000004', now(), null, 'sandbox') = 'recorded', 'Subscriber lifetime access is recorded');
select public.update_store_entitlement('app_store', '3000000004', now() + interval '30 days', null);
select pg_temp.ok((select expires_at is null from public.store_entitlements where original_transaction_id = '3000000004'),
    'A lifetime purchase never gets a period end');
select public.update_store_entitlement('app_store', '3000000004', null, now());
select public.update_store_entitlement('app_store', '3000000004', null, null);
select pg_temp.ok((select revoked_at is not null from public.store_entitlements where original_transaction_id = '3000000004'),
    'A refunded lifetime purchase stays refunded');

-- ===== Renewal status (202611190014) =========================================
select pg_temp.ok((select auto_renews is null from public.store_entitlements where original_transaction_id = '3000000001'),
    'A plan starts with an unknown renewal status');
select pg_temp.ok(public.set_store_auto_renew(pg_temp.id(1), 'app_store', '3000000001', true) = 'updated'
    and pg_temp.renews('3000000001'),
    'The app records that the plan renews');
select pg_temp.ok(public.set_store_auto_renew(pg_temp.id(2), 'app_store', '3000000001', false) = 'other_account'
    and pg_temp.renews('3000000001'),
    'Another account cannot change it');
select pg_temp.ok(public.set_store_auto_renew(null, 'app_store', '3000000001', false) = 'updated'
    and not pg_temp.renews('3000000001'),
    'A store notification records the cancellation');
select pg_temp.ok(public.set_store_auto_renew(null, 'app_store', '3000000004', true) = 'ignored'
    and pg_temp.renews('3000000004') is null,
    'Lifetime access has no renewal status');
select pg_temp.ok(public.set_store_auto_renew(null, 'app_store', '3999999999', true) = 'unknown',
    'A status for a purchase no account recorded changes nothing');
select pg_temp.ok(pg_temp.error_of('update public.store_entitlements set auto_renews = true where original_transaction_id = ''3000000004''')
    like '23514 %', 'Only the monthly plan can renew');

-- ===== What the account sees =================================================
select pg_temp.as_user(1);
select pg_temp.ok((select count(*) = 2 and bool_or(product_id = 'monthly_access' and expires_at > now() and not revoked
    and auto_renews = false) from public.my_store_entitlements()), 'An account sees its plan, when it ends and if it renews');
select pg_temp.ok(pg_temp.error_of(format('select public.update_store_entitlement(%L, %L, now(), null)',
    'app_store', '3000000001')) like '42501 %', 'The app cannot extend a plan itself');
select pg_temp.as_user(2);
select pg_temp.ok(not exists (select 1 from public.my_store_entitlements()), 'Another account sees nothing');
select pg_temp.as_admin();

select pg_temp.ok(not has_function_privilege('authenticated',
        'public.update_store_entitlement(text,text,timestamptz,timestamptz)', 'execute')
    and not has_function_privilege('anon', 'public.update_store_entitlement(text,text,timestamptz,timestamptz)', 'execute')
    and not has_function_privilege('authenticated',
        'public.record_store_entitlement(uuid,text,text,text,timestamptz,timestamptz,text,timestamptz)', 'execute')
    and not has_function_privilege('authenticated', 'public.set_store_auto_renew(uuid,text,text,boolean)', 'execute')
    and not has_function_privilege('anon', 'public.set_store_auto_renew(uuid,text,text,boolean)', 'execute'),
    'Only the edge function writes');

select name, 'PASS' as result, count(*) over () as total_passed from sub_results order by name;
rollback;
