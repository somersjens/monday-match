-- Production hardening found in the pre-launch review of 20 November 2026.
-- DEPLOYED 2026-11-20 (live checks: tests/android_readiness.sql 29, tests/subscriptions.sql 23).
--
-- 1. Sandbox purchases no longer count as account access.
--    App Store sandbox transactions are Apple-signed, so the store-entitlement
--    function accepts them, and every TestFlight build buys in the sandbox for
--    free. Until now my_store_entitlements returned them like real purchases,
--    so anyone who joined a TestFlight beta and "bought" lifetime there kept
--    free lifetime access on their account in the App Store version. The rows
--    stay (for support), they just aren't returned. A TestFlight tester still
--    has access on the phone itself through StoreKit.
--
-- 2. Profile names get an upper bound on the server too.
--    The name is shown to matches; a profile written straight to the API
--    could carry a name of up to the 128 kB profile limit. The app allows 30
--    characters, but Swift counts emoji sequences (👩‍👩‍👧) as one and
--    Postgres counts code points (up to ~10 per emoji), so the server allows
--    400: it never refuses a name the app accepts. NOT VALID keeps old rows readable; every
--    new insert/update is checked.
begin;

create or replace function public.my_store_entitlements()
returns table (store text, product_id text, purchased_at timestamptz, expires_at timestamptz, revoked boolean,
               auto_renews boolean)
language sql stable security definer set search_path = '' as $$
    select e.store, e.product_id, e.purchased_at, e.expires_at, e.revoked_at is not null, e.auto_renews
    from public.store_entitlements e
    where e.user_id = auth.uid() and e.environment = 'production'
    order by e.purchased_at;
$$;

revoke all on function public.my_store_entitlements() from public, anon;
grant execute on function public.my_store_entitlements() to authenticated;

alter table public.profiles
    add constraint profiles_display_name_length
    check (char_length(coalesce(profile->>'displayName', '')) <= 400) not valid;

commit;
