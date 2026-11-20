-- Objections to reports (202611200007). Run as postgres in the Supabase SQL
-- Editor ("Run without RLS" is fine): everything rolls back, and the last
-- line reports how many checks passed.
begin;
set local stop_swiping.access_check = 'off';
set local stop_swiping.matching_throttle = 'off';
create temporary table objection_results(name text primary key);
grant select, insert on objection_results to authenticated;
create function pg_temp.ok(passed boolean, label text) returns void
language plpgsql as $$ begin
    if passed is distinct from true then raise exception 'FAILED: %', label; end if;
    insert into objection_results values(label);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
    select ('0b1e0000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
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
-- Security definer: the reported person may not read reports themselves.
create function pg_temp.report_of(match_n integer) returns uuid language sql security definer as $$
    select id from public.match_reports where match_id = pg_temp.id(match_n) order by created_at desc limit 1 $$;
create function pg_temp.admin_pushes() returns bigint language sql as $$
    select count(*) from notification_private.outbox where kind = 'moderation_report' $$;
-- Matching document facts for Émile, born 4 March 2000.
create function pg_temp.passport() returns jsonb language sql immutable as $$
    select '{"initial":"e","birth_date":"2000-03-04","expires":"2031-05-01","document":"P","check_digits":true}'::jsonb $$;
grant execute on function pg_temp.passport() to authenticated;

insert into auth.users(id, aud, role, last_sign_in_at)
    select pg_temp.id(n), 'authenticated', 'authenticated', now() from generate_series(1, 9) n;
-- The reported person: Émile, born 4 March 2000. Not in matching.
insert into public.profiles(id, profile, backup)
    values (pg_temp.id(2), '{"displayName":"Émile","dateOfBirth":"2000-03-04T12:00:00Z"}', '{}');
insert into matching_private.admins(user_id) values (pg_temp.id(9));
insert into public.matches(id, user_low, user_high, score_low, score_high) values
    (pg_temp.id(12), pg_temp.id(1), pg_temp.id(2), 80, 80),
    (pg_temp.id(23), pg_temp.id(2), pg_temp.id(3), 80, 80),
    (pg_temp.id(24), pg_temp.id(2), pg_temp.id(4), 80, 80),
    (pg_temp.id(56), pg_temp.id(5), pg_temp.id(6), 80, 80);

-- ===== 1. A report with a copy of the conversation ========================
select pg_temp.as_user(1);
select public.report_partner(pg_temp.id(12), 'underage', 'Says they are 16', false,
    '[{"from":"reporter","at":"2026-11-20T10:00:00Z","text":"Hoi"},{"from":"reported","at":"2026-11-20T10:01:00Z","text":"Ik ben 16"}]');
select pg_temp.ok(pg_temp.error_of('select chat_copy from public.match_reports') like 'permission denied%',
    'Not even the reporter reads the conversation copy back');
select pg_temp.ok(pg_temp.error_of('select reported_identities from public.match_reports') like 'permission denied%',
    'nor the reported person''s identity hashes');
select pg_temp.ok((select count(*) = 1 from public.match_reports), 'The reporter still sees their own report');
select pg_temp.as_postgres();
update public.match_reports set created_at = now() - interval '3 hours' where id = pg_temp.report_of(12);
select pg_temp.ok((select jsonb_array_length(chat_copy) = 2 from public.match_reports where id = pg_temp.report_of(12)),
    'The report keeps the conversation copy');
select pg_temp.ok(pg_temp.admin_pushes() = 0, 'A plain report reaches no administrator');
select pg_temp.ok(not has_column_privilege('anon', 'public.match_reports', 'details', 'select')
    and not has_column_privilege('authenticated', 'public.match_reports', 'chat_copy', 'select'),
    'Nobody else can select reports or their copies');

select pg_temp.as_user(3);
select public.report_partner(pg_temp.id(23), 'spam', '', false, '[]');
select pg_temp.as_postgres();
select pg_temp.ok((select chat_copy is null from public.match_reports where match_id = pg_temp.id(23)),
    'An empty copy is stored as none');
delete from public.match_reports where match_id = pg_temp.id(23);

-- ===== 2. What the reported person sees ===================================
select pg_temp.as_user(2);
create temporary table seen as select public.matching_status() as s;
select pg_temp.ok((select s #>> '{moderation,latest_report,reason}' = 'underage' from seen), 'The notice names the reason');
select pg_temp.ok((select s #> '{moderation,latest_report,objection}' = 'null'::jsonb from seen), 'No objection yet');
select pg_temp.ok((select not (s->>'is_admin')::boolean and (s->>'admin_pending')::integer = 0 from seen),
    'A person is no administrator');
select pg_temp.ok(pg_temp.error_of('select public.admin_objections()') = 'Administrators only', 'and cannot list objections');
select pg_temp.ok(pg_temp.error_of(format('select public.admin_decide_objection(%L, true)', gen_random_uuid()))
    = 'Administrators only', 'or decide one');

-- ===== 3. First "under 18" objection with a matching document: automatic ===
select pg_temp.ok(pg_temp.error_of(format('select public.object_to_report(%L, %L)', pg_temp.report_of(12), 'Ik ben 26'))
    = 'Proof of age required', '"May be under 18" needs proof of age');
select pg_temp.ok(pg_temp.error_of(format('select public.object_to_report(%L, %L, %L)', pg_temp.report_of(12), '  ',
    pg_temp.passport())) = 'Objection message required', 'An objection needs words');
select pg_temp.ok(pg_temp.error_of(format('select public.object_to_report(%L, %L, %L)', pg_temp.report_of(12), 'Ik ben 26',
    '{"initial":"E","birth_date":"not a date"}')) = 'Proof of age unreadable', 'A garbled document is refused');
select public.object_to_report(pg_temp.report_of(12), 'Ik ben 26, zie mijn ID.', pg_temp.passport());
create temporary table first_time as select public.matching_status() as s;
select pg_temp.ok((select (s #>> '{moderation,strikes}')::integer = 0 and s #> '{moderation,latest_report}' = 'null'::jsonb
    and s #>> '{moderation,objection_result,decision}' = 'approved' from first_time),
    'A first matching age proof withdraws the report at once');
select pg_temp.as_postgres();
select pg_temp.ok((select decided_automatically and decided_by is null and id_check->>'profile_initial' = 'E'
        and (id_check->>'initial_matches')::boolean and (id_check->>'birth_date_matches')::boolean
    from matching_private.report_objections where report_id = pg_temp.report_of(12)),
    'decided automatically, after the server compared it with the profile (É = E)');
select pg_temp.ok(pg_temp.admin_pushes() = 0, 'without bothering an administrator');

-- ===== 4. A second "under 18" report goes to the administrator ============
select pg_temp.as_user(4);
select public.report_partner(pg_temp.id(24), 'underage', 'Again: says 16', false,
    '[{"from":"reported","at":"2026-11-20T12:00:00Z","text":"Ik zit in 4 havo"}]');
select pg_temp.as_postgres();
update public.match_reports set created_at = now() - interval '1 hour' where id = pg_temp.report_of(24);
select pg_temp.as_user(2);
select public.object_to_report(pg_temp.report_of(24), 'Weer niet waar.', pg_temp.passport());
select pg_temp.ok((public.matching_status() #>> '{moderation,latest_report,objection}') = 'pending',
    'The second time it waits for an administrator');
select pg_temp.ok(pg_temp.error_of(format('select public.object_to_report(%L, %L, %L)', pg_temp.report_of(24), 'Nog een keer',
    pg_temp.passport())) = 'Objection already made', 'One objection per report');
select pg_temp.as_user(4);
select pg_temp.ok(pg_temp.error_of(format('select public.object_to_report(%L, %L)', pg_temp.report_of(24), 'Ik niet'))
    = 'Report unavailable', 'The reporter cannot object to their own report');
select pg_temp.as_postgres();
select pg_temp.ok(exists (select 1 from notification_private.outbox where user_id = pg_temp.id(9)
    and kind = 'moderation_report' and detail = 'underage'), 'and the administrator gets a push');
select pg_temp.ok(not exists (select 1 from notification_private.outbox where kind = 'moderation_report'
    and user_id not in (select user_id from matching_private.admins)), 'only administrators');
create temporary table claimed as select public.push_claim_due(500) as entries;
select pg_temp.ok((select entries::text not like '%Weer niet%' and entries::text not like '%4 havo%'
    and entries::text not like '%Again%' from claimed), 'The push carries no words, report or conversation');

-- A first proof that does not match (here: no profile to compare) is no automatic approval.
select pg_temp.as_user(6);
select public.report_partner(pg_temp.id(56), 'underage', '');
select pg_temp.as_user(5);
select public.object_to_report(pg_temp.report_of(56), 'Ik ben volwassen.', pg_temp.passport());
select pg_temp.ok((public.matching_status() #>> '{moderation,latest_report,objection}') = 'pending',
    'A proof that cannot be matched goes to an administrator');

-- ===== 5. The administrator's list ========================================
select pg_temp.as_user(9);
create temporary table admin_view as select public.matching_status() as s, public.admin_objections() as list;
select pg_temp.ok((select (s->>'is_admin')::boolean and (s->>'admin_pending')::integer = 2 from admin_view),
    'The administrator sees two open objections');
select pg_temp.ok((select jsonb_array_length(list) = 2 from admin_view), 'and only those, no plain reports');
select pg_temp.ok((select exists (select 1 from jsonb_array_elements(list) e
        where e->>'message' = 'Weer niet waar.' and e #>> '{report,details}' = 'Again: says 16'
        and jsonb_array_length(e #> '{report,chat_copy}') = 1 and (e #>> '{report,strike}')::integer = 1
        and (e->>'age_proven_before')::boolean and e->>'display_name' = 'Émile') from admin_view),
    'Each with the report, its conversation, the objection and the earlier age proof');

-- ===== 6. Another report, objected to and approved ========================
select pg_temp.as_user(3);
select public.report_partner(pg_temp.id(23), 'harassment', 'Rude');
select pg_temp.as_user(2);
create temporary table second as select public.matching_status() as s;
select pg_temp.ok((select (s #>> '{moderation,strikes}')::integer = 2 and s #>> '{moderation,suspended_until}' is not null
    and s #>> '{moderation,latest_report,reason}' = 'harassment' from second), 'The second strike blocks, and is the newest');
select public.acknowledge_moderation();
select public.object_to_report(pg_temp.report_of(23), 'Dit klopt niet.');

select pg_temp.as_postgres();
create temporary table objection_ids as select o.report_id, o.id from matching_private.report_objections o;
grant select on objection_ids to authenticated;
select pg_temp.as_user(9);
select public.admin_decide_objection((select id from objection_ids where report_id = pg_temp.report_of(23)), true);
select pg_temp.ok(pg_temp.error_of(format('select public.admin_decide_objection(%L, false)',
    (select id from objection_ids where report_id = pg_temp.report_of(23)))) = 'Objection already decided',
    'An objection is decided once');

select pg_temp.as_user(2);
create temporary table approved as select public.matching_status() as s;
select pg_temp.ok((select (s #>> '{moderation,strikes}')::integer = 1 and s #>> '{moderation,suspended_until}' is null from approved),
    'Approving withdraws the report and lifts the block');
select pg_temp.ok((select (s #>> '{moderation,strikes_seen}')::integer = 1 from approved),
    'and a later report shows as new again');
select pg_temp.ok((select s #>> '{moderation,objection_result,decision}' = 'approved' from approved), 'The person sees it was approved');
select public.acknowledge_moderation();
select pg_temp.ok(public.matching_status() #> '{moderation,objection_result}' = 'null'::jsonb, 'until they have read it');

-- ===== 7. Rejected =========================================================
select pg_temp.as_user(9);
select public.admin_decide_objection((select id from objection_ids where report_id = pg_temp.report_of(24)), false);
select pg_temp.ok((public.matching_status()->>'admin_pending')::integer = 1, 'One left to decide');
select pg_temp.as_user(2);
create temporary table rejected as select public.matching_status() as s;
select pg_temp.ok((select (s #>> '{moderation,strikes}')::integer = 1
    and s #>> '{moderation,latest_report,objection}' = 'rejected'
    and s #>> '{moderation,objection_result,decision}' = 'rejected' from rejected), 'Rejecting keeps the report');

-- ===== 8. Privileges =======================================================
select pg_temp.as_postgres();
select pg_temp.ok(not has_function_privilege('anon', 'public.admin_objections()', 'execute')
    and not has_function_privilege('anon', 'public.object_to_report(uuid, text, jsonb)', 'execute')
    and not has_function_privilege('authenticated', 'matching_private.is_admin(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'matching_private.withdraw_report(uuid, uuid)', 'execute'),
    'Nothing is open to anonymous callers, nor the internals to users');
select pg_temp.ok(not has_table_privilege('authenticated', 'matching_private.report_objections', 'select'),
    'Objections are not readable directly');

do $$ begin
    raise exception 'TEST RESULT: % checks passed', (select count(*) from objection_results);
end; $$;
rollback;
