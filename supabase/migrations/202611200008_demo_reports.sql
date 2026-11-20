-- Stop Swiping: reporting the demo match (decided 20 November 2026).
-- DEPLOYED 2026-11-20. Runs after 202611200007_report_objections.sql.
-- Tests: supabase/tests/demo_reports.sql.
--
-- An administrator can report the demo match to try the whole moderation
-- flow on their own account: the warning on the home screen, the objection
-- and, as administrator, deciding that objection.
--
-- 1. A demo report is a report against the reporter themself, with no match
--    (match_id null, is_demo true). Only administrators can file one.
-- 2. It shows like a first report: the warning, the reason, "Object". It
--    never counts towards a 7-day block or a ban, whatever else is on the
--    account, and it never proves an age for a later real report.
-- 3. One demo report at a time: a new one withdraws the previous one (and an
--    undecided objection to it), so the warning shows again.
-- 4. An objection to a demo report reaches the administrators' list as
--    usual, marked as a demo, but without a push (pushes belong to a match).
begin;

-- ===== 1. Demo reports ====================================================

alter table public.match_reports add column is_demo boolean not null default false;
alter table public.match_reports alter column match_id drop not null;
alter table public.match_reports add constraint match_reports_match_or_demo
    check (match_id is not null or is_demo);
comment on column public.match_reports.is_demo is
    'An administrator reported the demo match: a report against themself, with no match. Never blocks or bans.';

create function public.report_demo(p_reason text, p_details text, p_chat_copy jsonb default null) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    if not matching_private.is_admin(uid) then raise exception 'Administrators only' using errcode = '42501'; end if;
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    -- The previous demo report goes, with an objection still waiting on it.
    delete from matching_private.report_objections o using public.match_reports r
        where r.id = o.report_id and r.is_demo and r.reporter_id = uid and r.dismissed_at is null
            and o.decision is null;
    update public.match_reports set dismissed_at = now()
        where is_demo and reporter_id = uid and dismissed_at is null;
    update matching_private.moderation_notices_seen
        set strikes_seen = least(strikes_seen, (matching_private.moderation_state(uid)->>'strikes')::integer)
        where user_id = uid;
    insert into public.match_reports(match_id, reporter_id, reported_id, reported_identities, reason, details,
        ended_match, counts_as_strike, chat_copy, is_demo)
    values (null, uid, uid, matching_private.identity_hashes(uid), p_reason, coalesce(p_details, ''), false, true,
        case when jsonb_typeof(p_chat_copy) = 'array' and jsonb_array_length(p_chat_copy) > 0 then p_chat_copy end,
        true);
end;
$$;

-- ===== 2. Strikes: a demo report shows, but never locks ====================

-- As in 202611200007, with demo reports counted for the notice and the
-- newest report, and left out of the numbering for a block or a ban.
create or replace function matching_private.moderation_state(uid uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
    with me as (select matching_private.identity_hashes(uid) as hashes),
    shown as (
        select r.id, r.reason, r.created_at, r.is_demo
        from public.match_reports r, me
        where r.counts_as_strike and r.dismissed_at is null and r.reported_identities && me.hashes),
    strikes as (
        select s.created_at, row_number() over (order by s.created_at, s.id) as n
        from shown s where not s.is_demo)
    select jsonb_build_object(
        'strikes', (select count(*) from shown),
        'banned', exists (select 1 from strikes where n >= 3),
        'suspended_until', (select created_at + interval '7 days' from strikes where n = 2
            and not exists (select 1 from strikes where n >= 3)),
        'strikes_seen', coalesce((select strikes_seen from matching_private.moderation_notices_seen where user_id = uid), 0),
        'latest_report', (select jsonb_build_object('id', s.id, 'reason', s.reason, 'created_at', s.created_at,
                'is_demo', s.is_demo,
                'objection', (select coalesce(o.decision, 'pending') from matching_private.report_objections o
                    where o.report_id = s.id))
            from shown s order by s.created_at desc, s.id desc limit 1),
        'objection_result', (select jsonb_build_object('id', o.id, 'decision', o.decision, 'reason', r.reason)
            from matching_private.report_objections o join public.match_reports r on r.id = o.report_id
            where o.user_id = uid and o.decision is not null and o.result_seen_at is null
            order by o.decided_at desc limit 1));
$$;

-- A demo objection proves nothing for a real report.
create or replace function matching_private.age_proven_before(p_identities text[], p_except uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select exists (select 1 from matching_private.report_objections o
        join public.match_reports r on r.id = o.report_id
        where o.decided_automatically and r.reason = 'underage' and o.report_id <> p_except
            and not r.is_demo and r.reported_identities && p_identities);
$$;

-- ===== 3. Objections: no push for a demo report ============================

-- As in 202611200007; only the administrators' push now skips demo reports.
create or replace function public.object_to_report(p_report_id uuid, p_message text, p_id_check jsonb default null) returns void
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

    -- Administrators hear only about objections they must decide. A demo
    -- report has no match to hang a push on; it shows in their list only.
    if not r.is_demo then
        insert into notification_private.outbox(user_id, kind, match_id, detail)
            select a.user_id, 'moderation_report', r.match_id, r.reason from matching_private.admins a
            on conflict do nothing;
    end if;
end;
$$;

-- ===== 4. Administrators see which objection is a demo =====================

-- As in 202611200007, with "is_demo" on the report; a demo report is always
-- a first warning, and real strikes leave demo reports out.
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
            'report', jsonb_build_object(
                'id', r.id,
                'reason', r.reason,
                'details', r.details,
                'created_at', r.created_at,
                'chat_copy', r.chat_copy,
                'ended_match', r.ended_match,
                'is_demo', r.is_demo,
                -- 1 warning, 2 a 7-day block, 3 or more a ban.
                'strike', case when r.is_demo then 1 else (select count(*) from public.match_reports s
                    where s.counts_as_strike and s.dismissed_at is null and not s.is_demo
                        and s.reported_identities && r.reported_identities
                        and (s.created_at, s.id) <= (r.created_at, r.id)) end))
            order by o.created_at)
        from matching_private.report_objections o
        join public.match_reports r on r.id = o.report_id
        left join public.profiles pr on pr.id = o.user_id
        where o.decision is null), '[]'::jsonb);
end;
$$;

-- ===== 5. Privileges ======================================================

revoke all on function matching_private.moderation_state(uuid), matching_private.age_proven_before(text[], uuid)
    from public, anon, authenticated;
revoke all on function public.report_demo(text, text, jsonb), public.object_to_report(uuid, text, jsonb),
    public.admin_objections() from public, anon;
grant execute on function public.report_demo(text, text, jsonb), public.object_to_report(uuid, text, jsonb),
    public.admin_objections() to authenticated;

notify pgrst, 'reload schema';
commit;
