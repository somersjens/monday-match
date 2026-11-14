-- Matching is server-owned. Clients can never choose their partner or scores.
begin;
create schema if not exists matching_private;
revoke all on schema matching_private from public, anon, authenticated;
grant usage on schema matching_private to service_role;

create table public.matches (
    id uuid primary key default gen_random_uuid(),
    user_low uuid references auth.users(id) on delete set null,
    user_high uuid references auth.users(id) on delete set null,
    score_low integer not null check (score_low between 0 and 100),
    score_high integer not null check (score_high between 0 and 100),
    algorithm_version text not null default '2026-11-14.v1',
    matched_at timestamptz not null default now(),
    ended_at timestamptz,
    ended_by uuid references auth.users(id) on delete set null,
    end_reason text check (end_reason in ('closed', 'blocked', 'profile_deleted')),
    check (user_low < user_high),
    check ((ended_at is null and end_reason is null and ended_by is null)
        or (ended_at is not null and end_reason is not null)),
    unique (user_low, user_high)
);
create index matches_low_history on public.matches(user_low, matched_at desc);
create index matches_high_history on public.matches(user_high, matched_at desc);

create table matching_private.pool (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    joined_at timestamptz not null default now()
);
-- This primary key is the final database guard against double booking.
create table matching_private.active_members (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    match_id uuid not null references public.matches(id)
);
create index active_members_match on matching_private.active_members(match_id);

-- Only a trusted verification service may attest an exact Storage object version.
-- A local client receipt or a user-editable profile flag is never proof.
create table matching_private.photo_verifications (
    object_id uuid primary key references storage.objects(id) on delete cascade,
    object_updated_at timestamptz not null,
    verified_at timestamptz not null default now()
);
grant select, insert, update, delete on matching_private.photo_verifications to service_role;

create table public.match_key_bundles (
    match_id uuid not null references public.matches(id),
    user_id uuid not null references auth.users(id) on delete cascade,
    device_id uuid not null,
    public_bundle jsonb not null check (jsonb_typeof(public_bundle) = 'object'
        and octet_length(public_bundle::text) between 2 and 16384),
    created_at timestamptz not null default now(),
    primary key (match_id, user_id, device_id)
);
create table public.encrypted_messages (
    id bigint generated always as identity primary key,
    match_id uuid not null references public.matches(id),
    sender_id uuid not null references auth.users(id) on delete cascade,
    client_message_id uuid not null,
    sender_device_id uuid not null,
    recipient_device_id uuid not null,
    -- Opaque protocol envelope, encrypted and authenticated on the device.
    ciphertext text not null check (octet_length(ciphertext) between 1 and 131072),
    protocol_version text not null check (protocol_version = 'e2ee-v1'),
    created_at timestamptz not null default now(),
    unique (match_id, sender_id, client_message_id)
);
create index encrypted_messages_conversation on public.encrypted_messages(match_id, id);

alter table public.matches enable row level security;
alter table public.match_key_bundles enable row level security;
alter table public.encrypted_messages enable row level security;
alter table matching_private.pool enable row level security;
alter table matching_private.active_members enable row level security;
alter table matching_private.photo_verifications enable row level security;
revoke all on public.matches, public.match_key_bundles, public.encrypted_messages from public, anon, authenticated;
grant select on public.matches, public.match_key_bundles, public.encrypted_messages to authenticated;
create policy "Participants read match history" on public.matches for select to authenticated
    using ((select auth.uid()) in (user_low, user_high));
create policy "Participants read public key bundles" on public.match_key_bundles for select to authenticated
    using (exists (select 1 from public.matches m where m.id = match_id
        and (select auth.uid()) in (m.user_low, m.user_high)));
create policy "Participants read encrypted history" on public.encrypted_messages for select to authenticated
    using (exists (select 1 from public.matches m where m.id = match_id
        and (select auth.uid()) in (m.user_low, m.user_high)));

