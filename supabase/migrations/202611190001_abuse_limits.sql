-- Stop Swiping: limits against a signed-in account scripting the API.
--
-- Runs after 202611180005_matching_throttle.sql (independent of it).
--
-- The project URL and anon key ship inside the app, so anyone with an Apple
-- or Google account can call the API with their own token, bypassing the app.
-- RLS already keeps them inside their own data; these limits keep one account
-- from filling the project's quotas (database, Storage, egress, pushes) or
-- holding the matching lock, which on the Free plan would restrict the
-- project for everyone.
--
--   1. Storage: at most 12 photos per account, named the way the app names
--      them (<account>/<uuid>.jpg), 2 MB each. The app makes JPEGs of at most
--      1600 px, well under 1 MB, and holds one photo (the matching photo).
--   2. Push devices: at most 5 per account; the oldest registrations go.
--   3. Chat: an envelope is at most 32 kB (8,000 bytes of text sealed twice
--      is about 22 kB); 60 messages a minute and 5 MB a day per sender; at
--      most 10 chat devices per person per match.
--   4. Every write through the Data API counts against 120 per account per
--      minute (PostgREST pre-request function). Read-only requests (GET and
--      the STABLE polling functions, which PostgREST runs read-only) are not
--      counted. A request that fails anyway rolls its count back with it.
--   5. AWS Face Liveness is parked (docs/aws-photo-verification.md): the app
--      can no longer start an AWS check, so the deployed function cannot
--      create paid sessions.
--
-- Undo 4 alone, without a migration, if it ever blocks real use:
--     alter role authenticator reset pgrst.db_pre_request;
--     notify pgrst, 'reload config';
begin;

-- ===== 1. Storage ===========================================================
update storage.buckets set file_size_limit = 2097152 where id = 'profile-photos';

