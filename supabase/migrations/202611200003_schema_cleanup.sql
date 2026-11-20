-- Stop Swiping: pre-launch schema cleanup (20 November 2026).
-- DEPLOYED 2026-11-20. Runs after 202611200002_matching_only_profiles.sql.
--
-- The live database holds no messages or profiles yet, so leftovers that
-- only existed for rows from before launch can go now:
--
-- 1. Chat envelopes accept only the protocol the app speaks
--    (hpke-auth-x25519-v1). The legacy 'e2ee-v1' value was kept for transport
--    rows from November's first builds; there are none.
-- 2. The 32 kB envelope bound (202611190001) and the 400-character name
--    bound (202611200001) were added NOT VALID so old rows stayed readable.
--    With no old rows they are validated, so every row is known to meet them.
--
-- If a VALIDATE fails, a row breaks the bound: nothing changes (one
-- transaction). Check it with the queries in the comments below.
begin;

alter table public.encrypted_messages drop constraint if exists encrypted_messages_protocol_version_check;
alter table public.encrypted_messages
    add constraint encrypted_messages_protocol_version_check check (protocol_version = 'hpke-auth-x25519-v1');

-- select count(*) from public.encrypted_messages where octet_length(ciphertext) > 32768;
alter table public.encrypted_messages validate constraint encrypted_messages_ciphertext_size;
-- select count(*) from public.profiles where char_length(coalesce(profile->>'displayName', '')) > 400;
alter table public.profiles validate constraint profiles_display_name_length;

commit;
