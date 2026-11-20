-- Stop Swiping: objections to reports (decided 20 November 2026).
-- DEPLOYED 2026-11-20. Runs after 202611200006_has_access_null_fix.sql.
-- Tests: supabase/tests/report_objections.sql.
--
-- 1. A report can carry a copy of the whole conversation. Messages are
--    end-to-end encrypted, so the copy is made on the reporter's phone, and
--    only when the reporter chooses to add it. Only an administrator reads it,
--    and only when the reported person objects. Cleared after 12 months, like
--    the written explanation.
-- 2. The reported person can always object to the newest report against
--    them, in their own words. For "may be under 18" they also prove their
--    age: the phone reads the machine-readable zone of a passport or ID card
--    and sends only the first initial, the birth date and the expiry date,
--    never the photo. The server compares them with the profile.
--    The first time a person proves their age this way and everything
--    matches (initial, birth date, 18+, check digits, not expired), the
--    objection is approved at once without an administrator. A second
--    "under 18" objection for the same person, or one whose check does not
--    match, goes to an administrator.
-- 3. Administrators (matching_private.admins) get a push for an objection
--    they must decide only. A report without an objection never reaches them.
-- 4. In the app an administrator approves an objection (the report is
--    withdrawn: its strike goes, and with it a block or ban it caused) or
--    rejects it (the report stands). The person sees the outcome on the
--    home screen.
begin;

-- ===== 1. A copy of the conversation with a report ========================

-- Oldest first: [{"from":"reporter"|"reported","at":"<ISO 8601>","text":"…"}].
alter table public.match_reports add column chat_copy jsonb
    check (chat_copy is null or (jsonb_typeof(chat_copy) = 'array' and octet_length(chat_copy::text) <= 262144));
comment on column public.match_reports.chat_copy is
    'The conversation as the reporter''s phone had it, if they chose to add it. Read by an administrator only for an objection.';

-- The reporter keeps reading their own reports (the app does not), but no
-- longer the conversation copy or the reported person's identity hashes.
revoke select on public.match_reports from authenticated;
grant select (id, match_id, reporter_id, reason, details, created_at, ended_match, reported_id,
    counts_as_strike, dismissed_at) on public.match_reports to authenticated;

drop function public.report_partner(uuid, text, text, boolean);
create function public.report_partner(p_match_id uuid, p_reason text, p_details text,
    p_break_match boolean default false, p_chat_copy jsonb default null) returns void
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
            ended_match, counts_as_strike, chat_copy)
        values (m.id, uid, partner,
            coalesce((select identity_hashes from matching_private.match_identities where match_id = m.id and user_id = partner),
                     matching_private.identity_hashes(partner)),
            p_reason, coalesce(p_details, ''), coalesce(p_break_match, false), counts,
            case when jsonb_typeof(p_chat_copy) = 'array' and jsonb_array_length(p_chat_copy) > 0 then p_chat_copy end);
    end if;
    if coalesce(p_break_match, false) then perform matching_private.end_match(m.id, 'reported', uid); end if;
    if counts then perform matching_private.apply_moderation(partner); end if;
end;
$$;

-- ===== 2. Objections ======================================================