-- Storage evaluates this for every upload by the signed-in account.
create function public.can_upload_profile_photo(p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
    select (select auth.uid()) is not null
        and p_name ~ ('^' || (select auth.uid())::text
            || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$')
        and (select count(*) from storage.objects o
             where o.bucket_id = 'profile-photos' and o.name like (select auth.uid())::text || '/%') < 12;
$$;
revoke all on function public.can_upload_profile_photo(text) from public, anon;
grant execute on function public.can_upload_profile_photo(text) to authenticated;

drop policy "Upload own profile photos" on storage.objects;
create policy "Upload own profile photos" on storage.objects
    for insert to authenticated with check (
        bucket_id = 'profile-photos' and public.can_upload_profile_photo(name)
    );

-- ===== 2. Push devices ======================================================
create or replace function public.register_push_device(p_device_id uuid, p_token text, p_environment text,
    p_time_zone text, p_transactional boolean, p_previews boolean, p_match_ended_alerts boolean,
    p_quiet_start integer default null, p_quiet_end integer default null, p_language text default 'en') returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); zone text;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    zone := case when exists (select 1 from pg_catalog.pg_timezone_names where name = p_time_zone)
        then p_time_zone else 'UTC' end;
    -- The same token under another device ID or account belongs to this phone now.
    delete from public.push_devices where token = lower(p_token) and device_id <> p_device_id;
    insert into public.push_devices(device_id, user_id, token, environment, time_zone, language, transactional,
        previews, match_ended_alerts, quiet_start, quiet_end)
    values (p_device_id, uid, lower(p_token), p_environment, zone,
        case when p_language in ('en', 'nl') then p_language else 'en' end, coalesce(p_transactional, true),
        coalesce(p_previews, true), coalesce(p_match_ended_alerts, false), p_quiet_start, p_quiet_end)
    on conflict (device_id) do update set user_id = excluded.user_id, token = excluded.token,
        environment = excluded.environment, time_zone = excluded.time_zone, language = excluded.language,
        transactional = excluded.transactional, previews = excluded.previews,
        match_ended_alerts = excluded.match_ended_alerts, quiet_start = excluded.quiet_start,
        quiet_end = excluded.quiet_end, updated_at = now(), revoked_at = null;
    -- This phone and the four registered most recently; every push goes to
    -- all of an account's devices, so the list must stay short.
    delete from public.push_devices where user_id = uid and device_id in (
        select device_id from public.push_devices where user_id = uid
        order by device_id = p_device_id desc, updated_at desc offset 5);
end;
$$;

-- ===== 3. Chat ==============================================================
alter table public.encrypted_messages drop constraint if exists encrypted_messages_ciphertext_check;
-- Older rows keep the previous 128 kB bound; new ones get this one.
alter table public.encrypted_messages
    add constraint encrypted_messages_ciphertext_size check (octet_length(ciphertext) between 1 and 32768) not valid;
create index encrypted_messages_sender_recent on public.encrypted_messages(sender_id, created_at);

create or replace function public.send_encrypted_message(p_match_id uuid, p_client_message_id uuid,
    p_sender_device_id uuid, p_recipient_device_id uuid, p_ciphertext text,
    p_protocol_version text default 'hpke-auth-x25519-v1') returns bigint
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); result bigint; existing public.encrypted_messages%rowtype;
begin
    perform 1 from public.matches where id = p_match_id and ended_at is null
        and uid is not null and uid in (user_low, user_high) for share;
    if not found then raise exception 'Active match required' using errcode = '42501'; end if;
    if p_protocol_version is distinct from 'hpke-auth-x25519-v1' then raise exception 'Unsupported protocol'; end if;
    if octet_length(p_ciphertext) is null or octet_length(p_ciphertext) not between 1 and 32768 then
        raise exception 'Message too large'; end if;
    if not exists (select 1 from public.match_key_bundles where match_id = p_match_id
        and user_id = uid and device_id = p_sender_device_id and revoked_at is null)
        or not exists (select 1 from public.match_key_bundles where match_id = p_match_id
        and user_id <> uid and device_id = p_recipient_device_id and revoked_at is null) then
        raise exception 'Both device key bundles required'; end if;
    select * into existing from public.encrypted_messages where match_id = p_match_id
        and sender_id = uid and client_message_id = p_client_message_id;
    if not found then
        -- A retry of a message that already arrived is never refused.
        if (select count(*) from public.encrypted_messages
                where sender_id = uid and created_at > now() - interval '1 minute') >= 60
            or (select coalesce(sum(octet_length(ciphertext)), 0) from public.encrypted_messages
                where sender_id = uid and created_at > now() - interval '1 day')
                + octet_length(p_ciphertext) > 5242880 then
            raise exception 'Message limit reached' using errcode = 'PT429';
        end if;
        insert into public.encrypted_messages(match_id, sender_id, client_message_id, sender_device_id,
            recipient_device_id, ciphertext, protocol_version)
            values (p_match_id, uid, p_client_message_id, p_sender_device_id, p_recipient_device_id, p_ciphertext, p_protocol_version)
            on conflict (match_id, sender_id, client_message_id) do nothing returning id into result;
        if result is not null then return result; end if;
        select * into existing from public.encrypted_messages where match_id = p_match_id
            and sender_id = uid and client_message_id = p_client_message_id;
    end if;
    if existing.ciphertext is distinct from p_ciphertext or existing.sender_device_id is distinct from p_sender_device_id
        or existing.recipient_device_id is distinct from p_recipient_device_id
        or existing.protocol_version is distinct from p_protocol_version then
        raise exception 'Message identifier already used'; end if;
    return existing.id;
end;
$$;

