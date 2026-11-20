-- Stop Swiping: the server keeps a profile only while it takes part in
-- automatic matching, and a match can be deleted from one's own list.
--
-- Runs after 202611200001_production_hardening.sql.
-- DEPLOYED 2026-11-20 (tests/matching_only_profiles.sql: 43 live checks pass;
-- retention-purge redeployed the same day).
-- Decided 20 November 2026: creating an account backs the profile up to the
-- person's own iCloud (or Android backup), never to this server. Only a
-- profile with automatic matching on is sent here, and switching it off
-- removes the profile and its photos again. What stays is what keeps two
-- people from being matched again (matches, match_identities) and the
-- match history both people share, until they delete it.
--
-- 1. leave_matching(): the app calls this when automatic matching goes off.
--    The profile row goes at once (the profile_deleted trigger takes the
--    person out of the pool), together with the search throttle state. The
--    app then removes its photos through Storage; whatever it could not
--    remove is an orphan for the daily job. During an active match nothing
--    is removed: the match goes on and the job removes the profile once it
--    has ended. The app normally cannot switch matching off during a match
--    (the conversation is the whole app), so this only covers a race.
-- 2. Daily job: a profile with automatic matching off and no active match
--    whose last save is over a day old is removed ('leave'). This replaces
--    the 30-day photo rule ('photos') of 202611190002, covers app versions
--    that still send profiles outside matching, failed leave_matching calls,
--    and someone whose match ended while matching was off.
-- 3. delete_match(match): removes an ended match from the caller's own
--    My matches. The match row and both identity hashes stay (never the same
--    two people again). The other person keeps the conversation until they
--    delete it too; once both have (or the other account is gone), messages,
--    keys, cards and read states go.
--
-- 4. The retention job's secret is created in Vault by the database itself;
--    retention-purge checks a request against it (retention_secret_matches)
--    instead of a copy in RETENTION_SECRET. Still by hand: "Verify JWT with
--    legacy secret" OFF for retention-purge (pg_net sends no JWT).
--
-- Partner photos are no longer needed on the server after a match: the app
-- keeps the photo it was shown with the match, on the phone and in the
-- person's own iCloud, so it stays available for reports.
begin;

-- ===== 1. Leaving automatic matching =====================================

create function public.leave_matching() returns boolean
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    -- The same lock as matching: no match can be made halfway through.
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    if exists (select 1 from matching_private.matched_users where user_id = uid) then
        return false;
    end if;
    delete from public.profiles where id = uid;
    delete from matching_private.search_state where user_id = uid;
    return true;
end;
$$;
revoke all on function public.leave_matching() from public, anon;
grant execute on function public.leave_matching() to authenticated;

-- ===== 2. Retention: no profile outside matching =========================

-- What retention-purge should do next, oldest first.
--   profile: no sign of the app for 12 months
--   leave:   automatic matching off, no active match, last save over a day ago
--   orphans: stored photos nothing names for a day (a replaced photo the
--            app could not remove, a failed earlier purge, a removed row)
create or replace view matching_private.retention_due with (security_barrier) as
    select p.id as user_id, 'profile'::text as action, p.updated_at as since
        from public.profiles p
        where p.updated_at < now() - interval '12 months'
            and matching_private.last_active(p.id) < now() - interval '12 months'
    union all
    select p.id, 'leave', p.updated_at
        from public.profiles p
        where p.updated_at < now() - interval '1 day'
            and coalesce((p.profile->>'autoMatchingEnabled')::boolean, false) = false
            and not exists (select 1 from matching_private.matched_users mu where mu.user_id = p.id)
    union all
    select split_part(o.name, '/', 1)::uuid, 'orphans', min(o.created_at)
        from storage.objects o
        where o.bucket_id = 'profile-photos'
            and o.name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/'
            and o.created_at < now() - interval '1 day'
            and o.name <> all(matching_private.referenced_photo_names(split_part(o.name, '/', 1)::uuid))
        group by 1;
revoke all on matching_private.retention_due from public, anon, authenticated;

create or replace function public.retention_apply(p_user_id uuid, p_action text) returns text[]
language plpgsql volatile security definer set search_path = '' as $$
begin
    if p_action not in ('profile', 'leave', 'orphans') then
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
    elsif p_action = 'leave' then
        perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
        -- Checked again under the lock: a match made since keeps the profile.
        delete from public.profiles p where p.id = p_user_id
            and coalesce((p.profile->>'autoMatchingEnabled')::boolean, false) = false
            and not exists (select 1 from matching_private.matched_users mu where mu.user_id = p_user_id);
        delete from matching_private.search_state s where s.user_id = p_user_id
            and not exists (select 1 from public.profiles p where p.id = p_user_id);
    end if;
    -- A photo uploaded within the last hour (or day, for orphans) may belong
    -- to a save still under way on the phone.
    return matching_private.unreferenced_photos(p_user_id,
        case when p_action = 'orphans' then interval '1 day' else interval '1 hour' end);
