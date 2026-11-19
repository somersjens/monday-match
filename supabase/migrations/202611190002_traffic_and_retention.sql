-- Stop Swiping: fewer requests per poll, and no data kept for people who
-- stopped matching or stopped using the app.
--
-- Runs after 202611190001_abuse_limits.sql (independent of it).
--
-- 1. current_match(p_known_card): leaves out the partner's profile card when
--    the phone already has it for that match, instead of sending it every
--    10 seconds. Called without arguments it behaves as before.
-- 2. chat_poll(match, after): one request for what an open chat asked in
--    three (match ended?, key bundles, new messages), plus the read receipt.
--    The key bundles come as a fingerprint; the phone fetches them only when
--    it changes.
-- 3. Retention, run daily by pg_cron:
--    - auto matching on but no sign of the app for 6 months: out of the pool
--      (the app's next save puts the person back);
--    - auto matching off for 30 days: the photo goes;
--    - no sign of the app for 12 months: the whole profile, its photo and
--      its push devices go. The sign-in itself stays;
--    - stored photos that nothing names for a day go too.
--    Photos live in Storage, which refuses SQL deletes, so the
--    `retention-purge` edge function removes them.
--
-- 4. Live signals: an active match gets a private Realtime channel the
--    database broadcasts on ("a message arrived", "it was read", "it ended"),
--    so an open app needs no polling timer for it.
--
-- The app treats what it last sent as unconfirmed after 28 days and checks
-- again (SupabaseProfileSync.confirmationLifetime), so it never relies on a
-- photo or row this job may have removed. The app also saves a matching
-- profile again after 28 days, which keeps `profiles.updated_at` current
-- for anyone who keeps opening the app.
--
-- Still to do by hand (see docs/data-retention.md):
--   select vault.create_secret('<RETENTION_SECRET>', 'retention_secret');
-- the function secret RETENTION_SECRET, and "Verify JWT with legacy secret"
-- off for retention-purge. Until the Vault secret exists, the job only takes
-- dormant profiles out of the pool and calls no function.
begin;

-- ===== 1. current_match without the card the phone already has ==========

drop function public.current_match();
create function public.current_match(p_known_card uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid(); result jsonb; mid uuid;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    select matching_private.match_summary(m, uid), m.id into result, mid
        from matching_private.matched_users a join public.matches m on m.id = a.match_id
        where a.user_id = uid and m.ended_at is null;
    if result is not null and p_known_card is not distinct from mid then
        result := result - 'partner_card';
    end if;
    return result;
end;
$$;
revoke all on function public.current_match(uuid) from public, anon;
grant execute on function public.current_match(uuid) to authenticated;

-- ===== 2. One request per chat poll ======================================

-- Runs as the caller, so the participants-only read policies apply: someone
-- outside the match sees it as closed and gets no messages.
create function public.chat_poll(p_match_id uuid, p_after bigint default null) returns jsonb
language sql stable security invoker set search_path = '' as $$
    select jsonb_build_object(
        'closed', m.id is null or m.ended_at is not null,
        'keys', (select md5(coalesce(string_agg(k.user_id::text || k.device_id::text
                    || coalesce(k.revoked_at::text, '-') || md5(k.public_bundle::text), ','
                    order by k.user_id, k.device_id), ''))
                from public.match_key_bundles k where k.match_id = p_match_id),
        'partner_read_at', (select e.created_at from public.match_read_states r
                join public.encrypted_messages e on e.id = r.last_read_message_id
                where r.match_id = p_match_id and r.user_id <> (select auth.uid())),
        -- Like the table query it replaces: the newest page on first open,
        -- then everything after the cursor in order.
        'messages', coalesce((select jsonb_agg(to_jsonb(page) order by page.id)
                from (select e.* from public.encrypted_messages e
                    where e.match_id = p_match_id and (p_after is null or e.id > p_after)
                    order by case when p_after is null then -e.id else e.id end
                    limit 100) page), '[]'::jsonb))
    from (select 1) one
    left join public.matches m on m.id = p_match_id;
$$;
revoke all on function public.chat_poll(uuid, bigint) from public, anon;
grant execute on function public.chat_poll(uuid, bigint) to authenticated;

-- ===== 3. Retention ======================================================

-- The last sign of the app for an account: a profile save, a sign-in or a
-- session refresh (the app refreshes its token whenever it opens after an
-- hour away).
create function matching_private.last_active(uid uuid) returns timestamptz
language sql stable security definer set search_path = '' as $$
    select greatest(
        (select p.updated_at from public.profiles p where p.id = uid),
        (select u.last_sign_in_at from auth.users u where u.id = uid),
        (select max(s.updated_at)::timestamptz from auth.sessions s where s.user_id = uid));
$$;

-- The Storage names this account's row still uses: the backup's photos, the
-- matching photo and the profile's photo references. None without a row.
create function matching_private.referenced_photo_names(uid uuid) returns text[]
language sql stable security definer set search_path = '' as $$
    select coalesce(array_agg(distinct uid::text || '/' || lower(ids.x) || '.jpg')
                        filter (where ids.x is not null), array[]::text[])
    from public.profiles p
    cross join lateral (
        select jsonb_array_elements(coalesce(p.backup->'photos', '[]'::jsonb))->>'id'
        union all select p.backup #>> '{state,storedAutoMatching,photoID}'
        union all select substring(u from '([0-9A-Fa-f-]{36})\.jpg$')
            from jsonb_array_elements_text(coalesce(p.profile->'photoURLs', '[]'::jsonb)) u) ids(x)
    where p.id = uid;
$$;

-- This account's stored photos that nothing names and that are older than
-- p_age (a photo is uploaded a moment before the row that names it).
create function matching_private.unreferenced_photos(uid uuid, p_age interval) returns text[]
language sql stable security definer set search_path = '' as $$
    select coalesce(array_agg(o.name order by o.name), array[]::text[])
    from storage.objects o
    where o.bucket_id = 'profile-photos' and o.name like uid::text || '/%'
        and o.created_at < now() - p_age
        and o.name <> all(matching_private.referenced_photo_names(uid));
$$;

-- What retention-purge should do next, oldest first.
--   profile: no sign of the app for 12 months
--   photos:  matching off for 30 days, a photo still named, no active match
--   orphans: stored photos nothing names for a day (a replaced photo the
--            app could not remove, a failed earlier purge, a removed row)
create view matching_private.retention_due with (security_barrier) as
    select p.id as user_id, 'profile'::text as action, p.updated_at as since
        from public.profiles p
        where p.updated_at < now() - interval '12 months'
            and matching_private.last_active(p.id) < now() - interval '12 months'
    union all
    select p.id, 'photos', p.updated_at
        from public.profiles p
        where p.updated_at < now() - interval '30 days'
            and coalesce((p.profile->>'autoMatchingEnabled')::boolean, false) = false
            and cardinality(matching_private.referenced_photo_names(p.id)) > 0
            and not exists (select 1 from matching_private.matched_users mu where mu.user_id = p.id)
            and matching_private.last_active(p.id) >= now() - interval '12 months'
    union all
    select split_part(o.name, '/', 1)::uuid, 'orphans', min(o.created_at)
        from storage.objects o
        where o.bucket_id = 'profile-photos'
            and o.name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
            and o.created_at < now() - interval '1 day'
            and o.name <> all(matching_private.referenced_photo_names(split_part(o.name, '/', 1)::uuid))
        group by 1;
revoke all on matching_private.retention_due from public, anon, authenticated;

-- Dormant matchers leave the pool, so nobody gets matched with a person who
-- will never see it. Nothing else changes: the app's next save (at the
-- latest 28 days after its last one) puts them straight back.
create function matching_private.remove_dormant_from_pool() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare removed integer;
begin
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    delete from matching_private.pool c
        where matching_private.last_active(c.user_id) < now() - interval '6 months';
    get diagnostics removed = row_count;
    return removed;
end;
$$;

-- For retention-purge (service role only): the next accounts to clean up.
create function public.retention_claim(p_limit integer default 100) returns jsonb
language sql stable security definer set search_path = '' as $$
    select coalesce(jsonb_agg(jsonb_build_object('user_id', d.user_id, 'action', d.action)), '[]'::jsonb)
    from (select user_id, action from matching_private.retention_due
          order by since limit least(greatest(p_limit, 1), 500)) d;
$$;

-- For retention-purge: applies one cleanup to the database if it is still
-- due, and returns the Storage names the function should then remove (an
-- empty array: nothing). The row changes first, so no row ever names a
-- removed photo; if the Storage delete fails, the leftovers come back as
-- 'orphans' the next day.
create function public.retention_apply(p_user_id uuid, p_action text) returns text[]
language plpgsql volatile security definer set search_path = '' as $$
declare cleared jsonb;
begin
    if p_action not in ('profile', 'photos', 'orphans') then
        raise exception 'Unknown retention action %', p_action using errcode = '22023';
    end if;
    if not exists (select 1 from matching_private.retention_due d
                   where d.user_id = p_user_id and d.action = p_action) then
        return array[]::text[];
    end if;
    if p_action = 'profile' then
        -- profile_deleted takes the matching lock, ends a match and leaves the pool.
        delete from public.profiles where id = p_user_id;
        delete from public.push_devices where user_id = p_user_id;
    elsif p_action = 'photos' then
        -- A restored phone starts without a photo and goes through the
        -- matching setup again, instead of naming a photo that is gone.
        select jsonb_set(jsonb_set(coalesce(p.backup, '{}'::jsonb), '{photos}', '[]'::jsonb),
                   '{state,storedAutoMatching}',
                   (coalesce(p.backup #> '{state,storedAutoMatching}', '{}'::jsonb) - 'photoID')
                       || '{"hasCompletedSetup": false, "isEnabled": false}'::jsonb)
            into cleared from public.profiles p where p.id = p_user_id for update;
        if cleared #> '{draft,autoMatching}' is not null then
            cleared := jsonb_set(cleared, '{draft,autoMatching}',
                ((cleared #> '{draft,autoMatching}') - 'photoID')
                    || '{"hasCompletedSetup": false, "isEnabled": false}'::jsonb);
        end if;
        -- The profiles_updated_at trigger restarts the 30 days, which is
        -- harmless: nothing is named any more.
        update public.profiles
            set backup = cleared, profile = jsonb_set(profile, '{photoURLs}', '[]'::jsonb)
            where id = p_user_id;
        return matching_private.unreferenced_photos(p_user_id, interval '1 hour');
    end if;
    -- profile and orphans: a photo uploaded within the last day may belong
    -- to a save still under way on the phone.
    return matching_private.unreferenced_photos(p_user_id,
        case when p_action = 'profile' then interval '1 hour' else interval '1 day' end);
end;
$$;

revoke all on function matching_private.last_active(uuid), matching_private.remove_dormant_from_pool(),
    matching_private.referenced_photo_names(uuid), matching_private.unreferenced_photos(uuid, interval)
    from public, anon, authenticated;
revoke all on function public.retention_claim(integer), public.retention_apply(uuid, text)
    from public, anon, authenticated;
grant execute on function public.retention_claim(integer), public.retention_apply(uuid, text) to service_role;

-- ===== 4. Live signals for an active match ===============================
-- While the app is open on an active match it listens on the private
-- Realtime channel "match:<id>" instead of asking the server on a timer.
-- The database says only what kind of thing changed and who did it; never
-- content. The app then fetches what it needs (chat_poll, current_match).

create function matching_private.signal_match(p_match_id uuid, p_what text, p_by uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
    perform realtime.send(jsonb_build_object('what', p_what, 'by', p_by), 'changed',
                          'match:' || p_match_id::text, true);
exception when others then
    -- A signal is a courtesy: it must never stop a message or a match change.
    -- The app catches up whenever its channel (re)connects.
    null;
end;
$$;

create function matching_private.on_match_signal() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    case tg_table_name
        when 'encrypted_messages' then perform matching_private.signal_match(new.match_id, 'message', new.sender_id);
        when 'match_read_states' then perform matching_private.signal_match(new.match_id, 'read', new.user_id);
        when 'match_key_bundles' then perform matching_private.signal_match(new.match_id, 'keys', new.user_id);
        when 'match_cards' then perform matching_private.signal_match(new.match_id, 'card', new.user_id);
        when 'matches' then perform matching_private.signal_match(new.id, 'ended', new.ended_by);
    end case;
    return null;
end;
$$;
revoke all on function matching_private.signal_match(uuid, text, uuid), matching_private.on_match_signal()
    from public, anon, authenticated;

create trigger encrypted_messages_signal after insert on public.encrypted_messages
    for each row execute function matching_private.on_match_signal();
create trigger match_read_states_signal after insert or update of last_read_message_id on public.match_read_states
    for each row execute function matching_private.on_match_signal();
create trigger match_key_bundles_signal after insert or update on public.match_key_bundles
    for each row execute function matching_private.on_match_signal();
create trigger match_cards_signal after insert or update on public.match_cards
    for each row execute function matching_private.on_match_signal();
create trigger matches_signal_ended after update of ended_at on public.matches
    for each row when (old.ended_at is null and new.ended_at is not null)
    execute function matching_private.on_match_signal();

-- Only the two people in a match may listen on its channel, and nobody may
-- send on it: there is no insert policy, so only the database broadcasts.
create policy "Match participants receive live signals" on realtime.messages
    for select to authenticated
    using (realtime.messages.extension = 'broadcast'
        and exists (select 1 from public.matches m
            where m.id = (case when (select realtime.topic())
                    ~ '^match:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                then substring((select realtime.topic()) from 7)::uuid end)
                and (select auth.uid()) in (m.user_low, m.user_high)));

-- Daily, after purge-expired-data (03:17). The function is called only once
-- its secret is in Vault and there is something to remove.
select cron.schedule('retention', '29 3 * * *', $job$
    select matching_private.remove_dormant_from_pool();
    select net.http_post(
        url := 'https://yrnwzehdzlxwnhyabwja.supabase.co/functions/v1/retention-purge',
        headers := jsonb_build_object('Content-Type', 'application/json',
            'X-Retention-Secret', (select decrypted_secret from vault.decrypted_secrets
                where name = 'retention_secret')),
        body := '{}'::jsonb, timeout_milliseconds := 60000)
    where exists (select 1 from vault.decrypted_secrets where name = 'retention_secret')
        and exists (select 1 from matching_private.retention_due);
$job$);

notify pgrst, 'reload schema';
commit;
