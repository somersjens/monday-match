-- Stop Swiping: photo scan limits per route, and a five-year end date for
-- what keeps two people apart (decided 20 November 2026).
-- DEPLOYED 2026-11-20. Runs after 202611200003_schema_cleanup.sql.
-- Tests: supabase/tests/scan_limits_and_five_years.sql.
--
-- 1. The daily limit of 5 belongs to AWS Face Liveness, where every session
--    costs money. A scan on the phone (unproven, or proven with App Attest)
--    no longer has one during the beta. What the limit also protected was
--    the matching lock (every record re-ran matching at once); a scan now
--    goes through request_search, the same one-search-per-minute rule as a
--    profile save. AWS counts only its own attempts, so phone scans never
--    use up the AWS allowance. The Data API's 120 writes a minute still
--    bound the unproven route.
-- 2. Five years after a match ended, the match row goes, and with it both
--    identity hashes, so those two people could be matched again. Five years
--    after a report was filed, the report goes, and with it its strike, so a
--    ban ends then too. A match is kept while a report about it remains.
--    Runs in the existing daily job purge-expired-data (03:17 UTC).
begin;

-- ===== 1. Scan limits ======================================================

create or replace function matching_private.record_photo_scan(uid uuid, p_photo_id uuid, p_attested boolean) returns boolean
language plpgsql security definer set search_path = '' as $$
declare object storage.objects%rowtype;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    perform pg_catalog.pg_advisory_xact_lock(hashtextextended('photo-verification:' || uid::text, 0));
    if not exists (select 1 from public.profiles where id = uid
        and lower(backup #>> '{state,storedAutoMatching,photoID}') = p_photo_id::text
        and backup #>> '{state,profilePrivacyConsent,version}' = '2026-11-15.v2') then
        raise exception 'Selected photo unavailable'; end if;
    select * into object from storage.objects
        where bucket_id = 'profile-photos' and name = uid::text || '/' || p_photo_id::text || '.jpg';
    if not found then raise exception 'Photo upload must finish first'; end if;

    insert into matching_private.verification_attempts(user_id, photo_id, object_id, object_updated_at,
            consent_version, status, completed_at)
        values (uid, p_photo_id, object.id, object.updated_at,
            case when p_attested then 'device.attested.v1' else 'device.v1' end, 'verified', now());
    insert into matching_private.photo_verifications(object_id, object_updated_at, method, attested)
        values (object.id, object.updated_at, 'device', p_attested) on conflict (object_id) do update
            set object_updated_at = excluded.object_updated_at, verified_at = now(), method = 'device',
                attested = excluded.attested;
    -- At most one search a minute, like a profile save.
    perform matching_private.request_search(uid);
    return true;
end; $$;
revoke all on function matching_private.record_photo_scan(uuid, uuid, boolean) from public, anon, authenticated;

-- AWS (parked): 5 sessions a day, counting AWS sessions only.
create or replace function public.begin_photo_verification(p_photo_id uuid,p_consent_version text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); object storage.objects%rowtype; attempt matching_private.verification_attempts%rowtype;
begin
    if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
    if p_consent_version is distinct from '2026-11-14.aws.v1' then raise exception 'AWS verification consent required'; end if;
    perform pg_catalog.pg_advisory_xact_lock(hashtextextended('photo-verification:'||uid::text,0));
    if (select count(*) from matching_private.verification_attempts where user_id=uid
        and consent_version like '%.aws.%' and created_at>now()-interval '1 day')>=5 then
        raise exception 'Daily verification limit reached'; end if;
    if not exists(select 1 from public.profiles where id=uid
        and lower(backup #>> '{state,storedAutoMatching,photoID}')=p_photo_id::text
        and backup #>> '{state,profilePrivacyConsent,version}'='2026-11-15.v2') then
        raise exception 'Selected photo unavailable'; end if;
    select * into object from storage.objects where bucket_id='profile-photos' and name=uid::text||'/'||p_photo_id::text||'.jpg';
    if not found then raise exception 'Photo upload must finish first'; end if;
    insert into matching_private.verification_attempts(user_id,photo_id,object_id,object_updated_at,consent_version)
        values(uid,p_photo_id,object.id,object.updated_at,p_consent_version) returning * into attempt;
    return jsonb_build_object('request_id',attempt.id,'expires_at',attempt.expires_at);
end; $$;

-- ===== 2. Five years ======================================================

create or replace function matching_private.purge_expired() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare cutoff timestamptz := now() - interval '12 months';
        five_years timestamptz := now() - interval '5 years';
begin
    delete from public.encrypted_messages where created_at < cutoff;
    delete from public.match_cards c using public.matches m where m.id = c.match_id and m.ended_at < cutoff;
    delete from public.match_key_bundles k using public.matches m where m.id = k.match_id and m.ended_at < cutoff;
    delete from public.match_read_states r using public.matches m where m.id = r.match_id and m.ended_at < cutoff;
    update public.match_reports set details = '' where created_at < cutoff and details <> '';
    delete from matching_private.verification_attempts where created_at < cutoff;

    -- Reports, and with them their strikes, five years after they were filed.
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
revoke all on function matching_private.purge_expired() from public, anon, authenticated;

commit;
