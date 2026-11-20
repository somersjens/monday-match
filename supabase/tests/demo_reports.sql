-- Reporting the demo match (202611200008). Run as postgres in the Supabase
-- SQL Editor ("Run without RLS" is fine): everything rolls back, and the last
-- line reports how many checks passed. The live admins table holds a real
-- account too, so nothing here assumes a single administrator.
begin;
set local stop_swiping.access_check = 'off';
set local stop_swiping.matching_throttle = 'off';
create temporary table demo_results(name text primary key);
grant select, insert on demo_results to authenticated;
create function pg_temp.ok(passed boolean, label text) returns void
language plpgsql as $$ begin
    if passed is distinct from true then raise exception 'FAILED: %', label; end if;
    insert into demo_results values(label);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
    select ('0de70000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function pg_temp.as_user(n integer) returns void language sql as $$
    select set_config('request.jwt.claim.sub', pg_temp.id(n)::text, true),
           set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.id(n), 'role', 'authenticated')::text, true),
           set_config('role', 'authenticated', true) $$;
create function pg_temp.as_postgres() returns void language sql as $$
    select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '{}', true),
           set_config('role', 'postgres', true) $$;
create function pg_temp.error_of(statement text) returns text
language plpgsql as $$ begin
    execute statement;
    return null;
exception when others then return sqlerrm;
end; $$;
grant execute on function pg_temp.ok(boolean, text), pg_temp.id(integer), pg_temp.error_of(text) to authenticated;
-- Security definer: a person may not read reports themselves.
create function pg_temp.demo_report(n integer) returns uuid language sql security definer as $$
    select id from public.match_reports where is_demo and reporter_id = pg_temp.id(n) and dismissed_at is null $$;
create function pg_temp.moderation(n integer) returns jsonb language sql security definer as $$
    select matching_private.moderation_state(pg_temp.id(n)) $$;
create function pg_temp.admin_pushes() returns bigint language sql as $$
    select count(*) from notification_private.outbox where kind = 'moderation_report' $$;
grant execute on function pg_temp.demo_report(integer), pg_temp.moderation(integer) to authenticated;

insert into auth.users(id, aud, role, last_sign_in_at)
    select pg_temp.id(n), 'authenticated', 'authenticated', now() from unnest(array[1, 2, 3, 9]) n;
-- The administrator: Ada, born 2 January 1990. Not in matching.
insert into public.profiles(id, profile, backup)
    values (pg_temp.id(9), '{"displayName":"Ada","dateOfBirth":"1990-01-02T12:00:00Z"}', '{}');
insert into matching_private.admins(user_id) values (pg_temp.id(9));
insert into public.matches(id, user_low, user_high, score_low, score_high) values
    (pg_temp.id(12), pg_temp.id(1), pg_temp.id(2), 80, 80),
    (pg_temp.id(13), pg_temp.id(1), pg_temp.id(9), 80, 80),
    (pg_temp.id(23), pg_temp.id(2), pg_temp.id(9), 80, 80),
    (pg_temp.id(33), pg_temp.id(3), pg_temp.id(9), 80, 80);

-- ===== 1. Only administrators ==============================================
select pg_temp.as_user(1);
select pg_temp.ok(pg_temp.error_of('select public.report_demo(''spam'', '''')') = 'Administrators only',
    'A person cannot report the demo match to the server');
select pg_temp.as_postgres();
select pg_temp.ok(not has_function_privilege('anon', 'public.report_demo(text, text, jsonb)', 'execute'),
    'nor can an anonymous caller');
select pg_temp.ok(pg_temp.error_of(format(
    'insert into public.match_reports(reporter_id, reason, details) values (%L, ''spam'', '''')', pg_temp.id(1)))
    like '%match_reports_match_or_demo%', 'A report without a match must be a demo');

