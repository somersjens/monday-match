-- Stop Swiping: at most one partner search per account per minute.
--
-- Runs after 202611180004_push_dispatch_schedule.sql (independent of it; it was
-- applied to the live project after that one, on 18 November 2026).
--
-- Every profile save ran a full partner search under the global matching
-- lock, so one account calling the API directly (bypassing the app) could
-- hold up matching for everyone. Now:
--   - a save that changes nothing returns at once, without taking the lock;
--   - the first change searches immediately, as before;
--   - a further change within the same minute updates the person's place in
--     the pool at once (switching matching off still takes effect straight
--     away) and leaves the search to a pg_cron job, which runs it once the
--     minute is over. A burst of saves therefore costs one search per minute.
-- retry_matching follows the same rule. Trusted callers (photo verification,
-- breaking a match, admin) still search immediately through try_match.
--
-- SQL tests can switch the limit off for their own transaction with
--     set local stop_swiping.matching_throttle = 'off';
-- which only works for a session opened as postgres, never through the API.
begin;

create table matching_private.search_state (
    user_id uuid primary key references auth.users(id) on delete cascade,
    searched_at timestamptz not null,
    -- A change arrived after searched_at that has not been searched for yet.
    pending boolean not null default false
);
create index search_state_pending on matching_private.search_state(searched_at) where pending;
alter table matching_private.search_state enable row level security;
revoke all on matching_private.search_state from public, anon, authenticated;

-- The baseline engine, with p_search: false refreshes the pool entry (or
-- removes it) without looking for a partner.
drop function matching_private.try_match(uuid, boolean);
create function matching_private.try_match(uid uuid, p_force boolean default true, p_search boolean default true)
returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare own public.profiles%rowtype; me matching_private.pool; existing matching_private.pool;
    mid uuid; past text[]; best_id uuid; best_mine integer; best_theirs integer; best_hashes text[];
begin
    -- Matching, breaking and moderation take this lock; chat does not.
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    select match_id into mid from matching_private.matched_users where user_id = uid;
    if mid is not null then return mid; end if;
    select * into own from public.profiles where id = uid;
    if found and not matching_private.is_blocked(uid) then
        me := matching_private.pool_entry(uid, own.profile, own.backup);
    end if;
    if me.user_id is null then
        delete from matching_private.pool where user_id = uid;
        return null;
    end if;
    select * into existing from matching_private.pool where user_id = uid;
    if found then
        -- Nothing that matters changed: every arrival since already compared
        -- itself against this entry, so a new search cannot find anyone.
        if not p_force and existing.inputs_hash = me.inputs_hash then return null; end if;
        me.joined_at := existing.joined_at;
        delete from matching_private.pool where user_id = uid;
    else
        me.joined_at := now();
    end if;
    insert into matching_private.pool select (me).*;
    if not p_search then return null; end if;

    -- Everyone this person (under any of their sign-ins) was ever matched with.
    select coalesce(array_agg(distinct h), array[]::text[]) into past
        from matching_private.match_identities mine
        join matching_private.match_identities other on other.match_id = mine.match_id and other.user_id <> mine.user_id
        cross join lateral unnest(other.identity_hashes) h
        where mine.identity_hashes && me.identity_hashes;

    -- Cheap column filters first (gender/age use the index), then the full
    -- requirements both ways, then both scores. Highest sum wins; the longest
    -- waiting candidate breaks ties.
    select c.user_id, s.mine, s.theirs, c.identity_hashes into best_id, best_mine, best_theirs, best_hashes
        from matching_private.pool c
        cross join lateral (select matching_private.compatibility_score(me.wanted, me.weights, c.answers) as mine,
                                   matching_private.compatibility_score(c.wanted, c.weights, me.answers) as theirs) s
        where c.user_id <> uid
            and c.gender = any(me.interested_in) and me.gender = any(c.interested_in)
            and c.birth_date > current_date - make_interval(years => me.max_age + 1)
            and c.birth_date <= current_date - make_interval(years => me.min_age)
            and abs(c.latitude - me.latitude) * 111.19 <= least(me.radius_km, c.radius_km)
            and not (c.identity_hashes && past)
            and matching_private.meets_requirements(me, c)
            and matching_private.meets_requirements(c, me)
            and (not me.requires_verified_photo or matching_private.has_verified_photo(c.user_id, c.photo_id))
            and (not c.requires_verified_photo or matching_private.has_verified_photo(uid, me.photo_id))
            and s.mine >= me.min_score and s.theirs >= c.min_score
            and not exists (select 1 from matching_private.matched_users mu where mu.user_id = c.user_id)
        order by s.mine + s.theirs desc, c.joined_at, c.user_id
        limit 1;
    if best_id is null then return null; end if;

    insert into public.matches(user_low, user_high, score_low, score_high)
        values (least(uid, best_id), greatest(uid, best_id),
                case when uid < best_id then best_mine else best_theirs end,
                case when uid < best_id then best_theirs else best_mine end)
        returning id into mid;
    insert into matching_private.matched_users(user_id, match_id) values (uid, mid), (best_id, mid);
    insert into matching_private.match_identities(match_id, user_id, identity_hashes)
        values (mid, uid, me.identity_hashes), (mid, best_id, best_hashes);
    delete from matching_private.pool where user_id in (uid, best_id);
    return mid;
end;
$$;

-- Searches now, or refreshes the pool entry and leaves the search to
-- run_pending_searches when this account already searched in the last minute.
create function matching_private.request_search(uid uuid, p_force boolean default true) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare claimed boolean;
begin
    if current_setting('stop_swiping.matching_throttle', true) = 'off' and session_user = 'postgres' then
        return matching_private.try_match(uid, p_force);
    end if;
    -- The row lock taken here also serialises concurrent saves of one account.
    insert into matching_private.search_state as s (user_id, searched_at) values (uid, now())
        on conflict (user_id) do update set searched_at = now(), pending = false
        where s.searched_at <= now() - interval '1 minute'
        returning true into claimed;
    if claimed then return matching_private.try_match(uid, p_force); end if;
    update matching_private.search_state set pending = true where user_id = uid;
    return matching_private.try_match(uid, p_force, false);
end;
$$;

-- pg_cron: the searches held back during the last minute.
create function matching_private.run_pending_searches() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare u uuid;
begin
    for u in select user_id from matching_private.search_state
        where pending and searched_at <= now() - interval '1 minute'
        order by searched_at limit 200
    loop
        update matching_private.search_state set searched_at = now(), pending = false where user_id = u;
        perform matching_private.try_match(u, true);
    end loop;
end;
$$;

create or replace function matching_private.profile_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    -- A save that changes nothing needs neither the matching lock nor a search.
    if tg_op = 'UPDATE' and new.profile is not distinct from old.profile
        and new.backup is not distinct from old.backup then
        return new;
    end if;
    perform matching_private.request_search(new.id, false);
    return new;
end;
$$;

create or replace function public.retry_matching() returns uuid
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    return matching_private.request_search(auth.uid());
end;
$$;

revoke all on function matching_private.try_match(uuid, boolean, boolean), matching_private.request_search(uuid, boolean),
    matching_private.run_pending_searches() from public, anon, authenticated;
grant execute on function matching_private.try_match(uuid, boolean, boolean) to service_role;

select cron.schedule('matching-pending-searches', '20 seconds', 'select matching_private.run_pending_searches()');

commit;