create table matching_private.report_objections (
    id uuid primary key default gen_random_uuid(),
    -- One objection per report.
    report_id uuid not null unique references public.match_reports(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    message text not null check (length(message) <= 2000),
    -- "May be under 18" only: what the phone read from the document, and the
    -- server's comparison with the profile.
    id_check jsonb check (id_check is null or (jsonb_typeof(id_check) = 'object' and octet_length(id_check::text) <= 2048)),
    created_at timestamptz not null default now(),
    decision text check (decision in ('approved', 'rejected')),
    decided_at timestamptz,
    decided_by uuid references auth.users(id) on delete set null,
    -- Approved without an administrator: a first, fully matching age proof.
    decided_automatically boolean not null default false,
    -- The person has read the outcome on the home screen.
    result_seen_at timestamptz
);
create index report_objections_pending on matching_private.report_objections(created_at) where decision is null;
create index report_objections_user on matching_private.report_objections(user_id, decided_at desc);
alter table matching_private.report_objections enable row level security;
revoke all on matching_private.report_objections from public, anon, authenticated;

create function matching_private.is_admin(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select uid is not null and exists (select 1 from matching_private.admins where user_id = uid);
$$;

-- Strikes as before, plus what the home screen needs to explain the newest
-- one and offer an objection: its reason and the state of its objection,
-- and the outcome of a decided objection the person has not read yet.
create or replace function matching_private.moderation_state(uid uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
    with me as (select matching_private.identity_hashes(uid) as hashes),
    strikes as (
        select r.id, r.reason, r.created_at, row_number() over (order by r.created_at, r.id) as n
        from public.match_reports r, me
        where r.counts_as_strike and r.dismissed_at is null and r.reported_identities && me.hashes)
    select jsonb_build_object(
        'strikes', (select count(*) from strikes),
        'banned', exists (select 1 from strikes where n >= 3),
        'suspended_until', (select created_at + interval '7 days' from strikes where n = 2
            and not exists (select 1 from strikes where n >= 3)),
        'strikes_seen', coalesce((select strikes_seen from matching_private.moderation_notices_seen where user_id = uid), 0),
        'latest_report', (select jsonb_build_object('id', s.id, 'reason', s.reason, 'created_at', s.created_at,
                'objection', (select coalesce(o.decision, 'pending') from matching_private.report_objections o
                    where o.report_id = s.id))
            from strikes s order by s.n desc limit 1),
        'objection_result', (select jsonb_build_object('id', o.id, 'decision', o.decision, 'reason', r.reason)
            from matching_private.report_objections o join public.match_reports r on r.id = o.report_id
            where o.user_id = uid and o.decision is not null and o.result_seen_at is null
            order by o.decided_at desc limit 1));
$$;

-- Removes accents and case, so "Émile" and an MRZ's "EMILE" share an initial.
create function matching_private.initial_of(name text) returns text
language sql immutable set search_path = '' as $$
    select nullif(upper(left(translate(btrim(coalesce(name, '')),
        'ÀÁÂÃÄÅàáâãäåÇçÈÉÊËèéêëÌÍÎÏìíîïÑñÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÝýÿŠšŽž',
        'AAAAAAaaaaaaCcEEEEeeeeIIIIiiiiNnOOOOOOooooooUUUUuuuuYyySsZz'), 1)), '');
$$;

-- Withdraws an objected report: its strike goes, and a later report must
-- show as new again. The person may search again at once.
create function matching_private.withdraw_report(p_report_id uuid, p_user_id uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
    update public.match_reports set dismissed_at = now() where id = p_report_id and dismissed_at is null;
    update matching_private.moderation_notices_seen
        set strikes_seen = least(strikes_seen, (matching_private.moderation_state(p_user_id)->>'strikes')::integer)
        where user_id = p_user_id;
    perform matching_private.try_match(p_user_id);
end;
$$;

-- An "under 18" objection was approved automatically for this person (under
-- any of their sign-ins) before.
create function matching_private.age_proven_before(p_identities text[], p_except uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select exists (select 1 from matching_private.report_objections o
        join public.match_reports r on r.id = o.report_id
        where o.decided_automatically and r.reason = 'underage' and o.report_id <> p_except
            and r.reported_identities && p_identities);
$$;

-- The reported person objects to a report against them.
create function public.object_to_report(p_report_id uuid, p_message text, p_id_check jsonb default null) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r public.match_reports%rowtype; msg text := btrim(coalesce(p_message, ''));
    checked jsonb; doc_birth date; doc_expires date; doc_initial text; p public.profiles%rowtype;
    profile_birth date; inserted uuid;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    select * into r from public.match_reports
        where id = p_report_id and counts_as_strike and dismissed_at is null
            and reported_identities && matching_private.identity_hashes(uid);
    if not found then raise exception 'Report unavailable' using errcode = '42501'; end if;
    if length(msg) = 0 then raise exception 'Objection message required' using errcode = '22023'; end if;
    if length(msg) > 2000 then raise exception 'Objection message too long' using errcode = '22023'; end if;

    if r.reason = 'underage' then
        if jsonb_typeof(p_id_check) is distinct from 'object' then
            raise exception 'Proof of age required' using errcode = '22023'; end if;
        doc_initial := matching_private.initial_of(p_id_check->>'initial');
        begin
            doc_birth := (p_id_check->>'birth_date')::date;
            doc_expires := (p_id_check->>'expires')::date;
        exception when others then
            raise exception 'Proof of age unreadable' using errcode = '22023';
        end;
        if doc_initial is null or doc_initial !~ '^[A-Z]$' or doc_birth is null then
            raise exception 'Proof of age unreadable' using errcode = '22023'; end if;
        select * into p from public.profiles where id = uid;
        profile_birth := ((p.profile->>'dateOfBirth')::timestamptz at time zone 'UTC')::date;
        checked := jsonb_build_object(
            'initial', doc_initial,
            'birth_date', doc_birth,
            'expires', doc_expires,
            'document', left(coalesce(p_id_check->>'document', ''), 2),
            'check_digits', coalesce((p_id_check->>'check_digits')::boolean, false),
            'adult', doc_birth <= current_date - interval '18 years',
            'expired', doc_expires is not null and doc_expires < current_date,
            -- Against the profile on the server; null when it left matching.
            'profile_initial', matching_private.initial_of(p.profile->>'displayName'),
            'profile_birth_date', profile_birth,
            'initial_matches', case when p.id is null then null
                else matching_private.initial_of(p.profile->>'displayName') = doc_initial end,
            'birth_date_matches', case when profile_birth is null then null else profile_birth = doc_birth end);
    end if;

    insert into matching_private.report_objections(report_id, user_id, message, id_check)
        values (r.id, uid, msg, checked)
        on conflict (report_id) do nothing
        returning id into inserted;
    if inserted is null then raise exception 'Objection already made' using errcode = '23505'; end if;

    -- A first age proof where everything matches needs no administrator.
    if r.reason = 'underage'
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

    -- Administrators hear only about objections they must decide.
    insert into notification_private.outbox(user_id, kind, match_id, detail)
        select a.user_id, 'moderation_report', r.match_id, r.reason from matching_private.admins a
        on conflict do nothing;
end;
$$;

-- ===== 3. Plain reports no longer reach the administrators ================

drop trigger match_reports_notify_admins on public.match_reports;
drop function notification_private.on_report_filed();

-- ===== 4. Home screen: outcome read, administrator badge ==================

-- The person has seen the notice for their current number of strikes, and
-- the outcome of every decided objection.
create or replace function public.acknowledge_moderation() returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    insert into matching_private.moderation_notices_seen(user_id, strikes_seen)
        values (uid, (matching_private.moderation_state(uid)->>'strikes')::integer)
        on conflict (user_id) do update set strikes_seen = excluded.strikes_seen, seen_at = now();
    update matching_private.report_objections set result_seen_at = now()
        where user_id = uid and decision is not null and result_seen_at is null;
end;
$$;

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
            when exists (select 1 from matching_private.pool where user_id = uid) then 'waiting'
            when coalesce((p.profile->>'autoMatchingEnabled')::boolean, false) then 'ineligible'
            else 'disabled' end,
        'match_id', mid,
        'photo_verified', matching_private.has_verified_photo(uid, lower(p.backup #>> '{state,storedAutoMatching,photoID}')),
        'moderation', moderation,
        'is_admin', admin,
        'admin_pending', case when admin then
            (select count(*) from matching_private.report_objections where decision is null) else 0 end);
end;
$$;

-- ===== 5. Administrators decide =========================================

-- Every open objection, oldest first: the report (reason, explanation,
-- conversation copy) and then the objection.
create function public.admin_objections() returns jsonb
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
            'report', jsonb_build_object(
                'id', r.id,
                'reason', r.reason,
                'details', r.details,
                'created_at', r.created_at,
                'chat_copy', r.chat_copy,
                'ended_match', r.ended_match,
                -- 1 warning, 2 a 7-day block, 3 or more a ban.
                'strike', (select count(*) from public.match_reports s
                    where s.counts_as_strike and s.dismissed_at is null
                        and s.reported_identities && r.reported_identities
                        and (s.created_at, s.id) <= (r.created_at, r.id))))
            order by o.created_at)
        from matching_private.report_objections o
        join public.match_reports r on r.id = o.report_id
        left join public.profiles pr on pr.id = o.user_id
        where o.decision is null), '[]'::jsonb);
end;
$$;

-- Approve: the report is withdrawn, its strike goes, and the person may
-- search again at once. Reject: the report stands.
create function public.admin_decide_objection(p_objection_id uuid, p_approve boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); o matching_private.report_objections%rowtype;
begin
    if not matching_private.is_admin(uid) then raise exception 'Administrators only' using errcode = '42501'; end if;
    if p_approve is null then raise exception 'Decision required' using errcode = '22023'; end if;
    update matching_private.report_objections
        set decision = case when p_approve then 'approved' else 'rejected' end, decided_at = now(), decided_by = uid
        where id = p_objection_id and decision is null
        returning * into o;
    if not found then raise exception 'Objection already decided' using errcode = '23505'; end if;
    if p_approve then perform matching_private.withdraw_report(o.report_id, o.user_id); end if;
end;
$$;

-- ===== 6. Retention =======================================================

-- purge_expired from 202611200004, also clearing a report's conversation
-- copy and a decided objection's words and age check after 12 months.
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

    -- Reports, and with them their strikes and objections, five years after
    -- they were filed.
    delete from public.match_reports where created_at < five_years;
    -- Matches five years after they ended. Cascades: match_identities,
    -- match_cards, match_read_states, deleted_matches, the push outbox.
    -- Messages and keys are long gone (12 months) but are removed first in
    -- case a row is left; a match with a remaining report waits for it.
    delete from public.encrypted_messages e using public.matches m
        where m.id = e.match_id and m.ended_at < five_years;
    delete from public.match_key_bundles k using public.matches m
        where m.id = k.match_id and m.ended_at < five_years;
    delete from public.matches m where m.ended_at < five_years
        and not exists (select 1 from public.match_reports r where r.match_id = m.id);
end;
$$;

-- ===== 7. Privileges ======================================================

revoke all on function matching_private.is_admin(uuid), matching_private.initial_of(text),
    matching_private.withdraw_report(uuid, uuid), matching_private.age_proven_before(text[], uuid),
    matching_private.moderation_state(uuid), matching_private.purge_expired()
    from public, anon, authenticated;
revoke all on function public.report_partner(uuid, text, text, boolean, jsonb),
    public.object_to_report(uuid, text, jsonb), public.admin_objections(),
    public.admin_decide_objection(uuid, boolean), public.acknowledge_moderation(), public.matching_status()
    from public, anon;
grant execute on function public.report_partner(uuid, text, text, boolean, jsonb),
    public.object_to_report(uuid, text, jsonb), public.admin_objections(),
    public.admin_decide_objection(uuid, boolean), public.acknowledge_moderation(), public.matching_status()
    to authenticated;

notify pgrst, 'reload schema';
commit;
