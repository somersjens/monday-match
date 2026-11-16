-- Stop Swiping: push notifications for the three events that happen while
-- the app is closed: a new match, new messages and a match ending.
--
-- Runs after 202611160001_baseline.sql. Everything else (reminders, nudges,
-- consent, onboarding) is planned on the phone as local notifications; see
-- docs/notifications.md.
--
-- Messages stay end-to-end encrypted: the server knows that a message exists
-- and who sent it, never what it says, so no push carries message text.
--
-- Batching happens here. A burst of messages in one conversation is
-- coalesced into one pending outbox row per recipient and match; reading the
-- conversation before it goes out cancels it; a match ending cancels
-- everything pending for that match.
begin;

create schema if not exists notification_private;
revoke all on schema notification_private from public, anon, authenticated;

-- ===== 1. Devices =========================================================

-- One row per phone. The token moves with whoever signed in last, so a phone
-- that changes accounts never receives the previous account's pushes.
create table public.push_devices (
    device_id uuid primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    token text not null check (token ~ '^[0-9a-f]{64,200}$'),
    environment text not null check (environment in ('sandbox', 'production')),
    time_zone text not null default 'UTC' check (octet_length(time_zone) between 1 and 64),
    -- The app's language; the copy is written for each, not translated.
    language text not null default 'en' check (language in ('en', 'nl')),
    -- The app's "Matches & messages" switch.
    transactional boolean not null default true,
    -- The app's "Message previews" switch: the sender's name on the lock screen.
    previews boolean not null default true,
    -- The app's "Match ended alerts" switch. Off: a silent background push only.
    match_ended_alerts boolean not null default false,
    -- Local hours; both null means no quiet hours.
    quiet_start smallint check (quiet_start between 0 and 23),
    quiet_end smallint check (quiet_end between 0 and 23),
    updated_at timestamptz not null default now(),
    revoked_at timestamptz,
    check ((quiet_start is null) = (quiet_end is null))
);
create unique index push_devices_token on public.push_devices(token);
create index push_devices_user on public.push_devices(user_id) where revoked_at is null;
alter table public.push_devices enable row level security;
revoke all on public.push_devices from anon, authenticated;
comment on table public.push_devices is
    'APNs registrations. Clients write only through register_push_device / unregister_push_device.';

