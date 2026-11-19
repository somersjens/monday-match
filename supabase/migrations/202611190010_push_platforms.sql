-- Stop Swiping: pushes ready for Android, and no names through Apple or Google.
--
-- Runs after 202611190001_abuse_limits.sql (its five-device limit is kept
-- here) and 202611190002_traffic_and_retention.sql.
--
-- 1. Devices get a platform. iOS tokens stay lowercase hex for APNs;
--    Android tokens are FCM registration tokens, which are case-sensitive
--    and are therefore stored exactly as received. FCM has no sandbox.
-- 2. The partner's name no longer leaves the server in a push. APNs and FCM
--    can read every payload, so a push only says that something happened
--    (kind, match, count). With previews on, the phone fills in the name
--    itself: on iOS the Notification Service Extension, on Android the app's
--    own handler for a data message. See docs/notifications.md §6.
--
-- Older app versions keep working: p_platform defaults to 'ios', and they
-- show the private copy ("New message") until they are updated.
begin;

-- ===== 1. Devices =========================================================

alter table public.push_devices add column platform text not null default 'ios'
    check (platform in ('ios', 'android'));
alter table public.push_devices drop constraint push_devices_token_check;
alter table public.push_devices drop constraint push_devices_environment_check;
alter table public.push_devices add constraint push_devices_token_format check (
    (platform = 'ios' and token ~ '^[0-9a-f]{64,200}$')
    -- Postgres regexes allow at most 255 repetitions, so the length is separate.
    or (platform = 'android' and token ~ '^[A-Za-z0-9_:-]+$' and length(token) between 32 and 4096));
alter table public.push_devices add constraint push_devices_environment_valid check (
    environment in ('sandbox', 'production') and (platform = 'ios' or environment = 'production'));
comment on table public.push_devices is
    'APNs (iOS) and FCM (Android) registrations. Clients write only through register_push_device / unregister_push_device.';

drop function public.register_push_device(uuid, text, text, text, boolean, boolean, boolean, integer, integer, text);

create function public.register_push_device(p_device_id uuid, p_token text, p_environment text,
    p_time_zone text, p_transactional boolean, p_previews boolean, p_match_ended_alerts boolean,
    p_quiet_start integer default null, p_quiet_end integer default null, p_language text default 'en',
    p_platform text default 'ios') returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); zone text; device_token text; platform_name text := coalesce(p_platform, 'ios');
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    if platform_name not in ('ios', 'android') then
        raise exception 'Unknown platform' using errcode = '22023';
    end if;
    -- APNs tokens are hex and compared case-insensitively; FCM tokens are not.
    device_token := case when platform_name = 'ios' then lower(p_token) else p_token end;
    zone := case when exists (select 1 from pg_catalog.pg_timezone_names where name = p_time_zone)
        then p_time_zone else 'UTC' end;
    -- The same token under another device ID or account belongs to this phone now.
    delete from public.push_devices where token = device_token and device_id <> p_device_id;
    insert into public.push_devices(device_id, user_id, platform, token, environment, time_zone, language,
        transactional, previews, match_ended_alerts, quiet_start, quiet_end)
    values (p_device_id, uid, platform_name, device_token,
        case when platform_name = 'android' then 'production' else p_environment end, zone,
        case when p_language in ('en', 'nl') then p_language else 'en' end, coalesce(p_transactional, true),
        coalesce(p_previews, true), coalesce(p_match_ended_alerts, false), p_quiet_start, p_quiet_end)
    on conflict (device_id) do update set user_id = excluded.user_id, platform = excluded.platform,
        token = excluded.token, environment = excluded.environment, time_zone = excluded.time_zone,
        language = excluded.language, transactional = excluded.transactional, previews = excluded.previews,
        match_ended_alerts = excluded.match_ended_alerts, quiet_start = excluded.quiet_start,
        quiet_end = excluded.quiet_end, updated_at = now(), revoked_at = null;
    -- This phone and the four registered most recently; every push goes to
    -- all of an account's devices, so the list must stay short.
    delete from public.push_devices where user_id = uid and device_id in (
        select device_id from public.push_devices where user_id = uid
        order by device_id = p_device_id desc, updated_at desc offset 5);
end;
$$;

-- APNs or FCM said the token is gone (app deleted, permission revoked).
create or replace function public.push_revoke_token(p_token text) returns void
language sql security definer set search_path = '' as $$
    update public.push_devices set revoked_at = now()
    where revoked_at is null
      and ((platform = 'ios' and token = lower(p_token)) or (platform = 'android' and token = p_token));
$$;

-- ===== 2. Dispatch without names ==========================================

-- Same claim logic as 202611160002, but each entry carries the device's
-- platform and its previews switch instead of the partner's name.
create or replace function public.push_claim_due(p_limit integer default 100) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare result jsonb := '[]'::jsonb; item notification_private.outbox%rowtype; unread integer;
    m public.matches%rowtype; partner uuid; entries jsonb;
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

        select coalesce(jsonb_agg(jsonb_build_object(
                'outbox_id', item.id,
                'kind', item.kind,
                'match_id', item.match_id,
                'count', greatest(unread, 1),
                'platform', d.platform,
                'token', d.token,
                'environment', d.environment,
                'language', d.language,
                -- The phone puts the name on the lock screen itself; the
                -- server only tells it whether the user wants that.
                'previews', d.previews,
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

revoke all on function public.register_push_device(uuid, text, text, text, boolean, boolean, boolean, integer, integer, text, text) from public, anon;
grant execute on function public.register_push_device(uuid, text, text, text, boolean, boolean, boolean, integer, integer, text, text) to authenticated;
revoke all on function public.push_claim_due(integer) from public, anon, authenticated;
revoke all on function public.push_revoke_token(text) from public, anon, authenticated;
grant execute on function public.push_claim_due(integer) to service_role;
grant execute on function public.push_revoke_token(text) to service_role;

commit;
