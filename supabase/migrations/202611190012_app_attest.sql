-- Stop Swiping: photo scans proven to come from the real app on a real device.
--
-- Runs after 202611180002_device_photo_verification.sql.
--
-- The on-device photo scan is reported by the phone, and until now the
-- server simply took its word for it. With Apple App Attest the phone holds
-- a key in its Secure Enclave that Apple certified as belonging to this
-- genuine, unmodified app; every scan report is signed with it. The
-- `app-attest` edge function checks Apple's certificate and the signature
-- and then records the scan with attested = true. Android will do the same
-- with Play Integrity.
--
-- Nothing is enforced yet: older app versions and the simulator still use
-- record_device_photo_verification (attested = false). To require proof
-- once every supported app version attests (iOS and Android):
--     revoke execute on function public.record_device_photo_verification(uuid) from authenticated;
-- and, to have unproven scans redone:
--     delete from matching_private.photo_verifications where method = 'device' and not attested;
begin;

-- ===== 1. Keys and one-time challenges ===================================

create table matching_private.app_attest_keys (
    -- Base64 of SHA-256 of the public key, as DCAppAttestService names it.
    key_id text primary key check (octet_length(key_id) between 40 and 64),
    user_id uuid not null references auth.users(id) on delete cascade,
    -- DER SubjectPublicKeyInfo (P-256), base64.
    public_key text not null check (octet_length(public_key) between 80 and 200),
    sign_count bigint not null default 0,
    environment text not null check (environment in ('development', 'production')),
    created_at timestamptz not null default now(),
    last_used_at timestamptz
);
create index app_attest_keys_user on matching_private.app_attest_keys(user_id);

create table matching_private.app_attest_challenges (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    challenge bytea not null default extensions.gen_random_bytes(32),
    created_at timestamptz not null default now(),
    used_at timestamptz
);
create index app_attest_challenges_user on matching_private.app_attest_challenges(user_id, created_at);
-- Only the service-role functions below touch these.
alter table matching_private.app_attest_keys enable row level security;
alter table matching_private.app_attest_challenges enable row level security;
revoke all on matching_private.app_attest_keys, matching_private.app_attest_challenges from public, anon, authenticated;

alter table matching_private.photo_verifications add column attested boolean not null default false;

-- ===== 2. Service-role functions for the edge function ===================

