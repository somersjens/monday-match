-- Stop Swiping: the complete database, as one migration.
--
-- Replaces migrations 202611140001 to 202611150010, merged on 16 November 2026
-- before launch. Applying this to an empty Supabase project gives the same
-- schema those ten produced together, without their intermediate renames and
-- rewrites. Their history is in Git.
--
-- Matching is server-owned: clients can never choose their partner or scores.
-- Messages are end-to-end encrypted on the devices; the server stores opaque
-- envelopes only.
begin;

-- ===== 1. Profiles and photos =============================================
-- Private profile backups and matching data, owned by the signed-in user.
create table public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    profile jsonb not null,
    backup jsonb,
    updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
revoke all on public.profiles from anon;
grant select, insert, update, delete on public.profiles to authenticated;

create policy "Read own profile" on public.profiles
    for select to authenticated using ((select auth.uid()) = id);
create policy "Insert own profile" on public.profiles
    for insert to authenticated with check ((select auth.uid()) = id);
create policy "Update own profile" on public.profiles
    for update to authenticated using ((select auth.uid()) = id)
    with check ((select auth.uid()) = id);
create policy "Delete own profile" on public.profiles
    for delete to authenticated using ((select auth.uid()) = id);

create function public.set_profile_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger profiles_updated_at before update on public.profiles
    for each row execute function public.set_profile_updated_at();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-photos', 'profile-photos', false, 10485760, array['image/jpeg']);

create policy "Read own profile photos" on storage.objects
    for select to authenticated using (
        bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text
    );
create policy "Upload own profile photos" on storage.objects
    for insert to authenticated with check (
        bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text
    );
create policy "Update own profile photos" on storage.objects
    for update to authenticated using (
        bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text
    ) with check (
        bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text
    );
create policy "Delete own profile photos" on storage.objects
    for delete to authenticated using (
        bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text
    );

-- ===== 2. Tables ===========================================================
create schema if not exists matching_private;
revoke all on schema matching_private from public, anon, authenticated;
grant usage on schema matching_private to service_role;

-- Participant IDs stay in a match (and on its messages) after an account is
-- deleted, so the other person keeps the pair exclusion, can still decrypt
-- the conversation they took part in, and sees who it was with. When both
-- participants are gone the conversation is removed (account_deleted).
create table public.matches (
    id uuid primary key default gen_random_uuid(),
    user_low uuid,
    user_high uuid,
    score_low integer not null check (score_low between 0 and 100),
    score_high integer not null check (score_high between 0 and 100),
    algorithm_version text not null default '2026-11-15.v3',
    matched_at timestamptz not null default now(),
    ended_at timestamptz,
    ended_by uuid,
    end_reason text check (end_reason in ('broken', 'reported', 'profile_deleted', 'moderation')),
    check (user_low < user_high),
    check ((ended_at is null and end_reason is null and ended_by is null)
        or (ended_at is not null and end_reason is not null)),
    unique (user_low, user_high)
);
create index matches_low_history on public.matches(user_low, matched_at desc);
create index matches_high_history on public.matches(user_high, matched_at desc);
comment on column public.matches.end_reason is
    'broken: a participant broke it; reported: broken together with a report; '
    'profile_deleted: a participant deleted their profile or account; moderation: a participant was blocked or banned';

-- The waiting room. Each user's requirements are stored as plain columns and
-- their answers as small integer arrays, filled once on admission, so a
-- search is one SQL query instead of parsing 2 × 50 JSON answers per candidate.
create table matching_private.pool (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    joined_at timestamptz not null default now(),
    -- md5 of every column below: an unchanged save skips the search.
    inputs_hash text not null,
    identity_hashes text[] not null,
    gender text not null,
    interested_in text[] not null,
    birth_date date not null,
    min_age smallint not null,
    max_age smallint not null,
    height smallint not null,
    min_height smallint not null,
    max_height smallint not null,
    religion text not null,
    accepted_religions text[] not null,
    languages text[] not null,
    attractiveness smallint not null,
    min_attractiveness smallint not null,
    has_children boolean not null,
    open_to_children boolean not null,
    future_children text not null,
    -- [alcohol, smoking, drugs]
    substance_levels smallint[] not null,
    substance_limits smallint[] not null,
    arrangements text[] not null,
    latitude double precision not null,
    longitude double precision not null,
    radius_km integer not null,
    min_score smallint not null,
    requires_verified_photo boolean not null,
    photo_id text,
    -- The 50 questions in question_ids() order: own answer, wanted partner
    -- answer and importance weight (0/1/2/4/8).
    answers smallint[] not null,
    wanted smallint[] not null,
    weights smallint[] not null
);
create index pool_gender_birth on matching_private.pool(gender, birth_date);

-- This primary key is the final database guard against double booking.
create table matching_private.matched_users (
    user_id uuid primary key references public.profiles(id) on delete cascade,
    match_id uuid not null references public.matches(id)
);
create index matched_users_match on matching_private.matched_users(match_id);

