-- Refined report flow (202611200009). Run as postgres in the Supabase SQL
-- Editor: everything rolls back, and the last line reports how many checks
-- passed.
begin;
set local stop_swiping.access_check = 'off';
set local stop_swiping.matching_throttle = 'off';
create temporary table refine_results(name text primary key);
grant select, insert on refine_results to authenticated;
create function pg_temp.ok(passed boolean, label text) returns void
language plpgsql as $$ begin
    if passed is distinct from true then raise exception 'FAILED: %', label; end if;
    insert into refine_results values(label);
end; $$;
create function pg_temp.id(n integer) returns uuid language sql immutable as $$
    select ('0b1f0000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
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
create function pg_temp.report_of(match_n integer) returns uuid language sql security definer as $$
    select id from public.match_reports where match_id = pg_temp.id(match_n) order by created_at desc limit 1 $$;
create function pg_temp.moderation(n integer) returns jsonb language sql security definer as $$
    select matching_private.moderation_state(pg_temp.id(n)) $$;
grant execute on function pg_temp.report_of(integer), pg_temp.moderation(integer) to authenticated;

insert into auth.users(id, aud, role, last_sign_in_at)
    select pg_temp.id(n), 'authenticated', 'authenticated', now() from generate_series(1, 9) n;
insert into matching_private.admins(user_id) values (pg_temp.id(9));
-- Jan Pieter, who goes by Pieter, born 4 March 2000.
insert into public.profiles(id, profile, backup)
    values (pg_temp.id(5), '{"displayName":"Pieter","dateOfBirth":"2000-03-04T12:00:00Z"}', '{}');
insert into public.matches(id, user_low, user_high, score_low, score_high) values
    (pg_temp.id(12), pg_temp.id(1), pg_temp.id(2), 80, 80),
    (pg_temp.id(13), pg_temp.id(1), pg_temp.id(3), 80, 80),
    (pg_temp.id(14), pg_temp.id(1), pg_temp.id(4), 80, 80),
    (pg_temp.id(56), pg_temp.id(5), pg_temp.id(6), 80, 80),
    (pg_temp.id(57), pg_temp.id(5), pg_temp.id(7), 80, 80),
    (pg_temp.id(58), pg_temp.id(5), pg_temp.id(8), 80, 80),
    (pg_temp.id(68), pg_temp.id(6), pg_temp.id(8), 80, 80);

-- ===== 1. Concerning offline behavior goes to the administrators ==========
select pg_temp.as_user(2);
select public.report_partner(pg_temp.id(12), 'offlineBehavior', 'Followed me home');
select pg_temp.as_postgres();
select pg_temp.ok((select review = 'pending' and counts_as_strike from public.match_reports where id = pg_temp.report_of(12)),
    'Concerning behavior counts as a strike and waits for a review');
select pg_temp.ok(exists (select 1 from notification_private.outbox where user_id = pg_temp.id(9)
    and kind = 'moderation_report' and detail = 'review'), 'and the administrator gets a push at once');
select pg_temp.ok((pg_temp.moderation(1)->>'strikes')::integer = 1 and not (pg_temp.moderation(1)->>'banned')::boolean,
    'The person sees a regular first warning meanwhile');

select pg_temp.as_user(1);
select pg_temp.ok(pg_temp.error_of('select public.admin_reviews()') = 'Administrators only', 'Only administrators review');
-- The person's phone.
select public.register_device('11111111-1111-4111-8111-111111111111');

select pg_temp.as_user(9);
select pg_temp.ok((public.matching_status()->>'admin_pending')::integer = 1, 'The review counts in the badge');
select pg_temp.ok((select jsonb_array_length(l) = 1 and l #>> '{0,details}' = 'Followed me home'
    and (l #>> '{0,strike}')::integer = 1 from (select public.admin_reviews() as l) x), 'and shows in the list');
select public.admin_review_report(pg_temp.report_of(12), true);
select pg_temp.ok(pg_temp.error_of(format('select public.admin_review_report(%L, false)', pg_temp.report_of(12)))
    = 'Report already reviewed', 'A review is decided once');
select pg_temp.ok((public.matching_status()->>'admin_pending')::integer = 0, 'Nothing left to review');
select pg_temp.ok((pg_temp.moderation(1)->>'banned')::boolean and pg_temp.moderation(1)->>'ban_reason' = 'direct',
    'A direct ban bans at once');
select pg_temp.as_postgres();
select pg_temp.ok(exists (select 1 from matching_private.banned_devices b
    where b.marker = matching_private.device_hash('install', '11111111-1111-4111-8111-111111111111')),
    'and remembers the banned person''s phone');

-- ===== 2. A new account on that phone is banned too =======================
select pg_temp.as_user(3);
select pg_temp.ok(not public.register_device('33333333-3333-4333-8333-333333333333'), 'Another phone is free');
select pg_temp.ok(public.register_device('11111111-1111-4111-8111-111111111111'), 'The banned phone is not');
select pg_temp.ok(public.matching_status() #>> '{moderation,ban_reason}' = 'device'
    and public.matching_status()->>'state' = 'banned', 'The new account is banned because of the phone');
select pg_temp.as_postgres();
select pg_temp.ok(matching_private.is_blocked(pg_temp.id(3)), 'and kept out of matching');
select pg_temp.ok(not exists (select 1 from matching_private.banned_devices
    where marker = matching_private.device_hash('install', '33333333-3333-4333-8333-333333333333')),
    'A phone ban does not spread to that account''s other phones');

select pg_temp.as_user(9);
select pg_temp.ok(not public.register_device('11111111-1111-4111-8111-111111111111'), 'An administrator is never caught');

-- ===== 3. Three strikes ban the phone; withdrawing lifts it ===============
select pg_temp.as_user(6);
select public.register_device('66666666-6666-4666-8666-666666666666');
select pg_temp.as_user(8);
select public.report_partner(pg_temp.id(68), 'spam', '');
select pg_temp.as_postgres();
update public.match_reports set created_at = now() - interval '2 days' where id = pg_temp.report_of(68);
select pg_temp.as_user(5);
select public.report_partner(pg_temp.id(56), 'harassment', '');
select pg_temp.as_postgres();
update public.match_reports set created_at = now() - interval '1 day' where id = pg_temp.report_of(56);
-- A strike via another sign-in of the same person.
insert into public.match_reports(match_id, reporter_id, reported_id, reported_identities, reason, details, counts_as_strike)
    values (pg_temp.id(68), pg_temp.id(8), pg_temp.id(6), matching_private.identity_hashes(pg_temp.id(6)), 'hateSpeech', '', true);
select matching_private.apply_moderation(pg_temp.id(6));
select pg_temp.ok(pg_temp.moderation(6)->>'ban_reason' = 'strikes', 'The third strike bans');
select pg_temp.as_user(4);
select pg_temp.ok(public.register_device('66666666-6666-4666-8666-666666666666'), 'and so does the phone');
select pg_temp.as_user(6);
select public.object_to_report(pg_temp.report_of(56), 'Niet waar.');
select pg_temp.as_postgres();
create temporary table refine_objections as select report_id, id from matching_private.report_objections;
grant select on refine_objections to authenticated;
select pg_temp.as_user(9);
select public.admin_decide_objection((select id from refine_objections where report_id = pg_temp.report_of(56)), true);
select pg_temp.ok(not (pg_temp.moderation(6)->>'banned')::boolean and not (pg_temp.moderation(4)->>'banned')::boolean,
    'Withdrawing the third strike lifts the ban and the phone ban');

-- ===== 4. "Under 18" is a lock, not a strike ==============================
select pg_temp.as_user(7);
select public.report_partner(pg_temp.id(57), 'underage', 'Says 16');
select pg_temp.as_user(5);
create temporary table locked as select public.matching_status() as s;
select pg_temp.ok((select (s #>> '{moderation,strikes}')::integer = 0 and s #> '{moderation,latest_report}' = 'null'::jsonb
    from locked), '"Under 18" is no strike');
select pg_temp.ok((select (s #>> '{moderation,age_locked}')::boolean and s->>'state' = 'age_check'
    and s #> '{moderation,age_check,objection}' = 'null'::jsonb from locked), 'but locks the account until age is proven');
select pg_temp.as_postgres();
select pg_temp.ok(matching_private.is_blocked(pg_temp.id(5)), 'which keeps them out of matching');

-- Any given name's initial counts: "JAN PIETER" for Pieter.
select pg_temp.as_user(5);
select public.object_to_report(pg_temp.report_of(57), '',
    '{"initials":["J","P"],"birth_date":"2000-03-04","expires":"2031-05-01","document":"P","check_digits":true}');
create temporary table unlocked as select public.matching_status() as s;
select pg_temp.ok((select not (s #>> '{moderation,age_locked}')::boolean
    and s #>> '{moderation,objection_result,decision}' = 'approved' from unlocked),
    'A matching second given name unlocks at once, without words');

-- When the document does not work: a message to the administrators.
select pg_temp.as_user(8);
select public.report_partner(pg_temp.id(58), 'underage', 'Again');
select pg_temp.as_user(5);
select pg_temp.ok(pg_temp.error_of(format('select public.object_to_report(%L, %L)', pg_temp.report_of(58), ' '))
    = 'Objection message required', 'Without a document, words are needed');
select public.object_to_report(pg_temp.report_of(58), 'Mijn ID wordt niet gelezen.');
select pg_temp.ok((public.matching_status() #>> '{moderation,age_check,objection}') = 'pending'
    and (public.matching_status() #>> '{moderation,age_locked}')::boolean, 'It waits for an administrator, still locked');
select pg_temp.as_postgres();
truncate refine_objections;
insert into refine_objections select report_id, id from matching_private.report_objections;
select pg_temp.as_user(9);
select pg_temp.ok((select (e #>> '{report,strike}')::integer = 0 and e->>'id_check' is null
    from jsonb_array_elements(public.admin_objections()) e where e #>> '{report,id}' = pg_temp.report_of(58)::text),
    'The administrator sees a message without a document, and no strike');
select pg_temp.ok(pg_temp.error_of(format('select public.admin_decide_objection(%L, true, true)',
    (select id from refine_objections where report_id = pg_temp.report_of(58)))) = 'Cannot approve and ban',
    'Approving and banning exclude each other');
-- Rejected, and banned: an unfounded objection.
select public.admin_decide_objection((select id from refine_objections where report_id = pg_temp.report_of(58)), false, true);
select pg_temp.ok(pg_temp.moderation(5)->>'ban_reason' = 'direct', 'Rejecting with a ban bans directly');

-- ===== 4b. Manual review: a photo is required, approved after 24 hours ====
select pg_temp.as_postgres();
insert into public.matches(id, user_low, user_high, score_low, score_high) values
    (pg_temp.id(37), pg_temp.id(3), pg_temp.id(7), 80, 80),
    (pg_temp.id(27), pg_temp.id(2), pg_temp.id(7), 80, 80);
select pg_temp.as_user(7);
select public.report_partner(pg_temp.id(37), 'underage', '');
select pg_temp.as_user(3);
select pg_temp.ok(pg_temp.error_of(format('select public.object_to_report(%L, %L, %L)', pg_temp.report_of(37), '',
    '{"manual_review":true}')) = 'Photo required', 'A manual review needs a photo');
select public.object_to_report(pg_temp.report_of(37), '', '{"manual_review":true,"photo_attached":true,"initial":"X"}');
select pg_temp.as_postgres();
select pg_temp.ok((select id_check = '{"manual_review":true,"photo_attached":true}'::jsonb and message = ''
    from matching_private.report_objections where report_id = pg_temp.report_of(37)),
    'Only the request reaches the server, no document details');
select pg_temp.as_user(9);
select pg_temp.ok((select (e->>'auto_decides_at')::timestamptz between now() + interval '23 hours' and now() + interval '25 hours'
    from jsonb_array_elements(public.admin_objections()) e
    where e #>> '{report,id}' = pg_temp.report_of(37)::text), 'The administrator sees when it is approved by itself');
select pg_temp.as_postgres();
select matching_private.auto_decide_moderation();
select pg_temp.ok((select decision is null from matching_private.report_objections where report_id = pg_temp.report_of(37)),
    'Not before 24 hours');
update matching_private.report_objections set created_at = now() - interval '25 hours' where report_id = pg_temp.report_of(37);

-- ===== 4c. Nobody decided in time ========================================
-- Concerning behavior without an objection stays a warning after 7 days.
select pg_temp.as_postgres();
insert into public.matches(id, user_low, user_high, score_low, score_high) values
    (pg_temp.id(47), pg_temp.id(4), pg_temp.id(7), 80, 80);
select pg_temp.as_user(7);
select public.report_partner(pg_temp.id(47), 'offlineBehavior', 'Volgde me');
select pg_temp.as_postgres();
update public.match_reports set created_at = now() - interval '8 days' where match_id = pg_temp.id(47);

-- With an objection, the objection card replaces the review card, and one
-- decision (or the objection's own 7 days) settles both.
select pg_temp.as_user(7);
select public.report_partner(pg_temp.id(27), 'offlineBehavior', 'Stalking');
select pg_temp.as_user(2);
select pg_temp.ok(pg_temp.error_of(format('select public.object_to_report(%L, %L)', pg_temp.report_of(27), ''))
    = 'Objection message required', 'An ordinary objection needs words');
select public.object_to_report(pg_temp.report_of(27), 'Klopt niet.');
select pg_temp.as_user(9);
select pg_temp.ok(not exists (select 1 from jsonb_array_elements(public.admin_reviews()) e
    where e->>'id' = pg_temp.report_of(27)::text), 'A report with an objection shows only as the objection');
select pg_temp.ok(pg_temp.error_of(format('select public.admin_review_report(%L, true)', pg_temp.report_of(27)))
    = 'Objection pending', 'and is decided there');
select pg_temp.as_postgres();
update public.match_reports set created_at = now() - interval '8 days' where match_id = pg_temp.id(27);
update matching_private.report_objections set created_at = now() - interval '6 days'
    where report_id = pg_temp.report_of(27);
select matching_private.auto_decide_moderation();
select pg_temp.ok((select decision = 'approved' and timed_out and not decided_automatically
    from matching_private.report_objections where report_id = pg_temp.report_of(37)),
    'A manual review is approved after 24 hours');
select pg_temp.ok(not (pg_temp.moderation(3)->>'age_locked')::boolean, 'which unlocks the account');
select pg_temp.ok((select review = 'warning' and reviewed_by is null from public.match_reports where match_id = pg_temp.id(47)),
    'Concerning behavior stays a regular warning after 7 days');
select pg_temp.ok((select review = 'pending' from public.match_reports where match_id = pg_temp.id(27)),
    'but not while an objection to it waits');
select pg_temp.ok((select decision is null from matching_private.report_objections where report_id = pg_temp.report_of(27)),
    'An ordinary objection still waits at 6 days');
update matching_private.report_objections set created_at = now() - interval '8 days' where report_id = pg_temp.report_of(27);
select matching_private.auto_decide_moderation();
select pg_temp.ok((select dismissed_at is not null and review is null from public.match_reports where match_id = pg_temp.id(27)),
    'and is approved after 7 days: the report is withdrawn, its review with it');
select pg_temp.ok(exists (select 1 from cron.job where jobname = 'moderation-auto-decide'), 'Checked every hour');

-- ===== 4d. Phones are kept with a match ===================================
select pg_temp.ok(exists (select 1 from information_schema.columns where table_schema = 'matching_private'
    and table_name = 'match_identities' and column_name = 'device_markers'), 'A match keeps both phones');

-- ===== 5. Privileges ======================================================
select pg_temp.as_postgres();
select pg_temp.ok(not has_function_privilege('anon', 'public.register_device(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.admin_reviews()', 'execute')
    and not has_function_privilege('authenticated', 'matching_private.ban_devices(uuid)', 'execute')
    and not has_function_privilege('authenticated', 'matching_private.device_hash(text, text)', 'execute'),
    'Nothing is open to anonymous callers, nor the internals to users');
select pg_temp.ok(not has_table_privilege('authenticated', 'matching_private.banned_devices', 'select')
    and not has_table_privilege('authenticated', 'matching_private.account_devices', 'select'),
    'Phones are not readable directly');

do $$ begin
    raise exception 'TEST RESULT: % checks passed', (select count(*) from refine_results);
end; $$;
rollback;