create or replace function public.register_chat_device(p_match_id uuid, p_device_id uuid, p_public_bundle jsonb,
    p_replace_device boolean default false) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    perform 1 from public.matches where id = p_match_id and ended_at is null
        and uid is not null and uid in (user_low, user_high) for share;
    if not found then raise exception 'Active match required' using errcode = '42501'; end if;
    if p_public_bundle->>'protocol' is distinct from 'hpke-auth-x25519-v1'
        or octet_length(decode(p_public_bundle->>'key', 'base64')) is distinct from 32 then
        raise exception 'Invalid public key bundle'; end if;
    if exists (select 1 from public.match_key_bundles where match_id = p_match_id and user_id = uid
        and device_id = p_device_id and revoked_at is not null) then raise exception 'Device revoked'; end if;
    -- Switching phones is rare; every switch leaves a revoked row behind.
    if not exists (select 1 from public.match_key_bundles where match_id = p_match_id and user_id = uid
            and device_id = p_device_id)
        and (select count(*) from public.match_key_bundles where match_id = p_match_id and user_id = uid) >= 10 then
        raise exception 'Too many chat devices' using errcode = 'PT429'; end if;
    if exists (select 1 from public.match_key_bundles where match_id = p_match_id and user_id = uid
        and device_id <> p_device_id and revoked_at is null) then
        if not p_replace_device then raise exception 'Device replacement confirmation required'; end if;
        update public.match_key_bundles set revoked_at = now() where match_id = p_match_id and user_id = uid
            and device_id <> p_device_id and revoked_at is null;
    end if;
    -- Immutable per device: a changed key needs a new device ID and verification.
    insert into public.match_key_bundles(match_id, user_id, device_id, public_bundle)
        values (p_match_id, uid, p_device_id, p_public_bundle) on conflict do nothing;
    if not exists (select 1 from public.match_key_bundles where match_id = p_match_id and user_id = uid
        and device_id = p_device_id and public_bundle = p_public_bundle) then
        raise exception 'Device key already registered'; end if;
end;
$$;

-- ===== 4. Writes per account per minute =====================================
-- Unlogged: a counter that resets after a crash costs nothing.
create unlogged table matching_private.api_writes (
    user_id uuid primary key,
    window_start timestamptz not null,
    writes integer not null
);
alter table matching_private.api_writes enable row level security;
revoke all on matching_private.api_writes from public, anon, authenticated;

-- Not in an exposed schema, so it cannot be called as an RPC.
create schema if not exists api_guard;
revoke all on schema api_guard from public;
grant usage on schema api_guard to anon, authenticated, service_role;

-- PostgREST runs this at the start of every request, as the request's role.
-- PT429 becomes HTTP 429 Too Many Requests.
create function api_guard.check_request() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid; used integer;
begin
    -- GET, HEAD and STABLE functions run read-only: nothing to count, and
    -- nothing could be written.
    if current_setting('transaction_read_only') = 'on' then return; end if;
    uid := auth.uid();
    if uid is null then return; end if;  -- anon has no write access; service_role is trusted
    insert into matching_private.api_writes as w (user_id, window_start, writes)
        values (uid, date_trunc('minute', now()), 1)
        on conflict (user_id) do update set
            writes = case when w.window_start = excluded.window_start then w.writes + 1 else 1 end,
            window_start = excluded.window_start
        returning writes into used;
    if used > 120 then
        raise exception 'Too many requests. Try again in a minute.' using errcode = 'PT429';
    end if;
end;
$$;
revoke all on function api_guard.check_request() from public;
grant execute on function api_guard.check_request() to anon, authenticated, service_role;

alter role authenticator set pgrst.db_pre_request = 'api_guard.check_request';

select cron.schedule('api-writes-prune', '53 3 * * *',
    $job$delete from matching_private.api_writes where window_start < now() - interval '1 day'$job$);

-- ===== 5. AWS Face Liveness stays parked ====================================
-- Restoring AWS: grant this back to authenticated (docs/aws-photo-verification.md).
revoke execute on function public.begin_photo_verification(uuid, text) from authenticated;

notify pgrst, 'reload schema';
notify pgrst, 'reload config';
commit;
