-- Push notifications: device registration, the outbox triggers, message
-- batching, cancellation by reading and by breaking, and dispatch claims.
-- Run as postgres in the Supabase SQL Editor after
-- 202611160002_push_notifications.sql ("Run without RLS" is fine):
-- everything rolls back.
--
-- now() is fixed for a whole transaction, so time passing is simulated by
-- moving stored timestamps instead.
begin;
create temporary table push_results(name text primary key);
grant select, insert on push_results to authenticated;
create function pg_temp.ok(passed boolean, label text) returns void
language plpgsql as $$ begin
    if passed is distinct from true then raise exception 'FAILED: %', label; end if;
    insert into push_results values(label);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
    select ('a7fc0000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.as_user(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', pg_temp.id(n)::text, true), set_config('role', 'authenticated', true) $$;
create function pg_temp.as_admin() returns void language sql as $$
    select set_config('role', 'postgres', true) $$;
create function pg_temp.pending(n integer, k text) returns setof notification_private.outbox language sql as $$
    select * from notification_private.outbox where user_id = pg_temp.id(n) and kind = k
        and claimed_at is null and sent_at is null $$;
create function pg_temp.message(m uuid, sender integer) returns bigint language sql as $$
    insert into public.encrypted_messages(match_id, sender_id, client_message_id, sender_device_id,
        recipient_device_id, ciphertext, protocol_version)
    values (m, pg_temp.id(sender), gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'opaque', 'hpke-auth-x25519-v1')
    returning id $$;

insert into auth.users(id, aud, role) select pg_temp.id(n), 'authenticated', 'authenticated' from generate_series(1, 4) n;
-- Only a name: stays backed up, never enters the matching pool.
insert into public.profiles(id, profile) values (pg_temp.id(2), '{"displayName":"Alex"}');

-- ===== Matches ============================================================
create temporary table push_matches(name text primary key, id uuid);
with m as (insert into public.matches(user_low, user_high, score_low, score_high)
    values (pg_temp.id(1), pg_temp.id(3), 80, 80) returning id)
insert into push_matches select 'earlier', id from m;
select pg_temp.ok((select count(*) from pg_temp.pending(1, 'first_match')) = 1
    and (select count(*) from pg_temp.pending(3, 'first_match')) = 1, 'A first match is announced as the first');

update public.matches set ended_at = now(), ended_by = pg_temp.id(1), end_reason = 'broken'
    where id = (select id from push_matches where name = 'earlier');
select pg_temp.ok(not exists (select 1 from pg_temp.pending(1, 'first_match'))
    and not exists (select 1 from pg_temp.pending(3, 'first_match')), 'Ending a match cancels its unsent match pushes');
select pg_temp.ok((select count(*) from pg_temp.pending(3, 'match_ended')) = 1, 'The other side hears the match ended');
select pg_temp.ok(not exists (select 1 from pg_temp.pending(1, 'match_ended')), 'The one who ended it hears nothing');

with m as (insert into public.matches(user_low, user_high, score_low, score_high)
    values (pg_temp.id(1), pg_temp.id(2), 85, 90) returning id)
insert into push_matches select 'current', id from m;
select pg_temp.ok((select count(*) from pg_temp.pending(1, 'match_new')) = 1, 'A later match is a plain new match');
select pg_temp.ok((select count(*) from pg_temp.pending(2, 'first_match')) = 1, 'The partner''s first match is their first');

-- ===== Message batching ===================================================
select pg_temp.message((select id from push_matches where name = 'current'), 2) from generate_series(1, 3);
select pg_temp.ok((select count(*) from pg_temp.pending(1, 'message_new')) = 1, 'A burst of messages is one pending push');
select pg_temp.ok((select message_count from pg_temp.pending(1, 'message_new')) = 3, 'The pending push counts the burst');
select pg_temp.ok((select last_message_id from pg_temp.pending(1, 'message_new'))
    = (select max(id) from public.encrypted_messages where sender_id = pg_temp.id(2)), 'The pending push covers the newest message');