-- Hashes of both sign-in identities (Apple/Google subject) per match, so
-- "never again" survives deleting and recreating an account.
create table matching_private.match_identities (
    match_id uuid not null references public.matches(id) on delete cascade,
    user_id uuid not null,
    identity_hashes text[] not null,
    primary key (match_id, user_id)
);
create index match_identities_hashes on matching_private.match_identities using gin (identity_hashes);

-- Only a trusted verification service may attest an exact Storage object version.
-- A local client receipt or a user-editable profile flag is never proof.
create table matching_private.photo_verifications (
    object_id uuid primary key references storage.objects(id) on delete cascade,
    object_updated_at timestamptz not null,
    verified_at timestamptz not null default now()
);
grant select, insert, update, delete on matching_private.photo_verifications to service_role;

create table matching_private.verification_attempts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    photo_id uuid not null,
    object_id uuid not null references storage.objects(id) on delete cascade,
    object_updated_at timestamptz not null,
    aws_session_id text unique,
    status text not null default 'pending' check(status in ('pending','verified','rejected','expired')),
    consent_version text not null,
    created_at timestamptz not null default now(),
    expires_at timestamptz not null default now()+interval '3 minutes',
    completed_at timestamptz
);
create index verification_attempt_user on matching_private.verification_attempts(user_id,created_at desc);

create table matching_private.moderation_notices_seen (
    user_id uuid primary key references auth.users(id) on delete cascade,
    strikes_seen integer not null default 0,
    seen_at timestamptz not null default now()
);

create table public.match_key_bundles (
    match_id uuid not null references public.matches(id),
    user_id uuid not null,
    device_id uuid not null,
    public_bundle jsonb not null check (jsonb_typeof(public_bundle) = 'object'
        and octet_length(public_bundle::text) between 2 and 16384),
    created_at timestamptz not null default now(),
    revoked_at timestamptz,
    primary key (match_id, user_id, device_id)
);
create unique index one_active_chat_device on public.match_key_bundles(match_id,user_id) where revoked_at is null;

create table public.encrypted_messages (
    id bigint generated always as identity primary key,
    match_id uuid not null references public.matches(id),
    sender_id uuid not null,
    client_message_id uuid not null,
    sender_device_id uuid not null,
    recipient_device_id uuid not null,
    -- Opaque protocol envelope, encrypted and authenticated on the device.
    ciphertext text not null check (octet_length(ciphertext) between 1 and 131072),
    protocol_version text not null check (protocol_version in ('e2ee-v1','hpke-auth-x25519-v1')),
    created_at timestamptz not null default now(),
    unique (match_id, sender_id, client_message_id)
);
create index encrypted_messages_conversation on public.encrypted_messages(match_id, id);