create function matching_private.question_ids() returns text[]
language sql immutable set search_path = '' as $$
    select array['aloneTime','sharedHobbies','partnerSocializing','romanticGestures',
    'physicalAffection','publicAffection','sexualIntimacy','texting','calling','talkativeness',
    'conversationDepth','currentAffairs','communicationStyle','expressingAppreciation',
    'discussingFeelings','stressContact','listeningAndSolutions','debating','disagreements',
    'relationshipConversations','dailyRhythm','leisureTime','cityOrNature','nightlife',
    'socialPlans','hostingGuests','familyRole','pets','exPartnerContact','relationshipPrivacy',
    'socialMediaSharing','futurePlanning','weeklyPlanning','punctuality','homeTidiness',
    'foodChoices','diningOut','exercise','travel','travelStyle','newExperiences',
    'spendingMoney','workAmbition','decisionMaking','sharedResponsibilities',
    'takingInitiative','spirituality','celebrations','personalStyle','screenTime']::text[];
$$;

create function matching_private.answer(p jsonb, q text) returns jsonb
language sql immutable set search_path = '' as $$
    select case when q = 'aloneTime' then p #> '{lifestyle,aloneTime}'
        else p #> array['lifestyle','storedCompatibilityAnswers',q] end;
$$;

create function matching_private.eligible(p jsonb, b jsonb) returns boolean
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
            'ownAttractiveness','partnerMinimumAttractiveness','coarseLatitude','coarseLongitude',
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

