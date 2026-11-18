-- Stop Swiping: 12-month retention and keyed sign-in identity hashes.
--
-- Runs after 202611180001_security_hardening.sql. Independent of
-- 202611180002_device_photo_verification.sql.
--
-- 1. Sign-in identities were stored as plain sha256(provider:subject). A
--    Google subject is the same in every app, so anyone holding a subject
--    could recompute the hash and find that person's matches and reports.
--    They are now HMAC-SHA256 with a secret key kept in Supabase Vault.
--    On 18 November 2026 no stored hash existed yet (pool, match identities
--    and reports were empty), so nothing needed rehashing. Never rotate or
--    delete the key without rehashing every stored identity: "never again"
--    pairs and strikes depend on it.
--
-- 2. Retention, run daily by pg_cron:
--    - every chat message 12 months after it was sent, also when the match
--      has been broken (the app says so above each conversation);
--    - a match that ended more than 12 months ago keeps no profile cards,
--      chat keys or read positions; the match row itself stays, because
--      matching uses it so the same two people are never matched again;
--    - a report's written explanation 12 months after it was filed. The
--      strike (reason, date, hashed identities) stays, so a block or ban
--      keeps counting;
--    - photo verification attempts after 12 months.
begin;

-- ===== 1. Keyed identity hashes ===========================================

select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'identity_hash_key',
    'HMAC key for matching_private.identity_hashes. Never rotate without rehashing stored identities.')
where not exists (select 1 from vault.secrets where name = 'identity_hash_key');

create or replace function matching_private.identity_hashes(uid uuid) returns text[]
language plpgsql stable security definer set search_path = '' as $$
declare k text;
begin
    select decrypted_secret into k from vault.decrypted_secrets where name = 'identity_hash_key';
    -- Without the key every identity would look new: fail loudly instead.
    if k is null then raise exception 'Vault secret identity_hash_key is missing'; end if;
    return coalesce((select array_agg(distinct encode(extensions.hmac(i.provider || ':' || i.provider_id, k, 'sha256'), 'hex'))
                     from auth.identities i where i.user_id = uid), array[]::text[])
        || array['account:' || uid::text];
end;
$$;
revoke all on function matching_private.identity_hashes(uuid) from public, anon, authenticated;

-- ===== 2. Retention =======================================================

create function matching_private.purge_expired() returns void
language plpgsql volatile security definer set search_path = '' as $$
declare cutoff timestamptz := now() - interval '12 months';
begin
    delete from public.encrypted_messages where created_at < cutoff;
    delete from public.match_cards c using public.matches m where m.id = c.match_id and m.ended_at < cutoff;
    delete from public.match_key_bundles k using public.matches m where m.id = k.match_id and m.ended_at < cutoff;
    delete from public.match_read_states r using public.matches m where m.id = r.match_id and m.ended_at < cutoff;
    update public.match_reports set details = '' where created_at < cutoff and details <> '';
    delete from matching_private.verification_attempts where created_at < cutoff;
end;
$$;
revoke all on function matching_private.purge_expired() from public, anon, authenticated;

create extension if not exists pg_cron with schema pg_catalog;
-- Scheduling under an existing name replaces that job.
select cron.schedule('purge-expired-data', '17 3 * * *', 'select matching_private.purge_expired()');

commit;