create function public.register_push_device(p_device_id uuid, p_token text, p_environment text,
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
end;
$$;

create function public.unregister_push_device(p_device_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    delete from public.push_devices where device_id = p_device_id and user_id = auth.uid();
end;
$$;

-- ===== 2. Outbox ==========================================================

create table notification_private.outbox (
    id bigint generated always as identity primary key,
    user_id uuid not null references auth.users(id) on delete cascade,
    kind text not null check (kind in ('match_new', 'first_match', 'message_new', 'match_ended')),
    match_id uuid not null references public.matches(id) on delete cascade,
    -- message_new only: the burst this push covers.
    message_count integer not null default 1,
    last_message_id bigint,
    created_at timestamptz not null default now(),
    not_before timestamptz not null default now(),
    claimed_at timestamptz,
    attempts smallint not null default 0,
    sent_at timestamptz,
    outcome text
);
-- At most one unclaimed row per recipient, match and kind: the coalescing point.
create unique index outbox_one_pending on notification_private.outbox(user_id, match_id, kind)
    where claimed_at is null and sent_at is null;
create index outbox_due on notification_private.outbox(not_before) where sent_at is null;
create index outbox_thread_sent on notification_private.outbox(user_id, match_id, sent_at desc)
    where kind = 'message_new' and sent_at is not null;

-- Debounce after the last message of a burst, the longest a burst may hold
-- its first message back, and the shortest time between two pushes for one
-- conversation. A newer push replaces the older one on the lock screen.
create function notification_private.message_timing(out debounce interval, out max_hold interval,
    out thread_gap interval)
language sql immutable as $$ select interval '15 seconds', interval '2 minutes', interval '3 minutes' $$;

-- ===== 3. Triggers ========================================================

create function notification_private.on_match_created() returns trigger
language plpgsql security definer set search_path = '' as $$
declare person uuid;
begin
    foreach person in array array[new.user_low, new.user_high] loop
        continue when person is null;
        insert into notification_private.outbox(user_id, kind, match_id)
        values (person,
            case when exists (select 1 from public.matches m where m.id <> new.id and person in (m.user_low, m.user_high))
                then 'match_new' else 'first_match' end,
            new.id)
        on conflict do nothing;
    end loop;
    return new;
end;
$$;
create trigger matches_notify_created after insert on public.matches
    for each row execute function notification_private.on_match_created();

create function notification_private.on_message_created() returns trigger
language plpgsql security definer set search_path = '' as $$
declare m public.matches%rowtype; recipient uuid; t record; last_sent timestamptz; gap_floor timestamptz;
begin
    select * into m from public.matches where id = new.match_id;
    if not found or m.ended_at is not null then return new; end if;
    recipient := case when m.user_low = new.sender_id then m.user_high else m.user_low end;
    if recipient is null then return new; end if;
    select * into t from notification_private.message_timing();
    select max(sent_at) into last_sent from notification_private.outbox
        where user_id = recipient and match_id = m.id and kind = 'message_new' and sent_at is not null;
    -- A rapid conversation gets one push per thread gap, never one per message.
    gap_floor := coalesce(last_sent + t.thread_gap, now());

    -- Each message restarts the debounce, but a burst never holds its first
    -- message back longer than max_hold.
    update notification_private.outbox set
        message_count = message_count + 1,
        last_message_id = greatest(last_message_id, new.id),
        not_before = greatest(least(now() + t.debounce, greatest(created_at + t.max_hold, now())), gap_floor)
    where user_id = recipient and match_id = m.id and kind = 'message_new'
        and claimed_at is null and sent_at is null;
    if not found then
        insert into notification_private.outbox(user_id, kind, match_id, last_message_id, not_before)
        values (recipient, 'message_new', m.id, new.id, greatest(now() + t.debounce, gap_floor))
        on conflict do nothing;
    end if;
    return new;
end;
$$;
create trigger encrypted_messages_notify after insert on public.encrypted_messages
    for each row execute function notification_private.on_message_created();

-- Reading the conversation before the push goes out cancels it.
create function notification_private.on_chat_read() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    delete from notification_private.outbox
        where user_id = new.user_id and match_id = new.match_id and kind = 'message_new'
        and claimed_at is null and sent_at is null and last_message_id <= new.last_read_message_id;
    return new;
end;
$$;
create trigger match_read_states_notify after insert or update of last_read_message_id on public.match_read_states
    for each row execute function notification_private.on_chat_read();

-- A match ending stops everything pending for it and tells the other side,
-- never who ended it or why. The one who ended it hears nothing.
create function notification_private.on_match_ended() returns trigger
language plpgsql security definer set search_path = '' as $$
declare person uuid;
begin
    delete from notification_private.outbox where match_id = new.id and claimed_at is null and sent_at is null;
    foreach person in array array[new.user_low, new.user_high] loop
        continue when person is null or person is not distinct from new.ended_by;
        insert into notification_private.outbox(user_id, kind, match_id) values (person, 'match_ended', new.id)
        on conflict do nothing;
    end loop;
    return new;
end;
$$;
create trigger matches_notify_ended after update of ended_at on public.matches
    for each row when (old.ended_at is null and new.ended_at is not null)
    execute function notification_private.on_match_ended();

-- ===== 4. Dispatch (service role only) ====================================

-- Claims due rows and returns one entry per device to deliver to, with
-- everything the sender needs and nothing more. Rows with nothing left to
-- say (read meanwhile, no devices, switched off) are closed here.
create function public.push_claim_due(p_limit integer default 100) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare result jsonb := '[]'::jsonb; item notification_private.outbox%rowtype; unread integer;
    m public.matches%rowtype; partner uuid; partner_name text; entries jsonb;
begin
    -- A sender that crashed mid-flight: release its claims after 5 minutes.
    update notification_private.outbox set claimed_at = null
        where sent_at is null and claimed_at < now() - interval '5 minutes' and attempts < 5;

    for item in
        update notification_private.outbox o set claimed_at = now(), attempts = attempts + 1
        where o.id in (select id from notification_private.outbox
            where sent_at is null and claimed_at is null and not_before <= now()
            order by not_before limit greatest(1, least(p_limit, 500)) for update skip locked)
        returning o.*
    loop
        select * into m from public.matches where id = item.match_id;
        partner := case when m.user_low = item.user_id then m.user_high else m.user_low end;
        unread := 0;
        if item.kind = 'message_new' then
            select count(*) into unread from public.encrypted_messages e
                where e.match_id = m.id and e.sender_id = partner
                and e.id > coalesce((select last_read_message_id from public.match_read_states
                    where match_id = m.id and user_id = item.user_id), 0);
        end if;
        if (item.kind in ('match_new', 'first_match', 'message_new') and m.ended_at is not null)
            or (item.kind = 'message_new' and unread = 0) then
            update notification_private.outbox set sent_at = now(), outcome = 'skipped' where id = item.id;
            continue;
        end if;
        select coalesce(pr.profile->>'displayName', '') into partner_name from public.profiles pr where pr.id = partner;

        select coalesce(jsonb_agg(jsonb_build_object(
                'outbox_id', item.id,
                'kind', item.kind,
                'match_id', item.match_id,
                'count', greatest(unread, 1),
                'token', d.token,
                'environment', d.environment,
                'language', d.language,
                -- Names reach the lock screen only with previews on.
                'partner_name', case when d.previews then nullif(partner_name, '') end,
                'visible', case when item.kind = 'match_ended' then d.match_ended_alerts and d.transactional
                    else d.transactional end,
                'quiet', d.quiet_start is not null and (
                    case when d.quiet_start < d.quiet_end
                        then extract(hour from now() at time zone d.time_zone) >= d.quiet_start
                         and extract(hour from now() at time zone d.time_zone) < d.quiet_end
                        else extract(hour from now() at time zone d.time_zone) >= d.quiet_start
                          or extract(hour from now() at time zone d.time_zone) < d.quiet_end end))), '[]'::jsonb)
            into entries
            from public.push_devices d where d.user_id = item.user_id and d.revoked_at is null;

        if jsonb_array_length(entries) = 0 then
            update notification_private.outbox set sent_at = now(), outcome = 'no_device' where id = item.id;
            continue;
        end if;
        result := result || entries;
    end loop;
    return result;
end;
$$;

-- p_outcome: 'sent', 'invisible' (background only), or an error to retry.
create function public.push_complete(p_outbox_id bigint, p_outcome text, p_retry boolean default false) returns void
language plpgsql security definer set search_path = '' as $$
begin
    if p_retry then
        update notification_private.outbox set claimed_at = null, outcome = left(p_outcome, 200),
            not_before = now() + make_interval(secs => 30 * power(2, least(attempts, 5)))
            where id = p_outbox_id and sent_at is null and attempts < 5;
        if found then return; end if;
    end if;
    update notification_private.outbox set sent_at = now(), outcome = left(p_outcome, 200)
        where id = p_outbox_id and sent_at is null;
end;
$$;

-- APNs said the token is gone (app deleted, permission revoked).
create function public.push_revoke_token(p_token text) returns void
language sql security definer set search_path = '' as $$
    update public.push_devices set revoked_at = now() where token = lower(p_token) and revoked_at is null;
$$;

-- Old outbox rows are only history.
create function notification_private.prune_outbox() returns void
language sql security definer set search_path = '' as $$
    delete from notification_private.outbox where sent_at < now() - interval '14 days';
$$;

revoke all on function public.register_push_device(uuid, text, text, text, boolean, boolean, boolean, integer, integer, text) from public, anon;
revoke all on function public.unregister_push_device(uuid) from public, anon;
grant execute on function public.register_push_device(uuid, text, text, text, boolean, boolean, boolean, integer, integer, text) to authenticated;
grant execute on function public.unregister_push_device(uuid) to authenticated;
revoke all on function public.push_claim_due(integer) from public, anon, authenticated;
revoke all on function public.push_complete(bigint, text, boolean) from public, anon, authenticated;
revoke all on function public.push_revoke_token(text) from public, anon, authenticated;
grant execute on function public.push_claim_due(integer) to service_role;
grant execute on function public.push_complete(bigint, text, boolean) to service_role;
grant execute on function public.push_revoke_token(text) to service_role;
revoke all on all functions in schema notification_private from public, anon, authenticated;

commit;