select pg_temp.ok((select not_before from pg_temp.pending(1, 'message_new')) >= now() + interval '15 seconds',
    'The push waits for the burst to settle');
select pg_temp.ok(not exists (select 1 from pg_temp.pending(2, 'message_new')), 'The sender gets no push');

-- A burst that keeps going is still sent within two minutes of its start.
update notification_private.outbox set created_at = now() - interval '110 seconds'
    where user_id = pg_temp.id(1) and kind = 'message_new' and sent_at is null;
select pg_temp.message((select id from push_matches where name = 'current'), 2);
select pg_temp.ok((select not_before from pg_temp.pending(1, 'message_new')) < now() + interval '15 seconds',
    'A long burst is not held back forever');

-- ===== Reading cancels ====================================================
insert into public.match_read_states(match_id, user_id, last_read_message_id)
    values ((select id from push_matches where name = 'current'), pg_temp.id(1),
            (select max(id) from public.encrypted_messages where sender_id = pg_temp.id(2)));
select pg_temp.ok(not exists (select 1 from pg_temp.pending(1, 'message_new')), 'Reading in time cancels the push');

-- ===== One push per thread gap ============================================
insert into notification_private.outbox(user_id, kind, match_id, sent_at, claimed_at, outcome)
    values (pg_temp.id(1), 'message_new', (select id from push_matches where name = 'current'),
            now() - interval '1 minute', now() - interval '1 minute', 'sent');
select pg_temp.message((select id from push_matches where name = 'current'), 2);
select pg_temp.ok((select not_before from pg_temp.pending(1, 'message_new')) >= now() + interval '2 minutes',
    'A rapid conversation waits for the thread gap');

-- ===== Devices ============================================================
select pg_temp.as_user(1);
select public.register_push_device(pg_temp.id(101), repeat('ab', 32), 'sandbox', 'Europe/Brussels',
    true, true, false, 22, 9);
select pg_temp.as_admin();
select pg_temp.ok((select user_id from public.push_devices where device_id = pg_temp.id(101)) = pg_temp.id(1),
    'A device registers for its own account');
select pg_temp.as_user(1);
select public.register_push_device(pg_temp.id(101), repeat('ab', 32), 'sandbox', 'Not/AZone', true, false, false,
    null, null, 'nl');
select pg_temp.as_admin();
select pg_temp.ok((select time_zone = 'UTC' and not previews and quiet_start is null and language = 'nl'
    from public.push_devices where device_id = pg_temp.id(101)),
    'Re-registering updates preferences and language; an unknown zone falls back to UTC');
select pg_temp.as_user(1);
select public.register_push_device(pg_temp.id(101), repeat('ab', 32), 'sandbox', 'UTC', true, false, false,
    null, null, 'xx');
select pg_temp.as_admin();
select pg_temp.ok((select language from public.push_devices where device_id = pg_temp.id(101)) = 'en',
    'An unsupported language falls back to English');

-- The same phone signs in to another account: the token moves with it.
select pg_temp.as_user(4);
select public.register_push_device(pg_temp.id(104), repeat('ab', 32), 'sandbox', 'UTC', true, true, false);
select pg_temp.as_admin();
select pg_temp.ok((select count(*) from public.push_devices where token = repeat('ab', 32)) = 1
    and (select user_id from public.push_devices where token = repeat('ab', 32)) = pg_temp.id(4),
    'A token belongs to the last account that registered it');

select pg_temp.as_user(1);
select public.register_push_device(pg_temp.id(101), repeat('cd', 32), 'sandbox', 'UTC', true, true, false,
    extract(hour from now() at time zone 'UTC')::integer, ((extract(hour from now() at time zone 'UTC')::integer + 1) % 24), 'nl');
select pg_temp.as_admin();

-- ===== Dispatch ===========================================================
update notification_private.outbox set not_before = now() - interval '1 second' where sent_at is null;
create temporary table push_claimed as select jsonb_array_elements(public.push_claim_due(100)) as entry;
select pg_temp.ok(exists (select 1 from push_claimed where entry->>'kind' = 'message_new'
    and entry->>'token' = repeat('cd', 32) and (entry->>'count')::integer = 1), 'A due message push is claimed with its unread count');
