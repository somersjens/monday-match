-- Stop Swiping: lifetime access recorded per account, for every store.
--
-- Until now lifetime access lived only on the phone (StoreKit and a Keychain
-- record). Someone who moves to another phone, or later to Android, would
-- lose it. Here the server keeps the purchase per account, after checking
-- the store's own signature: the `store-entitlement` edge function verifies
-- Apple's signed transactions (and later Google Play purchases) and is the
-- only writer.
--
-- One store purchase belongs to one account: the first account that records
-- it. The app still decides access from StoreKit on iOS; this ledger is what
-- an Android install (or a new iPhone with another Apple ID) can rely on.
begin;

create table public.store_entitlements (
    id bigint generated always as identity primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    store text not null check (store in ('app_store', 'play')),
    product_id text not null check (product_id in ('lifetime_access', 'lifetime_access_early_adopter')),
    -- App Store originalTransactionId, or the Play purchase token's order ID.
    original_transaction_id text not null check (octet_length(original_transaction_id) between 1 and 200),
    purchased_at timestamptz not null,
    revoked_at timestamptz,
    environment text not null check (environment in ('sandbox', 'production')),
    recorded_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (store, original_transaction_id)
);
create index store_entitlements_user on public.store_entitlements(user_id);
alter table public.store_entitlements enable row level security;
revoke all on public.store_entitlements from anon, authenticated;
comment on table public.store_entitlements is
    'Verified store purchases per account. Written only by the store-entitlement edge function (service role).';

-- Called by the edge function after it verified the store's signature.
-- Returns 'recorded', 'updated' or 'other_account'.
create function public.record_store_entitlement(p_user_id uuid, p_store text, p_product_id text,
    p_original_transaction_id text, p_purchased_at timestamptz, p_revoked_at timestamptz, p_environment text)
returns text
language plpgsql security definer set search_path = '' as $$
declare existing public.store_entitlements%rowtype;
begin
    select * into existing from public.store_entitlements
        where store = p_store and original_transaction_id = p_original_transaction_id for update;
    if not found then
        insert into public.store_entitlements(user_id, store, product_id, original_transaction_id,
            purchased_at, revoked_at, environment)
        values (p_user_id, p_store, p_product_id, p_original_transaction_id, p_purchased_at, p_revoked_at,
            p_environment);
        return 'recorded';
    end if;
    if existing.user_id <> p_user_id then return 'other_account'; end if;
    -- A refund or revocation only ever moves forward.
    update public.store_entitlements set revoked_at = coalesce(revoked_at, p_revoked_at), updated_at = now()
        where id = existing.id and (revoked_at is null and p_revoked_at is not null);
    return 'updated';
end;
$$;

-- What this account owns, for any of its devices.
create function public.my_store_entitlements()
returns table (store text, product_id text, purchased_at timestamptz, revoked boolean)
language sql stable security definer set search_path = '' as $$
    select e.store, e.product_id, e.purchased_at, e.revoked_at is not null
    from public.store_entitlements e where e.user_id = auth.uid()
    order by e.purchased_at;
$$;

revoke all on function public.record_store_entitlement(uuid, text, text, text, timestamptz, timestamptz, text)
    from public, anon, authenticated;
grant execute on function public.record_store_entitlement(uuid, text, text, text, timestamptz, timestamptz, text)
    to service_role;
revoke all on function public.my_store_entitlements() from public, anon;
grant execute on function public.my_store_entitlements() to authenticated;

commit;