-- A fresh challenge, at most 20 an hour per account.
create function public.app_attest_issue_challenge(p_user_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare row matching_private.app_attest_challenges%rowtype;
begin
    delete from matching_private.app_attest_challenges where created_at < now() - interval '1 hour';
    if (select count(*) from matching_private.app_attest_challenges where user_id = p_user_id) >= 20 then
        raise exception 'Too many attestation challenges' using errcode = '54000';
    end if;
    insert into matching_private.app_attest_challenges(user_id) values (p_user_id) returning * into row;
    return jsonb_build_object('id', row.id, 'challenge', encode(row.challenge, 'base64'));
end; $$;

-- Uses up a challenge: valid once, for five minutes, for its own account.
create function public.app_attest_take_challenge(p_user_id uuid, p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare value bytea;
begin
    update matching_private.app_attest_challenges set used_at = now()
        where id = p_id and user_id = p_user_id and used_at is null and created_at > now() - interval '5 minutes'
        returning challenge into value;
    return encode(value, 'base64');
end; $$;

-- A key Apple certified. A key belongs to the account that registered it;
-- the same phone keeps it across accounts only by registering again.
create function public.app_attest_register_key(p_user_id uuid, p_key_id text, p_public_key text,
    p_environment text) returns void
language plpgsql security definer set search_path = '' as $$
begin
    if (select count(*) from matching_private.app_attest_keys where user_id = p_user_id) >= 10 then
        delete from matching_private.app_attest_keys where key_id = (select key_id
            from matching_private.app_attest_keys where user_id = p_user_id order by created_at limit 1);
    end if;
    insert into matching_private.app_attest_keys(key_id, user_id, public_key, environment)
        values (p_key_id, p_user_id, p_public_key, p_environment)
        on conflict (key_id) do update set user_id = excluded.user_id, public_key = excluded.public_key,
            environment = excluded.environment, sign_count = 0, created_at = now(), last_used_at = null;
end; $$;

create function public.app_attest_key(p_user_id uuid, p_key_id text) returns jsonb
language sql stable security definer set search_path = '' as $$
    select jsonb_build_object('public_key', public_key, 'sign_count', sign_count, 'environment', environment)
    from matching_private.app_attest_keys where key_id = p_key_id and user_id = p_user_id;
$$;

-- Counters only move forward: a replayed assertion is refused.
create function public.app_attest_use_key(p_user_id uuid, p_key_id text, p_counter bigint) returns boolean
language plpgsql security definer set search_path = '' as $$
begin
    update matching_private.app_attest_keys set sign_count = p_counter, last_used_at = now()
        where key_id = p_key_id and user_id = p_user_id and sign_count < p_counter;
    return found;
end; $$;

-- ===== 3. Recording a scan ===============================================

-- The body of record_device_photo_verification, shared by both routes.
create function matching_private.record_photo_scan(uid uuid, p_photo_id uuid, p_attested boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
declare object storage.objects%rowtype;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    perform pg_catalog.pg_advisory_xact_lock(hashtextextended('photo-verification:' || uid::text, 0));
    -- The same daily bound as AWS checks: each record re-runs matching.
    if (select count(*) from matching_private.verification_attempts
        where user_id = uid and created_at > now() - interval '1 day') >= 5 then
        raise exception 'Daily verification limit reached'; end if;
    if not exists (select 1 from public.profiles where id = uid
        and lower(backup #>> '{state,storedAutoMatching,photoID}') = p_photo_id::text
        and backup #>> '{state,profilePrivacyConsent,version}' = '2026-11-15.v2') then
        raise exception 'Selected photo unavailable'; end if;
    select * into object from storage.objects
        where bucket_id = 'profile-photos' and name = uid::text || '/' || p_photo_id::text || '.jpg';
    if not found then raise exception 'Photo upload must finish first'; end if;

    insert into matching_private.verification_attempts(user_id, photo_id, object_id, object_updated_at,
            consent_version, status, completed_at)
        values (uid, p_photo_id, object.id, object.updated_at,
            case when p_attested then 'device.attested.v1' else 'device.v1' end, 'verified', now());
    insert into matching_private.photo_verifications(object_id, object_updated_at, method, attested)
        values (object.id, object.updated_at, 'device', p_attested) on conflict (object_id) do update
            set object_updated_at = excluded.object_updated_at, verified_at = now(), method = 'device',
                attested = excluded.attested;
    perform matching_private.try_match(uid);
    return true;
end; $$;

-- Unchanged for the app: the unproven route, until it is revoked.
create or replace function public.record_device_photo_verification(p_photo_id uuid) returns boolean
language sql security definer set search_path = '' as $$
    select matching_private.record_photo_scan(auth.uid(), p_photo_id, false);
$$;

-- Called by the app-attest edge function after it checked the assertion.
create function public.record_attested_photo_verification(p_user_id uuid, p_photo_id uuid) returns boolean
language sql security definer set search_path = '' as $$
    select matching_private.record_photo_scan(p_user_id, p_photo_id, true);
$$;

revoke all on function matching_private.record_photo_scan(uuid, uuid, boolean) from public, anon, authenticated;
revoke all on function public.record_device_photo_verification(uuid) from public, anon;
grant execute on function public.record_device_photo_verification(uuid) to authenticated;
revoke all on function public.app_attest_issue_challenge(uuid) from public, anon, authenticated;
revoke all on function public.app_attest_take_challenge(uuid, uuid) from public, anon, authenticated;
revoke all on function public.app_attest_register_key(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.app_attest_key(uuid, text) from public, anon, authenticated;
revoke all on function public.app_attest_use_key(uuid, text, bigint) from public, anon, authenticated;
revoke all on function public.record_attested_photo_verification(uuid, uuid) from public, anon, authenticated;
grant execute on function public.app_attest_issue_challenge(uuid) to service_role;
grant execute on function public.app_attest_take_challenge(uuid, uuid) to service_role;
grant execute on function public.app_attest_register_key(uuid, text, text, text) to service_role;
grant execute on function public.app_attest_key(uuid, text) to service_role;
grant execute on function public.app_attest_use_key(uuid, text, bigint) to service_role;
grant execute on function public.record_attested_photo_verification(uuid, uuid) to service_role;

commit;
