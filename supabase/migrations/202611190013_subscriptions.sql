-- Stop Swiping: the monthly plan and half-price lifetime access for its
-- subscribers, recorded per account like lifetime access (202611190011).
--
-- A subscription keeps one original transaction ID across every renewal, so
-- it stays one row; what changes is the end of its current period
-- (`expires_at`). The app sends each renewal it sees, and App Store Server
-- Notifications (the `store-entitlement` function, without a user) move it
-- forward even when no device of the account is opened, so another phone or
-- Android sees the plan as long as it is paid.
--
-- Old app versions and the deployed edge function keep working: the new
-- parameter has a default, and `my_store_entitlements()` only gains a column.
begin;

alter table public.store_entitlements drop constraint store_entitlements_product_id_check;
alter table public.store_entitlements add constraint store_entitlements_product_id_check
    check (product_id in ('lifetime_access', 'lifetime_access_early_adopter', 'lifetime_access_subscriber',
                          'monthly_access'));
alter table public.store_entitlements add column expires_at timestamptz;
-- Only the monthly plan runs out.
alter table public.store_entitlements add constraint store_entitlements_expiry
    check ((product_id = 'monthly_access') = (expires_at is not null));

-- Brings a recorded purchase up to date. Lifetime purchases only ever move
-- towards refunded; a subscription takes the state of its latest period, so
-- a renewal after a refunded month counts again. Returns 'updated' or
-- 'unknown' (no account recorded this purchase yet: nothing to change).
create function public.update_store_entitlement(p_store text, p_original_transaction_id text,
    p_expires_at timestamptz, p_revoked_at timestamptz)
returns text
language plpgsql security definer set search_path = '' as $$
declare existing public.store_entitlements%rowtype;
begin
    select * into existing from public.store_entitlements
        where store = p_store and original_transaction_id = p_original_transaction_id for update;
    if not found then return 'unknown'; end if;
    if existing.product_id = 'monthly_access' then
        if p_expires_at is not null and p_expires_at >= existing.expires_at then
            update public.store_entitlements
                set expires_at = p_expires_at, revoked_at = p_revoked_at, updated_at = now()
                where id = existing.id
                  and (expires_at is distinct from p_expires_at or revoked_at is distinct from p_revoked_at);
        end if;
    else
        update public.store_entitlements set revoked_at = coalesce(revoked_at, p_revoked_at), updated_at = now()
            where id = existing.id and (revoked_at is null and p_revoked_at is not null);
    end if;
    return 'updated';
end;
$$;

drop function public.record_store_entitlement(uuid, text, text, text, timestamptz, timestamptz, text);

-- Called by the edge function after it verified the store's signature.
-- Returns 'recorded', 'updated' or 'other_account'.
create function public.record_store_entitlement(p_user_id uuid, p_store text, p_product_id text,
    p_original_transaction_id text, p_purchased_at timestamptz, p_revoked_at timestamptz, p_environment text,
    p_expires_at timestamptz default null)
returns text
language plpgsql security definer set search_path = '' as $$
declare owner uuid;
begin
    select user_id into owner from public.store_entitlements
        where store = p_store and original_transaction_id = p_original_transaction_id for update;
    if not found then
        insert into public.store_entitlements(user_id, store, product_id, original_transaction_id,
            purchased_at, revoked_at, environment, expires_at)
        values (p_user_id, p_store, p_product_id, p_original_transaction_id, p_purchased_at, p_revoked_at,
            p_environment, p_expires_at);
        return 'recorded';
    end if;
    if owner <> p_user_id then return 'other_account'; end if;
    return public.update_store_entitlement(p_store, p_original_transaction_id, p_expires_at, p_revoked_at);
end;
$$;

drop function public.my_store_entitlements();

-- What this account owns, for any of its devices. A subscription counts
-- while `expires_at` is in the future and it isn't revoked.
create function public.my_store_entitlements()
returns table (store text, product_id text, purchased_at timestamptz, expires_at timestamptz, revoked boolean)
language sql stable security definer set search_path = '' as $$
    select e.store, e.product_id, e.purchased_at, e.expires_at, e.revoked_at is not null
    from public.store_entitlements e where e.user_id = auth.uid()
    order by e.purchased_at;
$$;

revoke all on function public.update_store_entitlement(text, text, timestamptz, timestamptz)
    from public, anon, authenticated;
grant execute on function public.update_store_entitlement(text, text, timestamptz, timestamptz) to service_role;
revoke all on function public.record_store_entitlement(uuid, text, text, text, timestamptz, timestamptz, text,
    timestamptz) from public, anon, authenticated;
grant execute on function public.record_store_entitlement(uuid, text, text, text, timestamptz, timestamptz, text,
    timestamptz) to service_role;
revoke all on function public.my_store_entitlements() from public, anon;
grant execute on function public.my_store_entitlements() to authenticated;

commit;