-- ===== 2. The administrator reports the demo ===============================
select pg_temp.as_user(9);
select public.report_demo('harassment', 'Demo: test', '[{"from":"reported","at":"2026-11-20T10:00:00Z","text":"Hoi"}]');
create temporary table first_demo as select public.matching_status() as s;
select pg_temp.ok((select (s #>> '{moderation,strikes}')::integer = 1
    and (s #>> '{moderation,strikes_seen}')::integer = 0
    and s #>> '{moderation,latest_report,reason}' = 'harassment'
    and (s #>> '{moderation,latest_report,is_demo}')::boolean
    and s #> '{moderation,latest_report,objection}' = 'null'::jsonb from first_demo),
    'The demo report shows as a first warning against the administrator, with Object');
select pg_temp.ok((select s->>'state' not in ('banned', 'suspended') from first_demo), 'It locks nothing');
select pg_temp.as_postgres();
select pg_temp.ok((select reported_id = pg_temp.id(9) and match_id is null and counts_as_strike
        and jsonb_array_length(chat_copy) = 1 and not ended_match
    from public.match_reports where id = pg_temp.demo_report(9)), 'stored against themself, without a match');

-- Acknowledged, then a new demo report: the warning shows again, one at a time.
select pg_temp.as_user(9);
select public.acknowledge_moderation();
select pg_temp.ok((public.matching_status() #>> '{moderation,strikes_seen}')::integer = 1, 'Understood is remembered');
select public.report_demo('spam', '', null);
create temporary table second_demo as select public.matching_status() as s;
select pg_temp.ok((select (s #>> '{moderation,strikes}')::integer = 1
    and (s #>> '{moderation,strikes_seen}')::integer = 0
    and s #>> '{moderation,latest_report,reason}' = 'spam' from second_demo),
    'A new demo report replaces the previous one and shows as unread');
select pg_temp.as_postgres();
select pg_temp.ok((select count(*) = 2 and count(*) filter (where dismissed_at is null) = 1
    from public.match_reports where is_demo and reporter_id = pg_temp.id(9)), 'The previous one is withdrawn');

-- ===== 3. Objecting and deciding as administrator ==========================
create temporary table pushes_before as select pg_temp.admin_pushes() as n;
select pg_temp.as_user(9);
select public.object_to_report(pg_temp.demo_report(9), 'Dit klopt niet, test.');
select pg_temp.ok((public.matching_status() #>> '{moderation,latest_report,objection}') = 'pending',
    'The administrator can object to the demo report');
create temporary table listed as select public.admin_objections() as list;
select pg_temp.ok((select exists (select 1 from jsonb_array_elements(list) e
        where e #>> '{report,id}' = pg_temp.demo_report(9)::text and (e #>> '{report,is_demo}')::boolean
            and (e #>> '{report,strike}')::integer = 1 and e->>'message' = 'Dit klopt niet, test.') from listed),
    'and finds it in their list, marked as a demo');
select pg_temp.as_postgres();
select pg_temp.ok(pg_temp.admin_pushes() = (select n from pushes_before), 'A demo objection sends no push');

-- A replaced demo report takes its undecided objection with it.
select pg_temp.as_user(9);
select public.report_demo('fakeProfile', '', null);
select pg_temp.ok((select not exists (select 1 from jsonb_array_elements(public.admin_objections()) e
        where e->>'message' = 'Dit klopt niet, test.')), 'A new demo report clears the old objection');

-- Rejected: the demo report stands, still without a lock.
select public.object_to_report(pg_temp.demo_report(9), 'Bezwaar twee.');
select public.admin_decide_objection((select (e->>'id')::uuid from jsonb_array_elements(public.admin_objections()) e
    where e->>'message' = 'Bezwaar twee.'), false);
create temporary table rejected as select public.matching_status() as s;
select pg_temp.ok((select s #>> '{moderation,latest_report,objection}' = 'rejected'
    and s #>> '{moderation,objection_result,decision}' = 'rejected'
    and s->>'state' not in ('banned', 'suspended') from rejected), 'Rejected: the report stands, nothing locks');
-- Read on the home screen ("Understood"), as between two real decisions.
select public.acknowledge_moderation();

-- Approved: withdrawn.
select public.report_demo('other', '', null);
select public.object_to_report(pg_temp.demo_report(9), 'Bezwaar drie.');
select public.admin_decide_objection((select (e->>'id')::uuid from jsonb_array_elements(public.admin_objections()) e
    where e->>'message' = 'Bezwaar drie.'), true);
create temporary table approved as select public.matching_status() as s;
select pg_temp.ok((select (s #>> '{moderation,strikes}')::integer = 0 and s #> '{moderation,latest_report}' = 'null'::jsonb
    and s #>> '{moderation,objection_result,decision}' = 'approved' from approved),
    'Approved: the demo report is withdrawn');
select public.acknowledge_moderation();

-- "Under 18" with a matching document: approved at once, as for real, but it
-- proves no age for a later real report.
select public.report_demo('underage', '', null);
select public.object_to_report(pg_temp.demo_report(9), 'Ik ben 36.',
    '{"initial":"A","birth_date":"1990-01-02","expires":"2031-05-01","document":"P","check_digits":true}');
select pg_temp.ok((public.matching_status() #>> '{moderation,objection_result,decision}') = 'approved'
    and (public.matching_status() #>> '{moderation,strikes}')::integer = 0,
    'A demo "under 18" with a matching document is approved automatically');
select pg_temp.as_postgres();
select pg_temp.ok(not matching_private.age_proven_before(matching_private.identity_hashes(pg_temp.id(9)), gen_random_uuid()),
    'but proves no age for a real report');

-- ===== 4. Demo reports never add up to a lock ==============================
-- Two real reports and a demo: a 7-day block, not a ban.
select pg_temp.as_user(2);
select public.report_partner(pg_temp.id(23), 'spam', '');
select pg_temp.as_postgres();
update public.match_reports set created_at = now() - interval '2 hours' where match_id = pg_temp.id(23);
select pg_temp.as_user(3);
select public.report_partner(pg_temp.id(33), 'spam', '');
select pg_temp.as_postgres();
update public.match_reports set created_at = now() - interval '1 hour' where match_id = pg_temp.id(33);
select pg_temp.as_user(9);
select public.report_demo('spam', '', null);
select pg_temp.as_postgres();
select pg_temp.ok((select (m->>'strikes')::integer = 3 and not (m->>'banned')::boolean
        and (m->>'suspended_until')::timestamptz > now() from pg_temp.moderation(9) m),
    'Two real reports block for 7 days; the demo on top does not ban');

-- ===== 5. Privileges =======================================================
select pg_temp.ok(not has_function_privilege('authenticated', 'matching_private.moderation_state(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'matching_private.age_proven_before(text[], uuid)', 'execute')
    and has_function_privilege('authenticated', 'public.report_demo(text, text, jsonb)', 'execute'),
    'Internals stay closed; report_demo is open to signed-in users (and refuses non-administrators)');

do $$ begin
    raise exception 'TEST RESULT: % checks passed', (select count(*) from demo_results);
end; $$;
rollback;
