-- Stop Swiping: refining the report flow (decided 20 November 2026).
-- DEPLOYED 2026-11-20. Runs after 202611200008_demo_reports.sql.
-- Tests: supabase/tests/report_flow_refinement.sql.
--
-- 1. A ban follows the phone. When an account is banned (a third strike, or
--    an administrator's direct ban), the phones it used are remembered: a
--    keyed hash of the app's install ID (kept in this phone's keychain, so it
--    survives a reinstall) and of each push token. Another account that
--    registers one of those phones is banned too, as soon as it reaches the
--    server, e.g. when automatic matching is switched on. The phone ban ends
--    with the ban itself: an approved objection lifts both, and reports are
--    deleted after five years. Administrators are never caught by a phone ban.
-- 2. "Concerning offline behavior" goes to the administrators at once (push
--    and list). It counts as a normal strike straight away; the administrator
--    then keeps it as a regular warning, or bans the account directly. When
--    the person objects first, the objection card replaces the review card:
--    approve withdraws the report, reject keeps the warning, reject and ban
--    bans. One decision settles both, so no timer can undo it later.
-- 3. "May be under 18" is no longer a strike. It locks the account (no
--    matching, no chat, no "Understood") until the person proves their age:
--    - with a passport or ID card: every given name's first letter now
--      counts, so "Jan Pieter" may be called Pieter. A first, fully matching
--      document unlocks at once; any other goes to an administrator, and the
--      person is not told which part did not match;
--    - or, when the document can't be read, with a manual review request
--      (point 6), which an administrator approves or rejects.
-- 4. An administrator who rejects an objection can also ban the account
--    directly: an unfounded objection may end an account.
-- 5. The same phone also keeps two people from being matched again: a new
--    sign-in on a phone that was in an earlier match is never matched with
--    that match's partner, and two accounts on one phone never with each other.
-- 6. "Request manual review" (when a document can't be read): the person must
--    add a photo of their document, which stays on the phone. Only that a
--    photo was added reaches the server, never ID details.
-- 7. Nothing waits on an administrator forever (pg_cron, hourly):
--    - a manual review request is approved 24 hours after it was sent;
--    - any other objection is approved after 7 days;
--    - "concerning offline behavior" stays a regular warning after 7 days.
begin;

-- ===== 1. Reports: direct ban and administrator review ======================

alter table public.match_reports
    add column admin_ban boolean not null default false,
    add column review text check (review in ('pending', 'warning', 'ban')),
    add column reviewed_at timestamptz,
    add column reviewed_by uuid references auth.users(id) on delete set null;
comment on column public.match_reports.admin_ban is
    'An administrator banned the reported person directly over this report. Withdrawing the report lifts it.';
comment on column public.match_reports.review is
    'Concerning offline behavior: pending until an administrator keeps it as a warning or bans directly.';
create index match_reports_review_pending on public.match_reports(created_at) where review = 'pending';

-- Decided because nobody decided in time (section 9), not by an administrator.
alter table matching_private.report_objections add column timed_out boolean not null default false;

-- ===== 2. Phones ============================================================

-- The phones an account used: 'install:<hmac>' of the keychain install ID.
-- Push tokens are read from public.push_devices when needed.
create table matching_private.account_devices (
    user_id uuid not null references auth.users(id) on delete cascade,
    marker text not null check (marker ~ '^install:[0-9a-f]{64}$'),
    seen_at timestamptz not null default now(),
    primary key (user_id, marker)
);
create index account_devices_marker on matching_private.account_devices(marker);

-- Phones of a banned person, with that person's identity hashes: the phone
-- stays banned exactly as long as those identities are.
create table matching_private.banned_devices (
    marker text primary key check (marker ~ '^(install|push):[0-9a-f]{64}$'),
    identities text[] not null,
    banned_at timestamptz not null default now()
);
create index banned_devices_identities on matching_private.banned_devices using gin (identities);

alter table matching_private.account_devices enable row level security;
alter table matching_private.banned_devices enable row level security;
revoke all on matching_private.account_devices, matching_private.banned_devices from public, anon, authenticated;

create function matching_private.device_hash(kind text, value text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare k text;
begin
    select decrypted_secret into k from vault.decrypted_secrets where name = 'identity_hash_key';
    if k is null then raise exception 'Vault secret identity_hash_key is missing'; end if;
    return kind || ':' || encode(extensions.hmac(value, k, 'sha256'), 'hex');
end;
$$;

-- Every phone this account is known on.
create function matching_private.device_markers(uid uuid) returns text[]
language sql stable security definer set search_path = '' as $$
    select coalesce(array_agg(distinct m), array[]::text[]) from (
        select marker as m from matching_private.account_devices where user_id = uid
        union
        select matching_private.device_hash('push', token) from public.push_devices
            where user_id = uid and revoked_at is null) markers;
$$;

-- Banned by reports: a direct ban, or three strikes. "Under 18" and demo
-- reports never count; a withdrawn report never does.
create function matching_private.ban_kind(hashes text[]) returns text
language sql stable security definer set search_path = '' as $$
    select case
        when exists (select 1 from public.match_reports r
            where r.admin_ban and r.dismissed_at is null and not r.is_demo and r.reported_identities && hashes)
            then 'direct'
        when (select count(*) from public.match_reports r
            where r.counts_as_strike and r.dismissed_at is null and not r.is_demo and r.reason <> 'underage'
                and r.reported_identities && hashes) >= 3
            then 'strikes'
    end;
$$;

-- A phone this account uses belonged to someone who is still banned.
create function matching_private.device_banned(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select not matching_private.is_admin(uid) and exists (
        select 1 from matching_private.banned_devices b
        where b.marker = any(matching_private.device_markers(uid))
            and matching_private.ban_kind(b.identities) is not null);
$$;

-- Remembers every phone of a banned account.
create function matching_private.ban_devices(uid uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare hashes text[] := matching_private.identity_hashes(uid);
begin
    if matching_private.is_admin(uid) or matching_private.ban_kind(hashes) is null then return; end if;
    insert into matching_private.banned_devices as b (marker, identities)
        select m, hashes from unnest(matching_private.device_markers(uid)) m
        on conflict (marker) do update set banned_at = now(), identities = (
            select array_agg(distinct x) from unnest(b.identities || excluded.identities) x);
end;
$$;

-- The app tells the server which phone it runs on: before a profile is
-- uploaded for matching, and when it checks its status. Returns whether the
-- account is banned now.
create function public.register_device(p_install_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); this_phone text;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    if p_install_id is null then raise exception 'Install ID required' using errcode = '22023'; end if;
    this_phone := matching_private.device_hash('install', lower(p_install_id::text));
    insert into matching_private.account_devices as d (user_id, marker) values (uid, this_phone)
        on conflict (user_id, marker) do update set seen_at = now();
    -- A handful of phones per account is plenty; the oldest go.
    delete from matching_private.account_devices d where d.user_id = uid and d.marker in (
        select a.marker from matching_private.account_devices a where a.user_id = uid
        order by a.seen_at desc offset 10);
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    -- A banned person's new phone is banned too; another account on a banned
    -- phone loses its match and its place in the pool.
    perform matching_private.ban_devices(uid);
    perform matching_private.apply_moderation(uid);
    return coalesce((matching_private.moderation_state(uid)->>'banned')::boolean, false);
end;
$$;

-- ===== 2b. Never matched again on the same phone =============================

-- The phones of both people at the time of a match, next to their identities.
alter table matching_private.match_identities add column device_markers text[] not null default '{}';
create index match_identities_devices on matching_private.match_identities using gin (device_markers);

-- As in 202611180005, plus phones: the earlier matches of this person also
-- include those made on this phone under another sign-in, and a candidate is
-- left out when they use a phone of an earlier partner, or this same phone.
create or replace function matching_private.try_match(uid uuid, p_force boolean default true, p_search boolean default true)
returns uuid
language plpgsql volatile security definer set search_path = '' as $$
declare own public.profiles%rowtype; me matching_private.pool; existing matching_private.pool;
    mid uuid; past text[]; past_devices text[]; my_devices text[]; best_id uuid; best_mine integer;
    best_theirs integer; best_hashes text[];
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
        if not p_force and existing.inputs_hash = me.inputs_hash then return null; end if;
        me.joined_at := existing.joined_at;
        delete from matching_private.pool where user_id = uid;
    else
        me.joined_at := now();
    end if;
    insert into matching_private.pool select (me).*;
    if not p_search then return null; end if;

    my_devices := array(select marker from matching_private.account_devices where user_id = uid);
    -- Everyone this person (under any of their sign-ins, or on this phone)
    -- was ever matched with: their identities and their phones.
    select coalesce(array_agg(distinct h), array[]::text[]) into past
        from matching_private.match_identities mine
        join matching_private.match_identities other on other.match_id = mine.match_id and other.user_id <> mine.user_id
        cross join lateral unnest(other.identity_hashes) h
        where mine.identity_hashes && me.identity_hashes or mine.device_markers && my_devices;
    select coalesce(array_agg(distinct d), array[]::text[]) into past_devices
        from matching_private.match_identities mine
        join matching_private.match_identities other on other.match_id = mine.match_id and other.user_id <> mine.user_id
        cross join lateral unnest(other.device_markers) d
        where mine.identity_hashes && me.identity_hashes or mine.device_markers && my_devices;
    past_devices := past_devices || my_devices;

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
            and (cardinality(past_devices) = 0 or not exists (select 1 from matching_private.account_devices d
                where d.user_id = c.user_id and d.marker = any(past_devices)))
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
    insert into matching_private.match_identities(match_id, user_id, identity_hashes, device_markers)
        values (mid, uid, me.identity_hashes, my_devices),
               (mid, best_id, best_hashes,
                array(select marker from matching_private.account_devices where user_id = best_id));
    delete from matching_private.pool where user_id in (uid, best_id);
    return mid;
end;
$$;

-- ===== 3. What the person sees ==============================================

-- As in 202611200008, plus:
--   'strikes' and 'latest_report' leave "under 18" out: it is not a strike;
--   'banned' also for a direct ban and a banned phone, with 'ban_reason'
--     ('strikes', 'direct' or 'device');
--   'age_check': the newest "under 18" report that still stands, with the
--     state of its objection; 'age_locked' while it locks the account (a
--     demo report shows the same but never locks).
create or replace function matching_private.moderation_state(uid uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
    with me as (select matching_private.identity_hashes(uid) as hashes),
    shown as (
        select r.id, r.reason, r.created_at, r.is_demo
        from public.match_reports r, me
        where r.counts_as_strike and r.dismissed_at is null and r.reported_identities && me.hashes),
    warnings as (select * from shown where reason <> 'underage'),
    strikes as (
        select s.created_at, row_number() over (order by s.created_at, s.id) as n
        from warnings s where not s.is_demo),
    age as (
        select s.id, s.created_at, s.is_demo,
            (select coalesce(o.decision, 'pending') from matching_private.report_objections o where o.report_id = s.id)
                as objection
        from shown s where s.reason = 'underage' order by s.created_at desc, s.id desc limit 1),
    ban as (
        select coalesce(matching_private.ban_kind(me.hashes),
            case when matching_private.device_banned(uid) then 'device' end) as kind
        from me)
    select jsonb_build_object(
        'strikes', (select count(*) from warnings),
        'banned', (select kind is not null from ban),
        'ban_reason', (select kind from ban),
        'suspended_until', (select created_at + interval '7 days' from strikes where n = 2
            and not exists (select 1 from strikes where n >= 3) and (select kind from ban) is null),
        'strikes_seen', coalesce((select strikes_seen from matching_private.moderation_notices_seen where user_id = uid), 0),
        'latest_report', (select jsonb_build_object('id', s.id, 'reason', s.reason, 'created_at', s.created_at,
                'is_demo', s.is_demo,
                'objection', (select coalesce(o.decision, 'pending') from matching_private.report_objections o
                    where o.report_id = s.id))
            from warnings s order by s.created_at desc, s.id desc limit 1),
        'age_check', (select jsonb_build_object('id', a.id, 'created_at', a.created_at, 'is_demo', a.is_demo,
                'objection', a.objection) from age a),
        'age_locked', exists (select 1 from age where not is_demo),
        'objection_result', (select jsonb_build_object('id', o.id, 'decision', o.decision, 'reason', r.reason)
            from matching_private.report_objections o join public.match_reports r on r.id = o.report_id
            where o.user_id = uid and o.decision is not null and o.result_seen_at is null
            order by o.decided_at desc limit 1));
$$;

-- Banned, blocked for 7 days, or waiting to prove their age.
create or replace function matching_private.is_blocked(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select coalesce((s->>'banned')::boolean, false)
        or coalesce((s->>'suspended_until')::timestamptz > now(), false)
        or coalesce((s->>'age_locked')::boolean, false)
    from matching_private.moderation_state(uid) s;
$$;

-- As in the baseline; a ban now also bans the person's phones.
create or replace function matching_private.apply_moderation(uid uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
declare mid uuid;
begin
    if uid is null or not matching_private.is_blocked(uid) then return; end if;
    perform matching_private.ban_devices(uid);
    select match_id into mid from matching_private.matched_users where user_id = uid;
    if mid is not null then perform matching_private.end_match(mid, 'moderation', null); end if;
    delete from matching_private.pool where user_id = uid;
end;
$$;

-- As in 202611200007, with 'age_check' as a state of its own, and open
-- reviews in the administrators' badge.
create or replace function public.matching_status() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid(); mid uuid; p public.profiles%rowtype; moderation jsonb; admin boolean;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    select match_id into mid from matching_private.matched_users where user_id = uid;
    select * into p from public.profiles where id = uid;
    moderation := matching_private.moderation_state(uid);
    admin := matching_private.is_admin(uid);
    return jsonb_build_object(
        'state', case
            when mid is not null then 'matched'
            when (moderation->>'banned')::boolean then 'banned'
            when (moderation->>'suspended_until')::timestamptz > now() then 'suspended'
            when (moderation->>'age_locked')::boolean then 'age_check'
            when exists (select 1 from matching_private.pool where user_id = uid) then 'waiting'
            when coalesce((p.profile->>'autoMatchingEnabled')::boolean, false) then 'ineligible'
            else 'disabled' end,
        'match_id', mid,
        'photo_verified', matching_private.has_verified_photo(uid, lower(p.backup #>> '{state,storedAutoMatching,photoID}')),
        'moderation', moderation,
        'is_admin', admin,
        'admin_pending', case when admin then
            (select count(*) from matching_private.report_objections where decision is null)
            + (select count(*) from public.match_reports r where r.review = 'pending' and r.dismissed_at is null
                and not exists (select 1 from matching_private.report_objections o
                    where o.report_id = r.id and o.decision is null))
            else 0 end);
end;
$$;

-- ===== 4. Filing a report ===================================================

-- As in 202611200007; "concerning offline behavior" also goes to the
-- administrators for review.
create or replace function public.report_partner(p_match_id uuid, p_reason text, p_details text,
    p_break_match boolean default false, p_chat_copy jsonb default null) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); m public.matches%rowtype; partner uuid; counts boolean; inserted uuid;
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
            ended_match, counts_as_strike, chat_copy, review)
        values (m.id, uid, partner,
            coalesce((select identity_hashes from matching_private.match_identities where match_id = m.id and user_id = partner),
                     matching_private.identity_hashes(partner)),
            p_reason, coalesce(p_details, ''), coalesce(p_break_match, false), counts,
            case when jsonb_typeof(p_chat_copy) = 'array' and jsonb_array_length(p_chat_copy) > 0 then p_chat_copy end,
            case when p_reason = 'offlineBehavior' then 'pending' end)
        returning id into inserted;
        if inserted is not null and p_reason = 'offlineBehavior' then
            insert into notification_private.outbox(user_id, kind, match_id, detail)
                select a.user_id, 'moderation_report', m.id, 'review' from matching_private.admins a
                on conflict do nothing;
        end if;
    end if;
    if coalesce(p_break_match, false) then perform matching_private.end_match(m.id, 'reported', uid); end if;
    if counts then perform matching_private.apply_moderation(partner); end if;
end;
$$;

-- As in 202611200008; a demo "concerning offline behavior" report also shows
-- in the review list (without a push), to try the decision.
create or replace function public.report_demo(p_reason text, p_details text, p_chat_copy jsonb default null) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    if not matching_private.is_admin(uid) then raise exception 'Administrators only' using errcode = '42501'; end if;
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    delete from matching_private.report_objections o using public.match_reports r
        where r.id = o.report_id and r.is_demo and r.reporter_id = uid and r.dismissed_at is null
            and o.decision is null;
    update public.match_reports set dismissed_at = now(), review = case when review = 'pending' then null else review end
        where is_demo and reporter_id = uid and dismissed_at is null;
    update matching_private.moderation_notices_seen
        set strikes_seen = least(strikes_seen, (matching_private.moderation_state(uid)->>'strikes')::integer)
        where user_id = uid;
    insert into public.match_reports(match_id, reporter_id, reported_id, reported_identities, reason, details,
        ended_match, counts_as_strike, chat_copy, is_demo, review)
    values (null, uid, uid, matching_private.identity_hashes(uid), p_reason, coalesce(p_details, ''), false, true,
        case when jsonb_typeof(p_chat_copy) = 'array' and jsonb_array_length(p_chat_copy) > 0 then p_chat_copy end,
        true, case when p_reason = 'offlineBehavior' then 'pending' end);
end;
$$;

-- ===== 5. Proving one's age =================================================

-- Every given name's first letter, from 'initials' (new apps) or 'initial'.
create function matching_private.document_initials(p_id_check jsonb) returns text[]
language sql immutable set search_path = '' as $$
    select coalesce(array_agg(distinct i) filter (where i ~ '^[A-Z]$'), array[]::text[]) from (
        select matching_private.initial_of(v) as i from jsonb_array_elements_text(
            case when jsonb_typeof(p_id_check->'initials') = 'array' then p_id_check->'initials' else '[]'::jsonb end) v
        union all
        select matching_private.initial_of(p_id_check->>'initial')) letters;
$$;

-- As in 202611200008, with changes for "under 18": every given name's
-- initial counts; with a document the message is optional; and a person
-- whose document can't be read requests a manual review instead
-- ({"manual_review": true}, after adding a photo that stays on their phone).
-- That is approved after 24 hours unless an administrator decides first.
create or replace function public.object_to_report(p_report_id uuid, p_message text, p_id_check jsonb default null) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.match_reports%rowtype; msg text := btrim(coalesce(p_message, ''));
    checked jsonb; doc_birth date; doc_expires date; doc_initials text[]; p public.profiles%rowtype;
    profile_birth date; profile_initial text; inserted uuid; has_document boolean; manual boolean;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    select * into r from public.match_reports
        where id = p_report_id and counts_as_strike and dismissed_at is null
            and reported_identities && matching_private.identity_hashes(uid);
    if not found then raise exception 'Report unavailable' using errcode = '42501'; end if;
    -- coalesce: without p_id_check these would be null, and null slips past every check.
    manual := coalesce(r.reason = 'underage' and jsonb_typeof(p_id_check) = 'object'
        and (p_id_check->>'manual_review')::boolean, false);
    if manual and not coalesce((p_id_check->>'photo_attached')::boolean, false) then
        raise exception 'Photo required' using errcode = '22023'; end if;
    has_document := coalesce(r.reason = 'underage' and jsonb_typeof(p_id_check) = 'object', false) and not manual;
    if manual then checked := jsonb_build_object('manual_review', true, 'photo_attached', true); end if;
    if length(msg) = 0 and not has_document and not manual then
        raise exception 'Objection message required' using errcode = '22023'; end if;
    if length(msg) > 2000 then raise exception 'Objection message too long' using errcode = '22023'; end if;

    if has_document then
        doc_initials := matching_private.document_initials(p_id_check);
        begin
            doc_birth := (p_id_check->>'birth_date')::date;
            doc_expires := (p_id_check->>'expires')::date;
        exception when others then
            raise exception 'Proof of age unreadable' using errcode = '22023';
        end;
        if cardinality(doc_initials) = 0 or doc_birth is null then
            raise exception 'Proof of age unreadable' using errcode = '22023'; end if;
        select * into p from public.profiles where id = uid;
        profile_birth := ((p.profile->>'dateOfBirth')::timestamptz at time zone 'UTC')::date;
        profile_initial := matching_private.initial_of(p.profile->>'displayName');
        checked := jsonb_build_object(
            'initial', doc_initials[1],
            'initials', to_jsonb(doc_initials),
            'birth_date', doc_birth,
            'expires', doc_expires,
            'document', left(coalesce(p_id_check->>'document', ''), 2),
            'check_digits', coalesce((p_id_check->>'check_digits')::boolean, false),
            'adult', doc_birth <= current_date - interval '18 years',
            'expired', doc_expires is not null and doc_expires < current_date,
            -- Against the profile on the server; null when it left matching.
            'profile_initial', profile_initial,
            'profile_birth_date', profile_birth,
            'initial_matches', case when p.id is null then null else profile_initial = any(doc_initials) end,
            'birth_date_matches', case when profile_birth is null then null else profile_birth = doc_birth end);
    end if;

    insert into matching_private.report_objections(report_id, user_id, message, id_check)
        values (r.id, uid, msg, checked)
        on conflict (report_id) do nothing
        returning id into inserted;
    if inserted is null then raise exception 'Objection already made' using errcode = '23505'; end if;

    -- A first age proof where everything matches needs no administrator.
    if has_document
        and coalesce((checked->>'initial_matches')::boolean, false)
        and coalesce((checked->>'birth_date_matches')::boolean, false)
        and coalesce((checked->>'adult')::boolean, false)
        and coalesce((checked->>'check_digits')::boolean, false)
        and not coalesce((checked->>'expired')::boolean, true)
        and not matching_private.age_proven_before(r.reported_identities, r.id) then
        update matching_private.report_objections
            set decision = 'approved', decided_at = now(), decided_automatically = true where id = inserted;
        perform matching_private.withdraw_report(r.id, uid);
        return;
    end if;

    -- Administrators hear only about objections they must decide. A demo
    -- report has no match to hang a push on; it shows in their list only.
    if not r.is_demo then
        insert into notification_private.outbox(user_id, kind, match_id, detail)
            select a.user_id, 'moderation_report', r.match_id, r.reason from matching_private.admins a
            on conflict do nothing;
    end if;
end;
$$;

-- How long an objection waits for an administrator before it is approved.
create function matching_private.objection_timeout(p_id_check jsonb) returns interval
language sql immutable set search_path = '' as $$
    select case when coalesce((p_id_check->>'manual_review')::boolean, false)
        then interval '24 hours' else interval '7 days' end;
$$;

-- ===== 6. Administrators ====================================================

-- As in 202611200008; strikes leave "under 18" out, and "initials" shows
-- every given name's first letter.
create or replace function public.admin_objections() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if not matching_private.is_admin(uid) then raise exception 'Administrators only' using errcode = '42501'; end if;
    return coalesce((select jsonb_agg(jsonb_build_object(
            'id', o.id,
            'created_at', o.created_at,
            'message', o.message,
            'id_check', o.id_check,
            'display_name', pr.profile->>'displayName',
            'age_proven_before', r.reason = 'underage' and matching_private.age_proven_before(r.reported_identities, r.id),
            -- Approved by then unless decided (section 9).
            'auto_decides_at', o.created_at + matching_private.objection_timeout(o.id_check),
            'report', jsonb_build_object(
                'id', r.id,
                'reason', r.reason,
                'details', r.details,
                'created_at', r.created_at,
                'chat_copy', r.chat_copy,
                'ended_match', r.ended_match,
                'is_demo', r.is_demo,
                -- 0 "under 18" (a lock, not a strike), 1 warning, 2 a 7-day block, 3 or more a ban.
                'strike', case when r.reason = 'underage' then 0 when r.is_demo then 1
                    else (select count(*) from public.match_reports s
                    where s.counts_as_strike and s.dismissed_at is null and not s.is_demo and s.reason <> 'underage'
                        and s.reported_identities && r.reported_identities
                        and (s.created_at, s.id) <= (r.created_at, r.id)) end))
            order by o.created_at)
        from matching_private.report_objections o
        join public.match_reports r on r.id = o.report_id
        left join public.profiles pr on pr.id = o.user_id
        where o.decision is null), '[]'::jsonb);
end;
$$;

-- Approve: the report is withdrawn. Reject: it stands; with p_ban the
-- account is also banned directly (an unfounded objection).
drop function public.admin_decide_objection(uuid, boolean);
create function public.admin_decide_objection(p_objection_id uuid, p_approve boolean, p_ban boolean default false)
returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); o matching_private.report_objections%rowtype;
begin
    if not matching_private.is_admin(uid) then raise exception 'Administrators only' using errcode = '42501'; end if;
    if p_approve is null then raise exception 'Decision required' using errcode = '22023'; end if;
    if p_approve and coalesce(p_ban, false) then raise exception 'Cannot approve and ban' using errcode = '22023'; end if;
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    update matching_private.report_objections
        set decision = case when p_approve then 'approved' else 'rejected' end, decided_at = now(), decided_by = uid
        where id = p_objection_id and decision is null
        returning * into o;
    if not found then raise exception 'Objection already decided' using errcode = '23505'; end if;
    -- A review still waiting on the same report is settled with it.
    update public.match_reports
        set review = case when p_approve then null when coalesce(p_ban, false) then 'ban' else 'warning' end,
            reviewed_at = now(), reviewed_by = uid
        where id = o.report_id and review = 'pending';
    if p_approve then
        perform matching_private.withdraw_report(o.report_id, o.user_id);
    elsif coalesce(p_ban, false) then
        update public.match_reports set admin_ban = true where id = o.report_id;
        perform matching_private.apply_moderation(o.user_id);
    end if;
end;
$$;

-- Every "concerning offline behavior" report waiting for a decision, oldest
-- first. One the person objected to shows as that objection instead.
create function public.admin_reviews() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if not matching_private.is_admin(uid) then raise exception 'Administrators only' using errcode = '42501'; end if;
    return coalesce((select jsonb_agg(jsonb_build_object(
            'id', r.id,
            'reason', r.reason,
            'details', r.details,
            'created_at', r.created_at,
            'chat_copy', r.chat_copy,
            'ended_match', r.ended_match,
            'is_demo', r.is_demo,
            'display_name', pr.profile->>'displayName',
            -- Kept as a regular warning by then unless decided (section 9).
            'auto_decides_at', r.created_at + interval '7 days',
            'strike', case when r.is_demo then 1 else (select count(*) from public.match_reports s
                where s.counts_as_strike and s.dismissed_at is null and not s.is_demo and s.reason <> 'underage'
                    and s.reported_identities && r.reported_identities
                    and (s.created_at, s.id) <= (r.created_at, r.id)) end)
            order by r.created_at)
        from public.match_reports r
        left join public.profiles pr on pr.id = r.reported_id
        where r.review = 'pending' and r.dismissed_at is null
            and not exists (select 1 from matching_private.report_objections o
                where o.report_id = r.id and o.decision is null)), '[]'::jsonb);
end;
$$;

-- Keep the report as a regular warning (it already counts as one), or ban
-- the account directly.
create function public.admin_review_report(p_report_id uuid, p_ban boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.match_reports%rowtype;
begin
    if not matching_private.is_admin(uid) then raise exception 'Administrators only' using errcode = '42501'; end if;
    if p_ban is null then raise exception 'Decision required' using errcode = '22023'; end if;
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    update public.match_reports
        set review = case when p_ban then 'ban' else 'warning' end, reviewed_at = now(), reviewed_by = uid,
            admin_ban = admin_ban or p_ban
        where id = p_report_id and review = 'pending'
        returning * into r;
    if not found then raise exception 'Report already reviewed' using errcode = '23505'; end if;
    -- An objection to it is decided with the objection itself (admin_decide_objection).
    if exists (select 1 from matching_private.report_objections where report_id = r.id and decision is null) then
        raise exception 'Objection pending' using errcode = '23505'; end if;
    if p_ban and not r.is_demo then perform matching_private.apply_moderation(r.reported_id); end if;
end;
$$;

-- ===== 9. Decisions nobody made in time =====================================

-- Objections past their time are approved (the report is withdrawn, and a
-- review waiting on it goes with it); reviews of concerning behavior past
-- 7 days stay the regular warning they already are.
create function matching_private.auto_decide_moderation() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare o matching_private.report_objections%rowtype;
begin
    for o in select * from matching_private.report_objections
        where decision is null and created_at + matching_private.objection_timeout(id_check) <= now()
        order by created_at limit 200
    loop
        update matching_private.report_objections
            set decision = 'approved', decided_at = now(), timed_out = true
            where id = o.id and decision is null;
        if found then
            update public.match_reports set review = null, reviewed_at = now()
                where id = o.report_id and review = 'pending';
            perform matching_private.withdraw_report(o.report_id, o.user_id);
        end if;
    end loop;
    update public.match_reports r set review = 'warning', reviewed_at = now()
        where r.review = 'pending' and r.dismissed_at is null and r.created_at <= now() - interval '7 days'
            and not exists (select 1 from matching_private.report_objections waiting
                where waiting.report_id = r.id and waiting.decision is null);
end;
$$;

select cron.schedule('moderation-auto-decide', '23 * * * *', 'select matching_private.auto_decide_moderation()');

-- ===== 7. Retention =========================================================

-- As in 202611200007, plus: phones of an account not seen for 12 months, and
-- banned phones five years after their ban (the reports behind them are gone
-- by then too).
create or replace function matching_private.purge_expired() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare cutoff timestamptz := now() - interval '12 months';
        five_years timestamptz := now() - interval '5 years';
begin
    delete from public.encrypted_messages where created_at < cutoff;
    delete from public.match_cards c using public.matches m where m.id = c.match_id and m.ended_at < cutoff;
    delete from public.match_key_bundles k using public.matches m where m.id = k.match_id and m.ended_at < cutoff;
    delete from public.match_read_states r using public.matches m where m.id = r.match_id and m.ended_at < cutoff;
    update public.match_reports set details = '', chat_copy = null
        where created_at < cutoff and (details <> '' or chat_copy is not null);
    update matching_private.report_objections set message = '', id_check = null
        where decided_at < cutoff and (message <> '' or id_check is not null);
    delete from matching_private.verification_attempts where created_at < cutoff;
    delete from matching_private.account_devices where seen_at < cutoff;
    delete from matching_private.banned_devices where banned_at < five_years;

    delete from public.match_reports where created_at < five_years;
    delete from public.encrypted_messages e using public.matches m
        where m.id = e.match_id and m.ended_at < five_years;
    delete from public.match_key_bundles k using public.matches m
        where m.id = k.match_id and m.ended_at < five_years;
    delete from public.matches m where m.ended_at < five_years
        and not exists (select 1 from public.match_reports r where r.match_id = m.id);
end;
$$;

-- ===== 8. Privileges ========================================================

revoke all on function matching_private.device_hash(text, text), matching_private.device_markers(uuid),
    matching_private.ban_kind(text[]), matching_private.device_banned(uuid), matching_private.ban_devices(uuid),
    matching_private.document_initials(jsonb), matching_private.moderation_state(uuid),
    matching_private.try_match(uuid, boolean, boolean), matching_private.objection_timeout(jsonb),
    matching_private.auto_decide_moderation(),
    matching_private.is_blocked(uuid), matching_private.apply_moderation(uuid), matching_private.purge_expired()
    from public, anon, authenticated;
revoke all on function public.register_device(uuid), public.matching_status(),
    public.report_partner(uuid, text, text, boolean, jsonb), public.report_demo(text, text, jsonb),
    public.object_to_report(uuid, text, jsonb), public.admin_objections(),
    public.admin_decide_objection(uuid, boolean, boolean), public.admin_reviews(),
    public.admin_review_report(uuid, boolean)
    from public, anon;
grant execute on function public.register_device(uuid), public.matching_status(),
    public.report_partner(uuid, text, text, boolean, jsonb), public.report_demo(text, text, jsonb),
    public.object_to_report(uuid, text, jsonb), public.admin_objections(),
    public.admin_decide_objection(uuid, boolean, boolean), public.admin_reviews(),
    public.admin_review_report(uuid, boolean)
    to authenticated;

notify pgrst, 'reload schema';
commit;
