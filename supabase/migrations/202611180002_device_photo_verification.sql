-- Stop Swiping: photo verification on the phone during the beta.
--
-- Runs after 202611180001_security_hardening.sql.
--
-- The app verifies the matching photo with its own live scan (Apple Vision +
-- SFace, all on the phone) instead of AWS Face Liveness. The phone reports a
-- match here and this function records the exact stored version of the
-- selected photo, just like the AWS worker did. Matching keeps using
-- matching_private.has_verified_photo unchanged, so both kinds count.
--
-- Trade-off: the server takes the app's word for the scan. A modified client
-- could call this without scanning. Accepted for the beta; AWS (server-proven)
-- is parked, see docs/aws-photo-verification.md.
--
-- Reactivating AWS later: revoke execute on this function from authenticated
-- (or drop it) and, to make everyone verify again with AWS, run
--     delete from matching_private.photo_verifications where method = 'device';
begin;

alter table matching_private.photo_verifications
    add column method text not null default 'aws' check (method in ('aws', 'device'));

create function public.record_device_photo_verification(p_photo_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); object storage.objects%rowtype;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    perform pg_catalog.pg_advisory_xact_lock(hashtextextended('photo-verification:' || uid::text, 0));
    -- The same daily bound as AWS checks: each record re-runs matching.
    if (select count(*) from matching_private.verification_attempts
        where user_id = uid and created_at > now() - interval '1 day') >= 5 then
        raise exception 'Daily verification limit reached'; end if;
    if not exists (select 1 from public.profiles where id = uid
        and lower(backup #>> '{state,storedAutoMatching,photoID}') = p_photo_id::text
        and backup #>> '{state,profilePrivacyConsent,version}' = '2026-11-15.v2') then
        raise exception 'Selected photo unavailable'; end if;
    select * into object from storage.objects
        where bucket_id = 'profile-photos' and name = uid::text || '/' || p_photo_id::text || '.jpg';
    if not found then raise exception 'Photo upload must finish first'; end if;

    -- Kept as an attempt, so the overview and the daily bound see it.
    insert into matching_private.verification_attempts(user_id, photo_id, object_id, object_updated_at,
            consent_version, status, completed_at)
        values (uid, p_photo_id, object.id, object.updated_at, 'device.v1', 'verified', now());
    insert into matching_private.photo_verifications(object_id, object_updated_at, method)
        values (object.id, object.updated_at, 'device') on conflict (object_id) do update
            set object_updated_at = excluded.object_updated_at, verified_at = now(), method = 'device';
    perform matching_private.try_match(uid);
    return true;
end; $$;

revoke all on function public.record_device_photo_verification(uuid) from public, anon;
grant execute on function public.record_device_photo_verification(uuid) to authenticated;

commit;
