-- Stop Swiping: security hardening from the 18 November 2026 review.
--
-- Runs after 202611160004_privacy_consent_v2.sql and does not depend on the
-- push (002) or partner photo (003) migrations.
--
-- 1. Profiles had no size limit. Any signed-in account could store megabytes
--    of JSON per write, and every write runs the matching trigger under the
--    global matching lock. The limits are about twenty times the largest real
--    row (profile 5.8 kB, backup 12.4 kB on 18 November 2026).
-- 2. The updated_at trigger function was executable by anon and
--    authenticated through PostgreSQL's default PUBLIC grant. It does nothing
--    outside a trigger, but nothing outside the database needs to call it.
begin;

alter table public.profiles
    add constraint profiles_profile_size check (octet_length(profile::text) <= 131072),
    add constraint profiles_backup_size check (backup is null or octet_length(backup::text) <= 262144);

revoke all on function public.set_profile_updated_at() from public, anon, authenticated;

commit;