create function matching_private.verified_photo(uid uuid, b jsonb) returns boolean
language sql stable security definer set search_path = '' as $$
    select exists (select 1 from storage.objects o
        join matching_private.photo_verifications v on v.object_id = o.id
            and v.object_updated_at = o.updated_at
        where o.bucket_id = 'profile-photos' and o.name = uid::text || '/' ||
            lower(b #>> '{state,storedAutoMatching,photoID}') || '.jpg');
$$;

-- One direction: all hard requirements, then the same weighted score as MatchReport.
create function matching_private.directional_score(s jsonb, c jsonb) returns integer
language plpgsql stable set search_path = '' as $$
declare q text; a jsonb; ca jsonb; habit text; years integer; d double precision;
    wanted integer; value integer; importance integer; w numeric; total numeric := 0;
    weights numeric := 0; n integer := 0;
begin
    years := extract(year from age(current_date, ((c->>'dateOfBirth')::timestamptz at time zone 'UTC')::date));
    if not (s->'interestedIn' ? (c->>'gender'))
        or years not between (s->>'preferredPartnerMinimumAge')::integer and (s->>'preferredPartnerMaximumAge')::integer
        or (c->>'heightCentimeters')::integer not between coalesce((s->>'preferredPartnerMinimumHeight')::integer,50) and coalesce((s->>'preferredPartnerMaximumHeight')::integer,250)
        or not (s->'acceptedPartnerReligions' ? (c->>'religion'))
        or not exists (select 1 from jsonb_array_elements_text(s->'languages') l(value) where c->'languages' ? l.value)
        or (c->>'ownAttractiveness')::integer < (s->>'partnerMinimumAttractiveness')::integer
        or (s #>> '{lifestyle,openToPartnerWithChildren}' = 'false' and c #>> '{lifestyle,hasChildren}' = 'true')
        or (s #>> '{lifestyle,futureChildren}' = 'yes' and c #>> '{lifestyle,futureChildren}' = 'no')
        or (s #>> '{lifestyle,futureChildren}' = 'no' and c #>> '{lifestyle,futureChildren}' = 'yes')
        then return null; end if;
    -- The selected arrangement is an explicit mutual requirement.
    if not exists (select 1 from jsonb_array_elements_text(s #> '{relationshipPreferences,sexualArrangement}') x(value)
        where c #> '{relationshipPreferences,sexualArrangement}' ? x.value) then return null; end if;
    d := 6371.0088 * 2 * asin(sqrt(least(1.0, greatest(0.0,
        power(sin(radians((c->>'coarseLatitude')::double precision - (s->>'coarseLatitude')::double precision)/2),2)
        + cos(radians((s->>'coarseLatitude')::double precision)) * cos(radians((c->>'coarseLatitude')::double precision))
        * power(sin(radians((c->>'coarseLongitude')::double precision - (s->>'coarseLongitude')::double precision)/2),2)))));
    if d > (s->>'preferredRadiusKilometers')::double precision then return null; end if;
    foreach habit in array array['alcohol','smoking','drugs'] loop
        a := s #> array['lifestyle','substances',habit];
        value := (c #>> array['lifestyle','substances',habit,'ownLevel'])::integer;
        if value > (a->>'partnerMaximumLevel')::integer then return null; end if;
        wanted := least((a->>'ownLevel')::integer, (a->>'partnerMaximumLevel')::integer);
        importance := 2 + round((5 - (a->>'partnerMaximumLevel')::integer) / 5.0 * 3)::integer;
        w := (array[0,1,2,4,8])[importance];
        total := total + w * (1 - abs(value-wanted)/5.0); weights := weights + w; n := n+1;
    end loop;
    foreach q in array matching_private.question_ids() loop
        a := matching_private.answer(s,q); ca := matching_private.answer(c,q);
        w := (array[0,1,2,4,8])[(a->>'importance')::integer];
        total := total + w * (1 - abs((ca->>'own')::integer - (a->>'partner')::integer)/4.0);
        weights := weights + w; n := n+1;
    end loop;
    return case when weights > 0 then round(total/weights*100)::integer when n > 0 then 100 else 0 end;
exception when data_exception then return null;
end;
$$;

create function matching_private.reconcile(uid uuid) returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare own public.profiles%rowtype; other record; mid uuid; lo uuid; hi uuid;
    own_score integer; other_score integer;
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
    -- Oldest eligible compatible candidate first; both personal thresholds must pass.
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
        lo := least(uid,other.id); hi := greatest(uid,other.id);
        insert into public.matches(user_low,user_high,score_low,score_high)
            values(lo,hi,case when uid=lo then own_score else other_score end,
                case when uid=hi then own_score else other_score end) returning id into mid;
        insert into matching_private.active_members(user_id,match_id) values(uid,mid),(other.id,mid);
        delete from matching_private.pool where user_id in (uid,other.id);
        return mid;
    end loop;
    return null;
end;
$$;

create function matching_private.profile_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    perform matching_private.reconcile(new.id);
    return new;
end;
$$;
create trigger profiles_matching after insert or update of profile, backup on public.profiles
    for each row execute function matching_private.profile_changed();

create function public.retry_matching() returns uuid
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
    return matching_private.reconcile(auth.uid());
end;
$$;

create function public.matching_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid(); mid uuid; p public.profiles%rowtype;
begin
    if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
    select match_id into mid from matching_private.active_members where user_id=uid;
    select * into p from public.profiles where id=uid;
    return jsonb_build_object('state', case when mid is not null then 'matched'
        when exists(select 1 from matching_private.pool where user_id=uid) then 'waiting'
        when coalesce((p.profile->>'autoMatchingEnabled')::boolean,false) then 'ineligible' else 'disabled' end,
        'match_id',mid,'photo_verified',matching_private.verified_photo(uid,p.backup));
end;
$$;

create function public.end_match(p_match_id uuid, p_reason text default 'closed') returns void
language plpgsql security definer set search_path = '' as $$
declare m public.matches%rowtype; uid uuid := auth.uid();
begin
    if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
    if p_reason not in ('closed','blocked') or p_reason is null then raise exception 'Invalid reason'; end if;
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    select * into m from public.matches where id=p_match_id and uid in (user_low,user_high);
    if not found then raise exception 'Match unavailable' using errcode='42501'; end if;
    if m.ended_at is not null then return; end if;
    update public.matches set ended_at=now(), ended_by=uid, end_reason=p_reason where id=m.id;
    delete from matching_private.active_members where match_id=m.id;
    -- Requeue both only if their saved auto-matching opt-in is still enabled.
    perform matching_private.reconcile(m.user_low);
    perform matching_private.reconcile(m.user_high);
end;
$$;

create function matching_private.profile_deleted() returns trigger
language plpgsql security definer set search_path = '' as $$
declare m public.matches%rowtype; partner uuid;
begin
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    select matches.* into m from public.matches matches
        join matching_private.active_members a on a.match_id=matches.id where a.user_id=old.id;
    delete from matching_private.pool where user_id=old.id;
    if m.id is not null then
        partner := case when m.user_low=old.id then m.user_high else m.user_low end;
        update public.matches set ended_at=now(),end_reason='profile_deleted',ended_by=old.id where id=m.id;
        delete from matching_private.active_members where match_id=m.id;
        -- Do not select the profile being deleted again in this BEFORE trigger.
        if exists(select 1 from public.profiles p where p.id=partner and matching_private.eligible(p.profile,p.backup)) then
            insert into matching_private.pool(user_id) values(partner) on conflict do nothing;
        end if;
    end if;
    return old;
end;
$$;
create trigger profiles_matching_deleted before delete on public.profiles
    for each row execute function matching_private.profile_deleted();

create function public.publish_match_key_bundle(p_match_id uuid, p_device_id uuid, p_public_bundle jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    if auth.uid() is null or not exists(select 1 from public.matches where id=p_match_id
        and ended_at is null and auth.uid() in (user_low,user_high)) then
        raise exception 'Active match required' using errcode='42501'; end if;
    -- Immutable per device: changes require a new device identifier and client verification.
    insert into public.match_key_bundles(match_id,user_id,device_id,public_bundle)
        values(p_match_id,auth.uid(),p_device_id,p_public_bundle) on conflict do nothing;
    if not exists(select 1 from public.match_key_bundles where match_id=p_match_id and user_id=auth.uid()
        and device_id=p_device_id and public_bundle=p_public_bundle) then
        raise exception 'Device key already registered'; end if;
end;
$$;

create function public.send_encrypted_message(p_match_id uuid, p_client_message_id uuid,
    p_sender_device_id uuid, p_recipient_device_id uuid, p_ciphertext text,
    p_protocol_version text default 'e2ee-v1') returns bigint
language plpgsql security definer set search_path = '' as $$
declare result bigint; existing public.encrypted_messages%rowtype;
begin
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    if auth.uid() is null or not exists(select 1 from public.matches where id=p_match_id
        and ended_at is null and auth.uid() in (user_low,user_high)) then
        raise exception 'Active match required' using errcode='42501'; end if;
    if not exists(select 1 from public.match_key_bundles where match_id=p_match_id
        and user_id=auth.uid() and device_id=p_sender_device_id)
        or not exists(select 1 from public.match_key_bundles where match_id=p_match_id
        and user_id<>auth.uid() and device_id=p_recipient_device_id) then
        raise exception 'Both device key bundles required'; end if;
    insert into public.encrypted_messages(match_id,sender_id,client_message_id,sender_device_id,
        recipient_device_id,ciphertext,protocol_version)
        values(p_match_id,auth.uid(),p_client_message_id,p_sender_device_id,p_recipient_device_id,p_ciphertext,p_protocol_version)
        on conflict (match_id,sender_id,client_message_id) do nothing returning id into result;
    if result is not null then return result; end if;
    select * into existing from public.encrypted_messages where match_id=p_match_id
        and sender_id=auth.uid() and client_message_id=p_client_message_id;
    if existing.ciphertext is distinct from p_ciphertext or existing.sender_device_id is distinct from p_sender_device_id
        or existing.recipient_device_id is distinct from p_recipient_device_id or existing.protocol_version is distinct from p_protocol_version then
        raise exception 'Message identifier already used'; end if;
    return existing.id;
end;
$$;

revoke all on all functions in schema matching_private from public, anon, authenticated;
grant execute on function matching_private.reconcile(uuid) to service_role;
revoke all on function public.retry_matching(), public.matching_status(), public.end_match(uuid,text),
    public.publish_match_key_bundle(uuid,uuid,jsonb), public.send_encrypted_message(uuid,uuid,uuid,uuid,text,text)
    from public, anon, authenticated;
grant execute on function public.retry_matching(), public.matching_status(), public.end_match(uuid,text),
    public.publish_match_key_bundle(uuid,uuid,jsonb), public.send_encrypted_message(uuid,uuid,uuid,uuid,text,text)
    to authenticated;

-- Seed existing opted-in profiles through exactly the same admission checks.
do $$ declare uid uuid; begin
    for uid in select id from public.profiles order by updated_at,id loop
        perform matching_private.reconcile(uid);
    end loop;
end; $$;
notify pgrst, 'reload schema';
commit;