-- Each participant shares the same compact profile code a QR exchange would
-- show, so the other side can draw the match heart, both scores and the
-- answers behind them. The server never parses it.
create table public.match_cards (
    match_id uuid not null references public.matches(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    -- Base64 of ProfileCode.encoded(sharedCopy): age only, ~1 km location.
    card text not null check (octet_length(card) between 1 and 4096),
    shared_at timestamptz not null default now(),
    primary key (match_id, user_id)
);

-- How far each participant has read, for unread badges and read receipts.
create table public.match_read_states (
    match_id uuid not null references public.matches(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    last_read_message_id bigint not null default 0,
    read_at timestamptz not null default now(),
    primary key (match_id, user_id)
);

-- 1st counted report: a warning. 2nd: blocked for 7 days. 3rd: banned.
-- Only the first report per match counts, so one person can add at most one
-- strike. Strikes follow the sign-in identity, so a new account with the same
-- Apple/Google ID keeps them. A report stays valid when the reporter leaves.
create table public.match_reports (
    id uuid primary key default gen_random_uuid(),
    match_id uuid not null references public.matches(id),
    reporter_id uuid references auth.users(id) on delete set null,
    reason text not null check (reason in ('inappropriateContent', 'harassment', 'fakeProfile', 'spam', 'offlineBehavior',
                      'underage', 'hateSpeech', 'other')),
    details text not null check(octet_length(details)<=8000),
    created_at timestamptz not null default now(),
    ended_match boolean not null default false,
    reported_id uuid,
    reported_identities text[] not null default '{}',
    counts_as_strike boolean not null default false,
    dismissed_at timestamptz
);
create index match_reports_match on public.match_reports(match_id, created_at desc);
create index match_reports_reported_identities on public.match_reports using gin (reported_identities);
comment on column public.match_reports.counts_as_strike is 'True for the first report per match; dismissed_at withdraws it.';

alter table public.matches enable row level security;
alter table public.match_key_bundles enable row level security;
alter table public.encrypted_messages enable row level security;
alter table public.match_cards enable row level security;
alter table public.match_read_states enable row level security;
alter table public.match_reports enable row level security;
alter table matching_private.pool enable row level security;
alter table matching_private.matched_users enable row level security;
alter table matching_private.match_identities enable row level security;
alter table matching_private.photo_verifications enable row level security;
alter table matching_private.verification_attempts enable row level security;
alter table matching_private.moderation_notices_seen enable row level security;

revoke all on public.matches, public.match_key_bundles, public.encrypted_messages,
    public.match_cards, public.match_read_states, public.match_reports from public, anon, authenticated;
grant select on public.matches, public.match_key_bundles, public.encrypted_messages,
    public.match_cards, public.match_read_states, public.match_reports to authenticated;
create policy "Participants read match history" on public.matches for select to authenticated
    using ((select auth.uid()) in (user_low, user_high));
create policy "Participants read public key bundles" on public.match_key_bundles for select to authenticated
    using (exists (select 1 from public.matches m where m.id = match_id
        and (select auth.uid()) in (m.user_low, m.user_high)));
create policy "Participants read encrypted history" on public.encrypted_messages for select to authenticated
    using (exists (select 1 from public.matches m where m.id = match_id
        and (select auth.uid()) in (m.user_low, m.user_high)));
create policy "Participants read match cards" on public.match_cards for select to authenticated
    using (exists (select 1 from public.matches m where m.id = match_id
        and (select auth.uid()) in (m.user_low, m.user_high)));
create policy "Participants read read states" on public.match_read_states for select to authenticated
    using (exists (select 1 from public.matches m where m.id = match_id
        and (select auth.uid()) in (m.user_low, m.user_high)));
create policy "Read own match reports" on public.match_reports for select to authenticated
    using (reporter_id=(select auth.uid()));

-- ===== 3. Admission and scoring ============================================

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

-- sha256 of provider + subject, plus the account ID itself. A recreated
-- account with the same Apple/Google sign-in shares a hash with the old one.
create function matching_private.identity_hashes(uid uuid) returns text[]
language sql stable security definer set search_path = '' as $$
    select coalesce(array_agg(distinct encode(pg_catalog.sha256(convert_to(i.provider || ':' || i.provider_id, 'UTF8')), 'hex')),
                    array[]::text[]) || array['account:' || uid::text]
    from auth.identities i where i.user_id = uid;
$$;

create function matching_private.pool_entry(uid uuid, p jsonb, b jsonb) returns matching_private.pool
language plpgsql stable security definer set search_path = '' as $$
declare r matching_private.pool;
begin
    if not matching_private.eligible(p, b) then return null; end if;
    r.user_id := uid;
    r.gender := p->>'gender';
    r.interested_in := array(select jsonb_array_elements_text(p->'interestedIn'));
    r.birth_date := ((p->>'dateOfBirth')::timestamptz at time zone 'UTC')::date;
    r.min_age := (p->>'preferredPartnerMinimumAge')::smallint;
    r.max_age := least((p->>'preferredPartnerMaximumAge')::integer, 150)::smallint;
    r.height := (p->>'heightCentimeters')::smallint;
    r.min_height := coalesce((p->>'preferredPartnerMinimumHeight')::smallint, 50);
    r.max_height := coalesce((p->>'preferredPartnerMaximumHeight')::smallint, 250);
    r.religion := p->>'religion';
    r.accepted_religions := array(select jsonb_array_elements_text(p->'acceptedPartnerReligions'));
    r.languages := array(select jsonb_array_elements_text(p->'languages'));
    r.attractiveness := (p->>'ownAttractiveness')::smallint;
    r.min_attractiveness := (p->>'partnerMinimumAttractiveness')::smallint;
    r.has_children := (p #>> '{lifestyle,hasChildren}')::boolean;
    r.open_to_children := (p #>> '{lifestyle,openToPartnerWithChildren}')::boolean;
    r.future_children := p #>> '{lifestyle,futureChildren}';
    r.substance_levels := array(select (p #>> array['lifestyle','substances',h,'ownLevel'])::smallint
        from unnest(array['alcohol','smoking','drugs']) with ordinality u(h, i) order by i);
    r.substance_limits := array(select (p #>> array['lifestyle','substances',h,'partnerMaximumLevel'])::smallint
        from unnest(array['alcohol','smoking','drugs']) with ordinality u(h, i) order by i);
    r.arrangements := array(select jsonb_array_elements_text(
        coalesce(p #> '{relationshipPreferences,sexualArrangement}', '[]'::jsonb)));
    r.latitude := (p->>'coarseLatitude')::double precision;
    r.longitude := (p->>'coarseLongitude')::double precision;
    r.radius_km := (p->>'preferredRadiusKilometers')::integer;
    r.min_score := (p->>'minimumMatchPercent')::smallint;
    r.requires_verified_photo := coalesce((p->>'requiresVerifiedPartnerPhoto')::boolean, true);
    r.photo_id := lower(b #>> '{state,storedAutoMatching,photoID}');
    select array_agg((matching_private.answer(p, q)->>'own')::smallint order by i),
           array_agg((matching_private.answer(p, q)->>'partner')::smallint order by i),
           array_agg((array[0,1,2,4,8])[(matching_private.answer(p, q)->>'importance')::integer]::smallint order by i)
        into r.answers, r.wanted, r.weights
        from unnest(matching_private.question_ids()) with ordinality u(q, i);
    r.identity_hashes := matching_private.identity_hashes(uid);
    r.inputs_hash := md5(row(r.identity_hashes, r.gender, r.interested_in, r.birth_date, r.min_age, r.max_age,
        r.height, r.min_height, r.max_height, r.religion, r.accepted_religions, r.languages, r.attractiveness,
        r.min_attractiveness, r.has_children, r.open_to_children, r.future_children, r.substance_levels,
        r.substance_limits, r.arrangements, r.latitude, r.longitude, r.radius_km, r.min_score,
        r.requires_verified_photo, r.photo_id, r.answers, r.wanted, r.weights)::text);
    return r;
exception when data_exception then return null;
end;
$$;

create function matching_private.distance_km(lat1 double precision, lon1 double precision,
    lat2 double precision, lon2 double precision) returns double precision
language sql immutable parallel safe set search_path = '' as $$
    select 6371.0088 * 2 * asin(sqrt(least(1.0, greatest(0.0,
        power(sin(radians(lat2 - lat1) / 2), 2)
        + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2)))));
$$;

-- Every hard requirement of seeker s that candidate c has to meet.
create function matching_private.meets_requirements(s matching_private.pool, c matching_private.pool) returns boolean
language sql stable set search_path = '' as $$
    select c.gender = any(s.interested_in)
        and c.birth_date > current_date - make_interval(years => s.max_age + 1)
        and c.birth_date <= current_date - make_interval(years => s.min_age)
        and c.height between s.min_height and s.max_height
        and c.religion = any(s.accepted_religions)
        and c.languages && s.languages
        and c.attractiveness >= s.min_attractiveness
        and not (not s.open_to_children and c.has_children)
        and not (s.future_children = 'yes' and c.future_children = 'no')
        and not (s.future_children = 'no' and c.future_children = 'yes')
        and c.substance_levels[1] <= s.substance_limits[1]
        and c.substance_levels[2] <= s.substance_limits[2]
        and c.substance_levels[3] <= s.substance_limits[3]
        and c.arrangements && s.arrangements
        and matching_private.distance_km(s.latitude, s.longitude, c.latitude, c.longitude) <= s.radius_km;
$$;

-- Σ weight × closeness ÷ Σ weight over the 50 questions, like MatchReport.
create function matching_private.compatibility_score(wanted smallint[], weights smallint[], answers smallint[])
returns integer
language sql immutable parallel safe set search_path = '' as $$
    select case when sum(u.w) > 0 then round(sum(u.w * (1 - abs(u.a - u.x) / 4.0)) / sum(u.w) * 100)::integer
                else 100 end
    from unnest(wanted, weights, answers) as u(x, w, a);
$$;

-- Null when s's requirements rule c out, otherwise how well c fits s.
create function matching_private.directional_score(s matching_private.pool, c matching_private.pool) returns integer
language sql stable set search_path = '' as $$
    select case when matching_private.meets_requirements(s, c)
        then matching_private.compatibility_score(s.wanted, s.weights, c.answers) end;
$$;

create function matching_private.has_verified_photo(uid uuid, photo_id text) returns boolean
language sql stable security definer set search_path = '' as $$
    select exists (select 1 from storage.objects o
        join matching_private.photo_verifications v on v.object_id = o.id and v.object_updated_at = o.updated_at
        where o.bucket_id = 'profile-photos' and o.name = uid::text || '/' || photo_id || '.jpg');
$$;

-- ===== 4. Reports, strikes and blocks =====================================

create function matching_private.moderation_state(uid uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
    with me as (select matching_private.identity_hashes(uid) as hashes),
    strikes as (
        select r.created_at, row_number() over (order by r.created_at, r.id) as n
        from public.match_reports r, me
        where r.counts_as_strike and r.dismissed_at is null and r.reported_identities && me.hashes)
    select jsonb_build_object(
        'strikes', (select count(*) from strikes),
        'banned', exists (select 1 from strikes where n >= 3),
        'suspended_until', (select created_at + interval '7 days' from strikes where n = 2
            and not exists (select 1 from strikes where n >= 3)),
        'strikes_seen', coalesce((select strikes_seen from matching_private.moderation_notices_seen where user_id = uid), 0));
$$;

create function matching_private.is_blocked(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select coalesce((s->>'banned')::boolean, false) or coalesce((s->>'suspended_until')::timestamptz > now(), false)
    from matching_private.moderation_state(uid) s;
$$;

-- ===== 5. The engine ======================================================

create function matching_private.try_match(uid uuid, p_force boolean default true) returns uuid
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

-- Ends a match once, frees both people and lets each search again.
create function matching_private.end_match(p_match_id uuid, p_reason text, p_ended_by uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare m public.matches%rowtype;
begin
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    select * into m from public.matches where id = p_match_id for update;
    if not found or m.ended_at is not null then return; end if;
    update public.matches set ended_at = now(), ended_by = p_ended_by, end_reason = p_reason where id = m.id;
    delete from matching_private.matched_users where match_id = m.id;
    perform matching_private.try_match(m.user_low);
    perform matching_private.try_match(m.user_high);
end;
$$;

-- After a counted report: a block or ban ends the person's current match
-- (whoever it is with) and keeps them out of the pool until it expires.
create function matching_private.apply_moderation(uid uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare mid uuid;
begin
    if uid is null or not matching_private.is_blocked(uid) then return; end if;
    select match_id into mid from matching_private.matched_users where user_id = uid;
    if mid is not null then perform matching_private.end_match(mid, 'moderation', null); end if;
    delete from matching_private.pool where user_id = uid;
end;
$$;

-- Admin: withdraw a report found to be unfounded. A lifted block lets the
-- person search again straight away.
create function matching_private.dismiss_report(p_report_id uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare target uuid;
begin
    update public.match_reports set dismissed_at = now() where id = p_report_id and dismissed_at is null
        returning reported_id into target;
    if target is not null then perform matching_private.try_match(target); end if;
end;
$$;

create function matching_private.profile_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    perform matching_private.try_match(new.id, false);
    return new;
end;
$$;

create trigger profiles_matching after insert or update of profile, backup on public.profiles
    for each row execute function matching_private.profile_changed();

create function matching_private.profile_deleted() returns trigger
language plpgsql security definer set search_path = '' as $$
declare mid uuid; partner uuid;
begin
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    delete from matching_private.pool where user_id = old.id;
    select match_id into mid from matching_private.matched_users where user_id = old.id;
    if mid is not null then
        select user_id into partner from matching_private.matched_users where match_id = mid and user_id <> old.id;
        update public.matches set ended_at = now(), end_reason = 'profile_deleted', ended_by = old.id where id = mid;
        delete from matching_private.matched_users where match_id = mid;
        -- The deleted profile is out of the pool already, so it cannot be picked.
        if partner is not null then perform matching_private.try_match(partner); end if;
    end if;
    return old;
end;
$$;

create trigger profiles_matching_deleted before delete on public.profiles
    for each row execute function matching_private.profile_deleted();

-- A conversation nobody is left to read is removed.
create function matching_private.account_deleted() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    with orphaned as (
        select m.id from public.matches m
        where old.id in (m.user_low, m.user_high)
            and not exists (select 1 from auth.users u
                where u.id = case when m.user_low = old.id then m.user_high else m.user_low end))
    , gone_messages as (delete from public.encrypted_messages e using orphaned o where e.match_id = o.id)
    , gone_keys as (delete from public.match_key_bundles k using orphaned o where k.match_id = o.id)
    , gone_reads as (delete from public.match_read_states r using orphaned o where r.match_id = o.id)
    delete from public.match_cards c using orphaned o where c.match_id = o.id;
    return old;
end;
$$;

create trigger matching_account_deleted after delete on auth.users
    for each row execute function matching_private.account_deleted();

-- ===== 6. Client API: matching =============================================

create function public.retry_matching() returns uuid
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    return matching_private.try_match(auth.uid());
end;
$$;

create function public.matching_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid(); mid uuid; p public.profiles%rowtype; moderation jsonb;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    select match_id into mid from matching_private.matched_users where user_id = uid;
    select * into p from public.profiles where id = uid;
    moderation := matching_private.moderation_state(uid);
    return jsonb_build_object(
        'state', case
            when mid is not null then 'matched'
            when (moderation->>'banned')::boolean then 'banned'
            when (moderation->>'suspended_until')::timestamptz > now() then 'suspended'
            when exists (select 1 from matching_private.pool where user_id = uid) then 'waiting'
            when coalesce((p.profile->>'autoMatchingEnabled')::boolean, false) then 'ineligible'
            else 'disabled' end,
        'match_id', mid,
        'photo_verified', matching_private.has_verified_photo(uid, lower(p.backup #>> '{state,storedAutoMatching,photoID}')),
        'moderation', moderation);
end;
$$;

-- The person has seen the notice for their current number of strikes.
create function public.acknowledge_moderation() returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    insert into matching_private.moderation_notices_seen(user_id, strikes_seen)
        values (uid, (matching_private.moderation_state(uid)->>'strikes')::integer)
        on conflict (user_id) do update set strikes_seen = excluded.strikes_seen, seen_at = now();
end;
$$;

-- One match as the app shows it, active or ended.
create function matching_private.match_summary(m public.matches, uid uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
    select jsonb_build_object(
        'id', m.id,
        'partner_id', partner.id,
        'partner_name', coalesce(pr.profile->>'displayName', ''),
        'own_score', case when m.user_low = uid then m.score_low else m.score_high end,
        'partner_score', case when m.user_low = uid then m.score_high else m.score_low end,
        'matched_at', m.matched_at,
        'ended_at', m.ended_at,
        'end_reason', m.end_reason,
        'ended_by_me', coalesce(m.ended_by = uid, false),
        'partner_card', card.card,
        'unread_count', (select count(*) from public.encrypted_messages e
            where e.match_id = m.id and e.sender_id = partner.id
            and e.id > coalesce(own_read.last_read_message_id, 0)),
        'last_message_at', (select max(e.created_at) from public.encrypted_messages e where e.match_id = m.id),
        'partner_read_at', (select e.created_at from public.encrypted_messages e
            where e.id = partner_read.last_read_message_id))
    from (select case when m.user_low = uid then m.user_high else m.user_low end as id) partner
    left join public.profiles pr on pr.id = partner.id
    left join public.match_cards card on card.match_id = m.id and card.user_id = partner.id
    left join public.match_read_states own_read on own_read.match_id = m.id and own_read.user_id = uid
    left join public.match_read_states partner_read on partner_read.match_id = m.id and partner_read.user_id = partner.id;
$$;

create function public.current_match() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid(); result jsonb;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    select matching_private.match_summary(m, uid) into result
        from matching_private.matched_users a join public.matches m on m.id = a.match_id
        where a.user_id = uid and m.ended_at is null;
    return result;
end;
$$;

-- Every match this account has had, newest first: the active one and every
-- broken one, whose conversation stays readable but closed.
create function public.my_matches() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    return coalesce((select jsonb_agg(matching_private.match_summary(m, uid) order by m.matched_at desc)
        from public.matches m where m.user_low = uid or m.user_high = uid), '[]'::jsonb);
end;
$$;

create function public.break_match(p_match_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    if not exists (select 1 from public.matches where id = p_match_id and uid in (user_low, user_high)) then
        raise exception 'Match unavailable' using errcode = '42501'; end if;
    perform matching_private.end_match(p_match_id, 'broken', uid);
end;
$$;

create function public.report_partner(p_match_id uuid, p_reason text, p_details text,
    p_break_match boolean default false) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); m public.matches%rowtype; partner uuid; counts boolean;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    select * into m from public.matches where id = p_match_id and uid in (user_low, user_high);
    if not found then raise exception 'Match unavailable' using errcode = '42501'; end if;
    partner := case when m.user_low = uid then m.user_high else m.user_low end;
    counts := not exists (select 1 from public.match_reports where match_id = m.id and reporter_id = uid and counts_as_strike);
    -- One report per reason per hour keeps a single person from flooding moderation.
    if counts or not exists (select 1 from public.match_reports where match_id = m.id and reporter_id = uid
        and reason = p_reason and created_at > now() - interval '1 hour') then
        insert into public.match_reports(match_id, reporter_id, reported_id, reported_identities, reason, details,
            ended_match, counts_as_strike)
        values (m.id, uid, partner,
            coalesce((select identity_hashes from matching_private.match_identities where match_id = m.id and user_id = partner),
                     matching_private.identity_hashes(partner)),
            p_reason, coalesce(p_details, ''), coalesce(p_break_match, false), counts);
    end if;
    if coalesce(p_break_match, false) then perform matching_private.end_match(m.id, 'reported', uid); end if;
    if counts then perform matching_private.apply_moderation(partner); end if;
end;
$$;

-- ===== 7. Client API: chat ================================================

-- Chat checks the match row instead of the global lock: break_match updates
-- that row, so a send either lands before the break or is refused after it.
create function public.register_chat_device(p_match_id uuid, p_device_id uuid, p_public_bundle jsonb,
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

create function public.send_encrypted_message(p_match_id uuid, p_client_message_id uuid,
    p_sender_device_id uuid, p_recipient_device_id uuid, p_ciphertext text,
    p_protocol_version text default 'hpke-auth-x25519-v1') returns bigint
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); result bigint; existing public.encrypted_messages%rowtype;
begin
    perform 1 from public.matches where id = p_match_id and ended_at is null
        and uid is not null and uid in (user_low, user_high) for share;
    if not found then raise exception 'Active match required' using errcode = '42501'; end if;
    if p_protocol_version is distinct from 'hpke-auth-x25519-v1' then raise exception 'Unsupported protocol'; end if;
    if not exists (select 1 from public.match_key_bundles where match_id = p_match_id
        and user_id = uid and device_id = p_sender_device_id and revoked_at is null)
        or not exists (select 1 from public.match_key_bundles where match_id = p_match_id
        and user_id <> uid and device_id = p_recipient_device_id and revoked_at is null) then
        raise exception 'Both device key bundles required'; end if;
    insert into public.encrypted_messages(match_id, sender_id, client_message_id, sender_device_id,
        recipient_device_id, ciphertext, protocol_version)
        values (p_match_id, uid, p_client_message_id, p_sender_device_id, p_recipient_device_id, p_ciphertext, p_protocol_version)
        on conflict (match_id, sender_id, client_message_id) do nothing returning id into result;
    if result is not null then return result; end if;
    select * into existing from public.encrypted_messages where match_id = p_match_id
        and sender_id = uid and client_message_id = p_client_message_id;
    if existing.ciphertext is distinct from p_ciphertext or existing.sender_device_id is distinct from p_sender_device_id
        or existing.recipient_device_id is distinct from p_recipient_device_id
        or existing.protocol_version is distinct from p_protocol_version then
        raise exception 'Message identifier already used'; end if;
    return existing.id;
end;
$$;

-- The card is frozen once shared, like a saved match on the phone: scores
-- and answers stay as they were on the day of the match.
create function public.share_match_card(p_match_id uuid, p_card text) returns void
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null or not exists(select 1 from public.matches where id = p_match_id
        and ended_at is null and auth.uid() in (user_low, user_high)) then
        raise exception 'Active match required' using errcode = '42501'; end if;
    if p_card is null or octet_length(p_card) not between 1 and 4096 then
        raise exception 'Invalid match card'; end if;
    insert into public.match_cards(match_id, user_id, card) values(p_match_id, auth.uid(), p_card)
        on conflict (match_id, user_id) do nothing;
end; $$;

-- Read positions only move forward and only to messages of this match.
create function public.mark_chat_read(p_match_id uuid, p_message_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null or not exists(select 1 from public.matches where id = p_match_id
        and auth.uid() in (user_low, user_high)) then
        raise exception 'Match unavailable' using errcode = '42501'; end if;
    if not exists(select 1 from public.encrypted_messages where id = p_message_id and match_id = p_match_id) then
        raise exception 'Message unavailable'; end if;
    insert into public.match_read_states(match_id, user_id, last_read_message_id, read_at)
        values(p_match_id, auth.uid(), p_message_id, now())
        on conflict (match_id, user_id) do update
            set last_read_message_id = greatest(public.match_read_states.last_read_message_id, excluded.last_read_message_id),
                read_at = case when excluded.last_read_message_id > public.match_read_states.last_read_message_id
                    then now() else public.match_read_states.read_at end;
end; $$;

-- ===== 8. Photo verification (AWS Face Liveness) ===========================

create function public.begin_photo_verification(p_photo_id uuid,p_consent_version text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); object storage.objects%rowtype; attempt matching_private.verification_attempts%rowtype;
begin
    if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
    if p_consent_version is distinct from '2026-11-14.aws.v1' then raise exception 'AWS verification consent required'; end if;
    perform pg_catalog.pg_advisory_xact_lock(hashtextextended('photo-verification:'||uid::text,0));
    if (select count(*) from matching_private.verification_attempts where user_id=uid and created_at>now()-interval '1 day')>=5 then
        raise exception 'Daily verification limit reached'; end if;
    if not exists(select 1 from public.profiles where id=uid
        and lower(backup #>> '{state,storedAutoMatching,photoID}')=p_photo_id::text
        and backup #>> '{state,profilePrivacyConsent,version}'='2026-11-14.v1') then
        raise exception 'Selected photo unavailable'; end if;
    select * into object from storage.objects where bucket_id='profile-photos' and name=uid::text||'/'||p_photo_id::text||'.jpg';
    if not found then raise exception 'Photo upload must finish first'; end if;
    insert into matching_private.verification_attempts(user_id,photo_id,object_id,object_updated_at,consent_version)
        values(uid,p_photo_id,object.id,object.updated_at,p_consent_version) returning * into attempt;
    return jsonb_build_object('request_id',attempt.id,'expires_at',attempt.expires_at);
end; $$;

-- These worker functions are callable only with the server's service-role key.
-- No browser/iPhone may choose or attest a verification outcome.
create function public.photo_verification_worker_request(p_request_id uuid,p_user_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare a matching_private.verification_attempts%rowtype;
begin
    select * into a from matching_private.verification_attempts where id=p_request_id and user_id=p_user_id;
    if not found then raise exception 'Verification unavailable' using errcode='42501'; end if;
    return jsonb_build_object('request_id',a.id,'status',a.status,'aws_session_id',a.aws_session_id,
        'expires_at',a.expires_at,'path',a.user_id::text||'/'||a.photo_id::text||'.jpg',
        'photo_current',exists(select 1 from storage.objects o join public.profiles p on p.id=a.user_id
            where o.id=a.object_id and o.updated_at=a.object_updated_at
            and lower(p.backup #>> '{state,storedAutoMatching,photoID}')=a.photo_id::text));
end; $$;

create function public.bind_photo_verification_session(p_request_id uuid,p_user_id uuid,p_session_id text) returns void
language plpgsql security definer set search_path='' as $$ begin
    update matching_private.verification_attempts set aws_session_id=p_session_id where id=p_request_id and user_id=p_user_id
        and status='pending' and expires_at>now() and (aws_session_id is null or aws_session_id=p_session_id);
    if not found then raise exception 'Verification expired or already bound'; end if;
end; $$;

create function public.complete_photo_verification(p_request_id uuid,p_user_id uuid,p_session_id text,p_passed boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare a matching_private.verification_attempts%rowtype; valid boolean;
begin
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    select * into a from matching_private.verification_attempts where id=p_request_id and user_id=p_user_id for update;
    if not found or a.aws_session_id is distinct from p_session_id or p_session_id is null then
        raise exception 'Verification session mismatch' using errcode='42501'; end if;
    valid:=exists(select 1 from storage.objects o join public.profiles p on p.id=a.user_id
        where o.id=a.object_id and o.updated_at=a.object_updated_at
        and lower(p.backup #>> '{state,storedAutoMatching,photoID}')=a.photo_id::text);
    if a.status='verified' then return valid; end if;
    if a.status<>'pending' then return false; end if;
    if a.expires_at<=now() then
        update matching_private.verification_attempts set status='expired',completed_at=now() where id=a.id; return false;
    end if;
    if p_passed is true and valid then
        insert into matching_private.photo_verifications(object_id,object_updated_at)
            values(a.object_id,a.object_updated_at) on conflict(object_id) do update
                set object_updated_at=excluded.object_updated_at,verified_at=now();
        update matching_private.verification_attempts set status='verified',completed_at=now() where id=a.id;
        perform matching_private.try_match(a.user_id);
        return true;
    end if;
    update matching_private.verification_attempts set status='rejected',completed_at=now() where id=a.id;
    return false;
end; $$;

-- ===== 9. Account deletion ================================================
-- Deleting a profile removes the signed-in account itself. Rows that belong
-- to it follow through foreign keys and the triggers above. Profile photos
-- must be removed through the Storage API first: Storage does not allow
-- deleting its objects with SQL. App Store purchases are tied to the Apple ID.

create function public.delete_account() returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'Not signed in'; end if;
    delete from auth.users where id = uid;
end;
$$;

-- ===== 10. Admin overview =================================================

create view matching_private.overview with (security_invoker = true) as
select p.id as user_id, p.profile->>'displayName' as display_name,
    coalesce((p.profile->>'autoMatchingEnabled')::boolean, false) as auto_matching_enabled,
    case when a.match_id is not null then 'matched'
        when (moderation.s->>'banned')::boolean then 'banned'
        when (moderation.s->>'suspended_until')::timestamptz > now() then 'suspended'
        when pool.user_id is not null then 'waiting'
        when coalesce((p.profile->>'autoMatchingEnabled')::boolean, false) then 'ineligible'
        else 'disabled' end as state,
    a.match_id, case when m.user_low = p.id then m.user_high else m.user_low end as partner_id,
    pool.joined_at as waiting_since,
    (select count(*) from public.matches history where p.id in (history.user_low, history.user_high)) as matches_ever,
    (moderation.s->>'strikes')::integer as strikes,
    (moderation.s->>'suspended_until')::timestamptz as suspended_until,
    matching_private.has_verified_photo(p.id, lower(p.backup #>> '{state,storedAutoMatching,photoID}')) as photo_verified
from public.profiles p
cross join lateral (select matching_private.moderation_state(p.id) as s) moderation
left join matching_private.pool pool on pool.user_id = p.id
left join matching_private.matched_users a on a.user_id = p.id
left join public.matches m on m.id = a.match_id;

-- ===== 11. Privileges =====================================================
revoke all on matching_private.overview from public, anon, authenticated;
revoke all on all tables in schema matching_private from public, anon, authenticated;
revoke all on all functions in schema matching_private from public, anon, authenticated;
grant execute on function matching_private.try_match(uuid, boolean), matching_private.dismiss_report(uuid)
    to service_role;
revoke all on function public.retry_matching(), public.matching_status(), public.acknowledge_moderation(),
    public.current_match(), public.my_matches(), public.break_match(uuid),
    public.report_partner(uuid, text, text, boolean), public.register_chat_device(uuid, uuid, jsonb, boolean),
    public.send_encrypted_message(uuid, uuid, uuid, uuid, text, text),
    public.share_match_card(uuid, text), public.mark_chat_read(uuid, bigint), public.delete_account()
    from public, anon, authenticated;
grant execute on function public.retry_matching(), public.matching_status(), public.acknowledge_moderation(),
    public.current_match(), public.my_matches(), public.break_match(uuid),
    public.report_partner(uuid, text, text, boolean), public.register_chat_device(uuid, uuid, jsonb, boolean),
    public.send_encrypted_message(uuid, uuid, uuid, uuid, text, text),
    public.share_match_card(uuid, text), public.mark_chat_read(uuid, bigint), public.delete_account()
    to authenticated;
-- These worker functions are callable only with the server's service-role key.
-- No browser/iPhone may choose or attest a verification outcome.
revoke all on function public.begin_photo_verification(uuid,text),public.photo_verification_worker_request(uuid,uuid),
    public.bind_photo_verification_session(uuid,uuid,text),public.complete_photo_verification(uuid,uuid,text,boolean)
    from public,anon,authenticated;
grant execute on function public.begin_photo_verification(uuid,text) to authenticated;
grant execute on function public.photo_verification_worker_request(uuid,uuid),public.bind_photo_verification_session(uuid,uuid,text),
    public.complete_photo_verification(uuid,uuid,text,boolean) to service_role;
notify pgrst, 'reload schema';
commit;