select pg_temp.ok((select entry->>'partner_name' from push_claimed where entry->>'kind' = 'message_new') = 'Alex',
    'With previews on, the sender''s name is included');
select pg_temp.ok((select entry->>'language' from push_claimed where entry->>'kind' = 'message_new') = 'nl',
    'The claim carries the device''s language');
select pg_temp.ok((select (entry->>'quiet')::boolean from push_claimed where entry->>'kind' = 'message_new'),
    'Quiet hours are computed in the device''s time zone');
select pg_temp.ok(not exists (select 1 from push_claimed where entry::text like '%ciphertext%' or entry::text like '%opaque%'),
    'No message content ever reaches the sender');
select pg_temp.ok((select outcome from notification_private.outbox where user_id = pg_temp.id(3) and kind = 'match_ended')
    = 'no_device', 'Rows for people without a phone are closed, not retried');
select pg_temp.ok(not exists (select 1 from push_claimed where entry->>'kind' = 'first_match' and entry->>'match_id'
    = (select id from push_matches where name = 'current')::text and entry->>'token' = repeat('ab', 32)),
    'Nobody receives another account''s pushes');

select public.push_complete((select (entry->>'outbox_id')::bigint from push_claimed where entry->>'kind' = 'message_new'), '503', true);
select pg_temp.ok((select claimed_at is null and sent_at is null and not_before > now() from notification_private.outbox
    where id = (select (entry->>'outbox_id')::bigint from push_claimed where entry->>'kind' = 'message_new')),
    'A failed send is retried later');
select public.push_revoke_token(repeat('cd', 32));
select pg_temp.ok((select revoked_at is not null from public.push_devices where device_id = pg_temp.id(101)),
    'A token APNs rejects is revoked');

-- ===== Breaking the current match =========================================
update notification_private.outbox set not_before = now() + interval '1 minute' where sent_at is null;
select pg_temp.message((select id from push_matches where name = 'current'), 1);
update public.matches set ended_at = now(), ended_by = pg_temp.id(2), end_reason = 'broken'
    where id = (select id from push_matches where name = 'current');
select pg_temp.ok(not exists (select 1 from notification_private.outbox where match_id = (select id from push_matches
    where name = 'current') and kind = 'message_new' and claimed_at is null and sent_at is null),
    'Breaking a match stops its pending message pushes');
select pg_temp.ok((select count(*) from pg_temp.pending(1, 'match_ended')) = 1
    and not exists (select 1 from pg_temp.pending(2, 'match_ended')), 'Only the partner of the one who broke it is told');

-- ===== Access =============================================================
select pg_temp.ok(not has_function_privilege('authenticated', 'public.push_claim_due(integer)', 'execute')
    and not has_function_privilege('anon', 'public.push_claim_due(integer)', 'execute')
    and not has_function_privilege('authenticated', 'public.push_complete(bigint,text,boolean)', 'execute')
    and not has_function_privilege('authenticated', 'public.push_revoke_token(text)', 'execute'),
    'Only the service role dispatches');
select pg_temp.ok(has_function_privilege('authenticated',
    'public.register_push_device(uuid,text,text,text,boolean,boolean,boolean,integer,integer,text)', 'execute')
    and not has_function_privilege('anon',
    'public.register_push_device(uuid,text,text,text,boolean,boolean,boolean,integer,integer,text)', 'execute'),
    'Signed-in users register their own phone');
select pg_temp.ok(not has_table_privilege('authenticated', 'public.push_devices', 'select')
    and not has_table_privilege('anon', 'public.push_devices', 'select'), 'Nobody reads device tokens directly');
select pg_temp.ok((select relrowsecurity from pg_class where oid = 'public.push_devices'::regclass), 'push_devices has RLS');

select name, 'PASS' as result, count(*) over () as total_passed from push_results order by name;
rollback;