end;
$$;
revoke all on function public.retention_apply(uuid, text) from public, anon, authenticated;
grant execute on function public.retention_apply(uuid, text) to service_role;

-- The job's secret lives only in Vault, made here by the database itself, so
-- nobody ever sees or copies it. The retention-purge function asks this
-- (as the service role) instead of keeping a copy as RETENTION_SECRET.
create function public.retention_secret_matches(p_secret text) returns boolean
language sql stable security definer set search_path = '' as $$
    select coalesce(p_secret, '') <> '' and exists (select 1 from vault.decrypted_secrets
        where name = 'retention_secret' and decrypted_secret = p_secret);
$$;
revoke all on function public.retention_secret_matches(text) from public, anon, authenticated;
grant execute on function public.retention_secret_matches(text) to service_role;

-- Starts the daily job's calls to retention-purge (see 202611190002): the
-- cron job only calls the function once this secret exists.
select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'retention_secret',
        'Daily retention job -> retention-purge')
    where not exists (select 1 from vault.secrets where name = 'retention_secret');

-- ===== 3. Deleting a match from one's own list ===========================

create table matching_private.deleted_matches (
    match_id uuid not null references public.matches(id) on delete cascade,
    user_id uuid not null,
    deleted_at timestamptz not null default now(),
    primary key (match_id, user_id)
);
alter table matching_private.deleted_matches enable row level security;
revoke all on matching_private.deleted_matches from public, anon, authenticated;

-- The conversation itself, once nobody is left to read it.
create function matching_private.forget_conversation(p_match_id uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
    delete from public.encrypted_messages where match_id = p_match_id;
    delete from public.match_key_bundles where match_id = p_match_id;
    delete from public.match_read_states where match_id = p_match_id;
    delete from public.match_cards where match_id = p_match_id;
end;
$$;

-- Nobody is left to read a match when each side either deleted it or no
-- longer has an account.
create function matching_private.nobody_reads(p_match_id uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select not exists (
        select 1 from public.matches m
        cross join lateral (values (m.user_low), (m.user_high)) side(uid)
        where m.id = p_match_id
            and exists (select 1 from auth.users u where u.id = side.uid)
            and not exists (select 1 from matching_private.deleted_matches d
                where d.match_id = m.id and d.user_id = side.uid));
$$;

create function public.delete_match(p_match_id uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid := auth.uid(); m public.matches%rowtype;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    select * into m from public.matches where id = p_match_id and uid in (user_low, user_high);
    if not found then raise exception 'Match unavailable' using errcode = '42501'; end if;
    if m.ended_at is null then raise exception 'Break the match first' using errcode = '55000'; end if;
    insert into matching_private.deleted_matches(match_id, user_id) values (m.id, uid) on conflict do nothing;
    if matching_private.nobody_reads(m.id) then perform matching_private.forget_conversation(m.id); end if;
end;
$$;
revoke all on function public.delete_match(uuid) from public, anon;
grant execute on function public.delete_match(uuid) to authenticated;

-- My matches leaves out the ones this person deleted.
create or replace function public.my_matches() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    return coalesce((select jsonb_agg(matching_private.match_summary(m, uid) order by m.matched_at desc)
        from public.matches m where (m.user_low = uid or m.user_high = uid)
            and not exists (select 1 from matching_private.deleted_matches d
                where d.match_id = m.id and d.user_id = uid)), '[]'::jsonb);
end;
$$;

-- A conversation nobody is left to read is removed: now also when the
-- other side deleted the match before this account went.
create or replace function matching_private.account_deleted() returns trigger
language plpgsql security definer set search_path = '' as $$
declare mid uuid;
begin
    for mid in select m.id from public.matches m where old.id in (m.user_low, m.user_high) loop
        if matching_private.nobody_reads(mid) then perform matching_private.forget_conversation(mid); end if;
    end loop;
    delete from matching_private.deleted_matches where user_id = old.id;
    return old;
end;
$$;

revoke all on function matching_private.forget_conversation(uuid), matching_private.nobody_reads(uuid)
    from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;
