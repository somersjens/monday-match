-- Stop Swiping: three launch rules (decided 20 November 2026).
-- DEPLOYED 2026-11-20. Runs after 202611200004_scan_limits_and_five_years.sql.
-- Tests: supabase/tests/launch_rules.sql. The older SQL tests switch the
-- access check off for their fixtures (stop_swiping.access_check = 'off').
--
-- 1. Only a proven photo scan counts. App Attest works on the iPhone
--    (20 November 2026), so the unproven route record_device_photo_verification
--    is closed to the app and unproven records go. Android reports through
--    Play Integrity before it launches. has_verified_photo also ignores any
--    unproven device record that might remain.
-- 2. Only someone who paid enters the matching pool. Access is a verified
--    store purchase on the account (store_entitlements, written only by the
--    store-entitlement edge function after checking Apple's signature): not
--    revoked, and for the monthly plan not expired. Sandbox (TestFlight)
--    purchases count while matching_private.settings 'sandbox_purchases_count'
--    is on; switch it off at launch:
--        update matching_private.settings set enabled = false where name = 'sandbox_purchases_count';
--    A purchase that arrives searches at once; a refund or lapse takes the
--    person out of the pool at once (or in the daily sweep, for a plan that
--    simply ran out). An active match is never ended by this.
-- 3. A new report pushes "New report: <reason>" to every administrator in
--    matching_private.admins, through the normal push pipeline (kind
--    moderation_report). The push carries the reason code only, never a name
--    or the explanation. Add an administrator in the SQL editor:
--        insert into matching_private.admins(user_id) values ('<auth user id>');
begin;

-- ===== 1. Only proven photo scans =========================================

revoke execute on function public.record_device_photo_verification(uuid) from authenticated;
delete from matching_private.photo_verifications where method = 'device' and not attested;

create or replace function matching_private.has_verified_photo(uid uuid, photo_id text) returns boolean
language sql stable security definer set search_path = '' as $$
    select exists (select 1 from storage.objects o
        join matching_private.photo_verifications v on v.object_id = o.id and v.object_updated_at = o.updated_at
        where o.bucket_id = 'profile-photos' and o.name = uid::text || '/' || photo_id || '.jpg'
            and (v.method <> 'device' or v.attested));
$$;

-- ===== 2. Only paying accounts in the pool ================================

create table matching_private.settings (
    name text primary key,
    enabled boolean not null,
    note text
);
alter table matching_private.settings enable row level security;
revoke all on matching_private.settings from public, anon, authenticated;
insert into matching_private.settings(name, enabled, note) values ('sandbox_purchases_count', true,
    'TestFlight (sandbox) purchases count as access during the beta. Switch off at launch.');

create function matching_private.has_access(uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
    select (current_setting('stop_swiping.access_check', true) = 'off' and session_user = 'postgres')
        or exists (select 1 from public.store_entitlements e
            where e.user_id = uid and e.revoked_at is null
                and (e.expires_at is null or e.expires_at > now())
                and (e.environment = 'production' or (e.environment = 'sandbox'
                    and coalesce((select s.enabled from matching_private.settings s
                        where s.name = 'sandbox_purchases_count'), false))));
$$;
revoke all on function matching_private.has_access(uuid) from public, anon, authenticated;

-- The pool entry from 202611160001, with the access check added.
create or replace function matching_private.pool_entry(uid uuid, p jsonb, b jsonb) returns matching_private.pool
language plpgsql stable security definer set search_path = '' as $$
declare r matching_private.pool;
begin
    if not matching_private.eligible(p, b) or not matching_private.has_access(uid) then return null; end if;
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

-- A purchase searches at once; a refund or lapse leaves the pool at once.
create function matching_private.entitlement_changed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    if matching_private.has_access(new.user_id) then
        if exists (select 1 from public.profiles where id = new.user_id) then
            perform matching_private.request_search(new.user_id);
        end if;
    else
        perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
        delete from matching_private.pool where user_id = new.user_id;
    end if;
    return null;
end;
$$;
revoke all on function matching_private.entitlement_changed() from public, anon, authenticated;
create trigger store_entitlements_access after insert or update on public.store_entitlements
    for each row execute function matching_private.entitlement_changed();

-- The daily sweep (job retention, 03:29 UTC) also takes out whoever lost access.
create or replace function matching_private.remove_dormant_from_pool() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare removed integer;
begin
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    delete from matching_private.pool c
        where matching_private.last_active(c.user_id) < now() - interval '6 months'
            or not matching_private.has_access(c.user_id);
    get diagnostics removed = row_count;
    return removed;
end;
$$;

-- ===== 3. Reports reach the administrators ================================

create table matching_private.admins (
    user_id uuid primary key references auth.users(id) on delete cascade,
    added_at timestamptz not null default now()
);
alter table matching_private.admins enable row level security;
revoke all on matching_private.admins from public, anon, authenticated;

alter table notification_private.outbox drop constraint if exists outbox_kind_check;
alter table notification_private.outbox add constraint outbox_kind_check
    check (kind in ('match_new', 'first_match', 'message_new', 'match_ended', 'moderation_report'));
-- moderation_report only: the report's reason code.
alter table notification_private.outbox add column detail text check (octet_length(detail) <= 64);

create function notification_private.on_report_filed() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
    insert into notification_private.outbox(user_id, kind, match_id, detail)
        select a.user_id, 'moderation_report', new.match_id, new.reason from matching_private.admins a
        on conflict do nothing;
    return null;
end;
$$;
revoke all on function notification_private.on_report_filed() from public, anon, authenticated;
create trigger match_reports_notify_admins after insert on public.match_reports
    for each row execute function notification_private.on_report_filed();

-- push_claim_due from 202611190010, passing a report's reason along.
create or replace function public.push_claim_due(p_limit integer default 100) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare result jsonb := '[]'::jsonb; item notification_private.outbox%rowtype; unread integer;
    m public.matches%rowtype; partner uuid; entries jsonb;
begin
    -- A sender that crashed mid-flight: release its claims after 5 minutes.
    update notification_private.outbox set claimed_at = null
        where sent_at is null and claimed_at < now() - interval '5 minutes' and attempts < 5;

    for item in
        update notification_private.outbox o set claimed_at = now(), attempts = attempts + 1
        where o.id in (select id from notification_private.outbox
            where sent_at is null and claimed_at is null and not_before <= now()
            order by not_before limit greatest(1, least(p_limit, 500)) for update skip locked)
        returning o.*
    loop
        select * into m from public.matches where id = item.match_id;
        partner := case when m.user_low = item.user_id then m.user_high else m.user_low end;
        unread := 0;
        if item.kind = 'message_new' then
            select count(*) into unread from public.encrypted_messages e
                where e.match_id = m.id and e.sender_id = partner
                and e.id > coalesce((select last_read_message_id from public.match_read_states
                    where match_id = m.id and user_id = item.user_id), 0);
        end if;
        if (item.kind in ('match_new', 'first_match', 'message_new') and m.ended_at is not null)
            or (item.kind = 'message_new' and unread = 0) then
            update notification_private.outbox set sent_at = now(), outcome = 'skipped' where id = item.id;
            continue;
        end if;

        select coalesce(jsonb_agg(jsonb_build_object(
                'outbox_id', item.id,
                'kind', item.kind,
                'match_id', item.match_id,
                'count', greatest(unread, 1),
                'detail', item.detail,
                'platform', d.platform,
                'token', d.token,
                'environment', d.environment,
                'language', d.language,
                -- The phone puts the name on the lock screen itself; the
                -- server only tells it whether the user wants that.
                'previews', d.previews,
                'visible', case when item.kind = 'match_ended' then d.match_ended_alerts and d.transactional
                    when item.kind = 'moderation_report' then true
                    else d.transactional end,
                'quiet', d.quiet_start is not null and (
                    case when d.quiet_start < d.quiet_end
                        then extract(hour from now() at time zone d.time_zone) >= d.quiet_start
                         and extract(hour from now() at time zone d.time_zone) < d.quiet_end
                        else extract(hour from now() at time zone d.time_zone) >= d.quiet_start
                          or extract(hour from now() at time zone d.time_zone) < d.quiet_end end))), '[]'::jsonb)
            into entries
            from public.push_devices d where d.user_id = item.user_id and d.revoked_at is null;

        if jsonb_array_length(entries) = 0 then
            update notification_private.outbox set sent_at = now(), outcome = 'no_device' where id = item.id;
            continue;
        end if;
        result := result || entries;
    end loop;
    return result;
end;
$$;
revoke all on function public.push_claim_due(integer) from public, anon, authenticated;
grant execute on function public.push_claim_due(integer) to service_role;

notify pgrst, 'reload schema';
commit;
