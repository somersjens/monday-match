-- Harden account-deletion cascades and explicit-null admission checks.
begin;
create or replace function matching_private.eligible(p jsonb, b jsonb) returns boolean
language plpgsql stable set search_path = '' as $$
declare q text; a jsonb; habit text; years integer;
begin
    if not coalesce((p->>'autoMatchingEnabled')::boolean, false)
        or not coalesce((p->>'profileComplete')::boolean, false)
        or b #>> '{state,profilePrivacyConsent,version}' is distinct from '2026-11-14.v1'
        or b #>> '{state,storedAutoMatching,privacyConsent,version}' is distinct from '2026-11-14.v1'
        or coalesce((b #>> '{state,isUnderageLocked}')::boolean, false)
        or nullif(trim(p->>'displayName'), '') is null then return false; end if;
    years := extract(year from age(current_date, ((p->>'dateOfBirth')::timestamptz at time zone 'UTC')::date));
    if years is null or years < 18 or years > 120
        or p->>'gender' is null or jsonb_array_length(p->'interestedIn') = 0
        or jsonb_array_length(p->'languages') = 0
        or (p->>'heightCentimeters')::integer not between 50 and 250
        or (p->>'ownAttractiveness')::integer not between 1 and 10
        or (p->>'partnerMinimumAttractiveness')::integer not between 1 and 10
        or (p->>'minimumMatchPercent')::integer not between 50 and 90
        or (p->>'coarseLatitude')::numeric not between -90 and 90
        or (p->>'coarseLongitude')::numeric not between -180 and 180
        or (p->>'preferredRadiusKilometers')::integer <= 0
        or (p->>'preferredPartnerMinimumAge')::integer < 18
        or (p->>'preferredPartnerMaximumAge')::integer < (p->>'preferredPartnerMinimumAge')::integer
        or not coalesce(p #>> '{lifestyle,hasChildren}' in ('true','false'), false)
        or not coalesce(p #>> '{lifestyle,openToPartnerWithChildren}' in ('true','false'), false)
        or not coalesce(p #>> '{lifestyle,futureChildren}' in ('yes','no','notSure'), false)
        then return false; end if;
    if not (p ?& array['gender','interestedIn','languages','heightCentimeters','ownAttractiveness',
        'partnerMinimumAttractiveness','minimumMatchPercent','coarseLatitude','coarseLongitude',
        'preferredRadiusKilometers','preferredPartnerMinimumAge','preferredPartnerMaximumAge',
        'religion','acceptedPartnerReligions'])
        or exists (select 1 from jsonb_each(p) e where e.key = any(array['gender','heightCentimeters',
            'ownAttractiveness','partnerMinimumAttractiveness','minimumMatchPercent','preferredRadiusKilometers','coarseLatitude','coarseLongitude',
            'preferredPartnerMinimumAge','preferredPartnerMaximumAge',
            'religion','acceptedPartnerReligions']) and e.value = 'null'::jsonb)
        then return false; end if;
    foreach q in array matching_private.question_ids() loop
        a := matching_private.answer(p,q);
        if not coalesce((a->>'own')::integer between 1 and 5
            and (a->>'partner')::integer between 1 and 5
            and (a->>'importance')::integer between 1 and 5, false) then return false; end if;
    end loop;
    foreach habit in array array['alcohol','smoking','drugs'] loop
        a := p #> array['lifestyle','substances',habit];
        if not coalesce((a->>'ownLevel')::integer between 0 and 5
            and (a->>'partnerMaximumLevel')::integer between 0 and 5, false) then return false; end if;
    end loop;
    return true;
exception when data_exception then return false;
end;
$$;

create or replace function matching_private.profile_deleted() returns trigger
language plpgsql security definer set search_path = '' as $$
declare m public.matches%rowtype; partner uuid;
begin
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    select matches.* into m from public.matches matches
        join matching_private.active_members a on a.match_id=matches.id where a.user_id=old.id;
    delete from matching_private.pool where user_id=old.id;
    if m.id is not null then
        select user_id into partner from matching_private.active_members where match_id=m.id and user_id<>old.id;
        -- auth.users may already be deleted while its cascading profile deletion runs.
        -- Clear every reference to that account before the FK actions complete.
        update public.matches set ended_at=now(),end_reason='profile_deleted',
            ended_by=case when exists(select 1 from auth.users where id=old.id) then old.id else null end,
            user_low=case when exists(select 1 from auth.users where id=m.user_low) then m.user_low else null end,
            user_high=case when exists(select 1 from auth.users where id=m.user_high) then m.user_high else null end
            where id=m.id;
        delete from matching_private.active_members where match_id=m.id;
        -- Do not select the profile being deleted again in this BEFORE trigger.
        if exists(select 1 from public.profiles p where p.id=partner and matching_private.eligible(p.profile,p.backup)) then
            insert into matching_private.pool(user_id) values(partner) on conflict do nothing;
        end if;
    end if;
    return old;
end;
$$;
-- Admin-only operational view. The private schema is not exposed through the Data API.
create view matching_private.overview with (security_invoker = true) as
select p.id as user_id, p.profile->>'displayName' as display_name,
    coalesce((p.profile->>'autoMatchingEnabled')::boolean,false) as auto_matching_enabled,
    case when a.match_id is not null then 'matched' when pool.user_id is not null then 'waiting'
        when coalesce((p.profile->>'autoMatchingEnabled')::boolean,false) then 'ineligible' else 'disabled' end as state,
    a.match_id, case when m.user_low=p.id then m.user_high else m.user_low end as partner_id,
    pool.joined_at as waiting_since,
    (select count(*) from public.matches history where p.id in (history.user_low,history.user_high)) as previous_and_current_matches,
    matching_private.verified_photo(p.id,p.backup) as photo_verified
from public.profiles p
left join matching_private.pool pool on pool.user_id=p.id
left join matching_private.active_members a on a.user_id=p.id
left join public.matches m on m.id=a.match_id;
revoke all on matching_private.overview from public, anon, authenticated;
commit;
