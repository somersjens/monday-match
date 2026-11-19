-- Stop Swiping: whether a monthly plan will renew, per account.
--
-- Someone who buys lifetime access while paying monthly must cancel the plan
-- themselves: no app or server can do it for them. The app keeps asking until
-- the plan no longer renews. On the device that subscribed, StoreKit says so;
-- every other device (another Apple ID, Android) needs the server to know.
-- The status comes from the store's signed renewal info: sent by the app
-- after each change, and by App Store Server Notifications (and later Google
-- Play) without the app.
begin;

alter table public.store_entitlements add column auto_renews boolean;
-- Only the monthly plan renews.
alter table public.store_entitlements add constraint store_entitlements_auto_renew
    check (product_id = 'monthly_access' or auto_renews is null);

-- Records the renewal status of a purchase an account already recorded.
-- p_user_id is the signed-in account (the app), or null (a store
-- notification). Returns 'updated', 'unknown', 'other_account' or 'ignored'.
create function public.set_store_auto_renew(p_user_id uuid, p_store text, p_original_transaction_id text,
    p_auto_renews boolean)
returns text
language plpgsql security definer set search_path = '' as $$
declare existing public.store_entitlements%rowtype;
begin
    if p_auto_renews is null then return 'ignored'; end if;
    select * into existing from public.store_entitlements
        where store = p_store and original_transaction_id = p_original_transaction_id for update;
    if not found then return 'unknown'; end if;
    if p_user_id is not null and existing.user_id <> p_user_id then return 'other_account'; end if;
    if existing.product_id <> 'monthly_access' then return 'ignored'; end if;
    update public.store_entitlements set auto_renews = p_auto_renews, updated_at = now()
        where id = existing.id and auto_renews is distinct from p_auto_renews;
    return 'updated';
end;
$$;

drop function public.my_store_entitlements();

-- What this account owns, for any of its devices. A subscription counts
-- while `expires_at` is in the future and it isn't revoked; `auto_renews`
-- says whether it will be charged again (null: not known yet).
create function public.my_store_entitlements()
returns table (store text, product_id text, purchased_at timestamptz, expires_at timestamptz, revoked boolean,
               auto_renews boolean)
language sql stable security definer set search_path = '' as $$
    select e.store, e.product_id, e.purchased_at, e.expires_at, e.revoked_at is not null, e.auto_renews
    from public.store_entitlements e where e.user_id = auth.uid()
    order by e.purchased_at;
$$;

revoke all on function public.set_store_auto_renew(uuid, text, text, boolean) from public, anon, authenticated;
grant execute on function public.set_store_auto_renew(uuid, text, text, boolean) to service_role;
revoke all on function public.my_store_entitlements() from public, anon;
grant execute on function public.my_store_entitlements() to authenticated;

commit;
