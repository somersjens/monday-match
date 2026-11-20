-- Stop Swiping: has_access must answer false, never null.
-- DEPLOYED 2026-11-20, minutes after 202611200005_launch_rules.sql.
--
-- In 202611200005 the test switch (stop_swiping.access_check) is unset
-- outside the SQL tests, so its comparison gave null, and "null or false"
-- is null. pool_entry's "not has_access(uid)" was then null too, which an IF
-- treats as false: everyone was admitted, paid or not. tests/launch_rules.sql
-- caught it on its first live run, before any real account was affected.
begin;

create or replace function matching_private.has_access(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select coalesce(current_setting('stop_swiping.access_check', true) = 'off' and session_user = 'postgres', false)
        or exists (select 1 from public.store_entitlements e
            where e.user_id = uid and e.revoked_at is null
                and (e.expires_at is null or e.expires_at > now())
                and (e.environment = 'production' or (e.environment = 'sandbox'
                    and coalesce((select s.enabled from matching_private.settings s
                        where s.name = 'sandbox_purchases_count'), false))));
$$;
revoke all on function matching_private.has_access(uuid) from public, anon, authenticated;

commit;
