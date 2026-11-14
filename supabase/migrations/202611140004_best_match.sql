-- Highest mean of both directional scores among all currently eligible candidates.
begin;
create or replace function matching_private.reconcile(uid uuid) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare own public.profiles%rowtype; other record; mid uuid; lo uuid; hi uuid;
    own_score integer; other_score integer;
    best_id uuid; best_own_score integer; best_other_score integer; best_total integer := -1;
begin
    -- All pool, match, end-match and send operations take the same transaction lock.
    -- This deliberately favors correctness over throughput for the initial pool.
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    select match_id into mid from matching_private.active_members where user_id = uid;
    if mid is not null then return mid; end if;
    select * into own from public.profiles where id = uid;
    if not found or not matching_private.eligible(own.profile, own.backup) then
        delete from matching_private.pool where user_id = uid;
        return null;
    end if;
    insert into matching_private.pool(user_id) values(uid) on conflict do nothing;
    -- Evaluate every eligible candidate. Highest exact mean wins; queue order breaks ties.
    for other in select p.* from matching_private.pool pool
        join public.profiles p on p.id = pool.user_id
        where p.id <> uid and not exists (select 1 from matching_private.active_members am where am.user_id = p.id)
        and not exists (select 1 from public.matches m where m.user_low = least(uid,p.id) and m.user_high = greatest(uid,p.id))
        order by pool.joined_at, p.id loop
        if not matching_private.eligible(other.profile, other.backup) then continue; end if;
        if coalesce((own.profile->>'requiresVerifiedPartnerPhoto')::boolean, true)
            and not matching_private.verified_photo(other.id, other.backup) then continue; end if;
        if coalesce((other.profile->>'requiresVerifiedPartnerPhoto')::boolean, true)
            and not matching_private.verified_photo(uid, own.backup) then continue; end if;
        own_score := matching_private.directional_score(own.profile, other.profile);
        other_score := matching_private.directional_score(other.profile, own.profile);
        if own_score is null or other_score is null
            or own_score < (own.profile->>'minimumMatchPercent')::integer
            or other_score < (other.profile->>'minimumMatchPercent')::integer then continue; end if;
        if own_score + other_score > best_total then
            best_id := other.id; best_own_score := own_score; best_other_score := other_score;
            best_total := own_score + other_score;
        end if;
    end loop;
    if best_id is null then return null; end if;
    lo := least(uid,best_id); hi := greatest(uid,best_id);
    insert into public.matches(user_low,user_high,score_low,score_high,algorithm_version)
        values(lo,hi,case when uid=lo then best_own_score else best_other_score end,
            case when uid=hi then best_own_score else best_other_score end,'2026-11-14.v2') returning id into mid;
    insert into matching_private.active_members(user_id,match_id) values(uid,mid),(best_id,mid);
    delete from matching_private.pool where user_id in (uid,best_id);
    return mid;
end;
$$;
notify pgrst, 'reload schema';
commit;
