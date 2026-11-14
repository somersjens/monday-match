-- Run as postgres in Supabase SQL Editor. Every fixture and change rolls back.
begin;
create temporary table matching_test_results(name text primary key);
grant select, insert on matching_test_results to authenticated;
create function pg_temp.check_test(ok boolean, label text) returns void
language plpgsql as $$ begin
    if ok is distinct from true then raise exception 'FAILED: %',label; end if;
    insert into matching_test_results values(label);
end; $$;
create temporary table matching_fixture(p jsonb, b jsonb);
insert into matching_fixture
select jsonb_build_object(
    'displayName','Matching transaction fixture','autoMatchingEnabled',true,'profileComplete',true,
    'dateOfBirth','1995-06-15T12:00:00Z','gender','nonBinary','interestedIn',jsonb_build_array('nonBinary'),
    'languages',jsonb_build_array('nl'),'heightCentimeters',175,
    'ownAttractiveness',7,'partnerMinimumAttractiveness',5,'minimumMatchPercent',70,
    'coarseLatitude',-89,'coarseLongitude',170,'preferredRadiusKilometers',1,
    'preferredPartnerMinimumAge',18,'preferredPartnerMaximumAge',80,
    'religion','other','acceptedPartnerReligions',jsonb_build_array('other'),
    'requiresVerifiedPartnerPhoto',false,
    'relationshipPreferences',jsonb_build_object('sexualArrangement',jsonb_build_array('partnerOnly')),
    'lifestyle',jsonb_build_object('hasChildren',false,'openToPartnerWithChildren',true,'futureChildren','notSure',
        'aloneTime',jsonb_build_object('own',3,'partner',3,'importance',3),
        'storedCompatibilityAnswers',(select jsonb_object_agg(q,jsonb_build_object('own',3,'partner',3,'importance',3))
            from unnest(matching_private.question_ids()) q where q <> 'aloneTime'),
        'substances',jsonb_build_object(
            'alcohol',jsonb_build_object('ownLevel',0,'partnerMaximumLevel',5),
            'smoking',jsonb_build_object('ownLevel',0,'partnerMaximumLevel',5),
            'drugs',jsonb_build_object('ownLevel',0,'partnerMaximumLevel',5)))),
    '{"state":{"profilePrivacyConsent":{"version":"2026-11-14.v1"},"storedAutoMatching":{"privacyConsent":{"version":"2026-11-14.v1"}}}}'::jsonb;

select pg_temp.check_test(matching_private.eligible(p,b),'Complete opted-in profile admitted') from matching_fixture;
select pg_temp.check_test(not matching_private.eligible(p,'{}'),'Missing consent rejected') from matching_fixture;
select pg_temp.check_test(not matching_private.eligible(p || '{"dateOfBirth":"2020-01-01"}',b),'Underage rejected') from matching_fixture;
select pg_temp.check_test(not matching_private.eligible(p #- '{lifestyle,aloneTime}',b),'Missing answer rejected') from matching_fixture;
select pg_temp.check_test(not matching_private.eligible(p || '{"ownAttractiveness":"invalid"}',b),'Malformed profile rejected without breaking backup') from matching_fixture;
select pg_temp.check_test(not matching_private.eligible(p || '{"minimumMatchPercent":null}',b),'Null score threshold rejected') from matching_fixture;
select pg_temp.check_test(not matching_private.eligible(p || '{"preferredRadiusKilometers":null}',b),'Null radius rejected') from matching_fixture;
select pg_temp.check_test(matching_private.directional_score(p,p)=100,'Exact score is 100, unrestricted height supported') from matching_fixture;
select pg_temp.check_test(matching_private.directional_score(p,p || '{"gender":"man"}') is null,'Gender preference enforced') from matching_fixture;
select pg_temp.check_test(matching_private.directional_score(p,p || '{"dateOfBirth":"1940-01-01"}') is null,'Age preference enforced') from matching_fixture;
select pg_temp.check_test(matching_private.directional_score(p || '{"preferredPartnerMaximumHeight":170}',p) is null,'Height preference enforced') from matching_fixture;
select pg_temp.check_test(matching_private.directional_score(p,p || '{"religion":"atheist"}') is null,'Religion preference enforced') from matching_fixture;
select pg_temp.check_test(matching_private.directional_score(p,p || '{"languages":["en"]}') is null,'Shared language required') from matching_fixture;
select pg_temp.check_test(matching_private.directional_score(p,p || '{"coarseLatitude":-85}') is null,'Distance limit enforced') from matching_fixture;
select pg_temp.check_test(matching_private.directional_score(p,p || '{"ownAttractiveness":4}') is null,'Appearance minimum enforced') from matching_fixture;
select pg_temp.check_test(matching_private.directional_score(p,jsonb_set(p,'{relationshipPreferences,sexualArrangement}','["noSex"]')) is null,'Arrangement enforced') from matching_fixture;
select pg_temp.check_test(matching_private.directional_score(jsonb_set(p,'{lifestyle,openToPartnerWithChildren}','false'),jsonb_set(p,'{lifestyle,hasChildren}','true')) is null,'Children preference enforced') from matching_fixture;
select pg_temp.check_test(matching_private.directional_score(jsonb_set(p,'{lifestyle,futureChildren}','"yes"'),jsonb_set(p,'{lifestyle,futureChildren}','"no"')) is null,'Future children preference enforced') from matching_fixture;
select pg_temp.check_test(matching_private.directional_score(jsonb_set(p,'{lifestyle,substances,smoking,partnerMaximumLevel}','0'),jsonb_set(p,'{lifestyle,substances,smoking,ownLevel}','1')) is null,'Substance maximum enforced') from matching_fixture;
do $$ declare p jsonb; c jsonb; q text; begin
    select f.p into p from matching_fixture f; c:=p;
    foreach q in array matching_private.question_ids() loop
        if q='aloneTime' then c:=jsonb_set(c,'{lifestyle,aloneTime,own}','4');
        else c:=jsonb_set(c,array['lifestyle','storedCompatibilityAnswers',q,'own'],'4'); end if;
    end loop;
    perform pg_temp.check_test(matching_private.directional_score(p,c)=76,'Weighted score includes all 50 questions and 3 habits');
end; $$;

-- Reserved IDs: collision aborts rather than touching an existing account.
insert into auth.users(id,aud,role) values
('a7fa0000-0000-4000-8000-000000000001','authenticated','authenticated'),
('a7fa0000-0000-4000-8000-000000000002','authenticated','authenticated'),
('a7fa0000-0000-4000-8000-000000000003','authenticated','authenticated'),
('a7fa0000-0000-4000-8000-000000000004','authenticated','authenticated');
insert into public.profiles(id,profile,backup)
select 'a7fa0000-0000-4000-8000-000000000001',p,b from matching_fixture;
select pg_temp.check_test(exists(select 1 from matching_private.pool where user_id='a7fa0000-0000-4000-8000-000000000001'),'First arrival waits in pool');
insert into public.profiles(id,profile,backup)
select 'a7fa0000-0000-4000-8000-000000000002',p,b from matching_fixture;
create temporary table matching_test_match(id uuid);
insert into matching_test_match select match_id from matching_private.active_members where user_id='a7fa0000-0000-4000-8000-000000000001';
grant select on matching_test_match to authenticated;
select pg_temp.check_test((select count(*)=1 from matching_test_match),'Second arrival immediately creates match');
select pg_temp.check_test((select count(*)=2 from matching_private.active_members where match_id=(select id from matching_test_match)),'Both participants reserved');
select pg_temp.check_test(not exists(select 1 from matching_private.pool where user_id in ('a7fa0000-0000-4000-8000-000000000001','a7fa0000-0000-4000-8000-000000000002')),'Both participants removed from pool');
select pg_temp.check_test(matching_private.reconcile('a7fa0000-0000-4000-8000-000000000001')=(select id from matching_test_match),'Retry returns same match');
insert into public.profiles(id,profile,backup)
select 'a7fa0000-0000-4000-8000-000000000003',p,b from matching_fixture;
select pg_temp.check_test(exists(select 1 from matching_private.pool where user_id='a7fa0000-0000-4000-8000-000000000003'),'Third arrival cannot take occupied partner');
update public.profiles set profile=profile || '{"autoMatchingEnabled":false}' where id='a7fa0000-0000-4000-8000-000000000003';
select pg_temp.check_test(not exists(select 1 from matching_private.pool where user_id='a7fa0000-0000-4000-8000-000000000003'),'Disabling removes waiting user');

set local role authenticated;
select set_config('request.jwt.claim.sub','a7fa0000-0000-4000-8000-000000000003',true);
select pg_temp.check_test((select count(*)=0 from public.matches),'Third party cannot read other matches');
do $$ begin
    begin
        perform public.end_match((select id from matching_test_match));
        raise exception 'Third party ended a match';
    exception when insufficient_privilege then
        perform pg_temp.check_test(true,'Third party cannot close match');
    end;
    begin
        insert into public.matches(user_low,user_high,score_low,score_high) values(
            'a7fa0000-0000-4000-8000-000000000003','a7fa0000-0000-4000-8000-000000000004',100,100);
        raise exception 'Client forged a match';
    exception when insufficient_privilege then
        perform pg_temp.check_test(true,'Client cannot forge match');
    end;
    begin
        perform matching_private.reconcile('a7fa0000-0000-4000-8000-000000000001');
        raise exception 'Client called private engine';
    exception when insufficient_privilege then
        perform pg_temp.check_test(true,'Private engine inaccessible to clients');
    end;
end; $$;
select set_config('request.jwt.claim.sub','a7fa0000-0000-4000-8000-000000000001',true);
select pg_temp.check_test(public.matching_status()->>'state'='matched','Participant sees matched status');
select public.publish_match_key_bundle((select id from matching_test_match),'a7fa0000-0000-4000-8000-000000000011','{"test_public_key":"fixture-A"}');
select set_config('request.jwt.claim.sub','a7fa0000-0000-4000-8000-000000000002',true);
select public.publish_match_key_bundle((select id from matching_test_match),'a7fa0000-0000-4000-8000-000000000012','{"test_public_key":"fixture-B"}');
select set_config('request.jwt.claim.sub','a7fa0000-0000-4000-8000-000000000001',true);
select public.send_encrypted_message((select id from matching_test_match),'a7fa0000-0000-4000-8000-000000000021',
    'a7fa0000-0000-4000-8000-000000000011','a7fa0000-0000-4000-8000-000000000012','opaque-test-envelope');
select public.send_encrypted_message((select id from matching_test_match),'a7fa0000-0000-4000-8000-000000000021',
    'a7fa0000-0000-4000-8000-000000000011','a7fa0000-0000-4000-8000-000000000012','opaque-test-envelope');
select pg_temp.check_test((select count(*)=1 from public.encrypted_messages where match_id=(select id from matching_test_match)),'Message retry does not duplicate');
do $$ begin
    begin
        perform public.send_encrypted_message((select id from matching_test_match),'a7fa0000-0000-4000-8000-000000000021',
            'a7fa0000-0000-4000-8000-000000000011','a7fa0000-0000-4000-8000-000000000012','different-envelope');
        raise exception 'Message ID reuse unexpectedly accepted';
    exception when raise_exception then
        if SQLERRM <> 'Message identifier already used' then raise; end if;
        perform pg_temp.check_test(true,'Message ID cannot replace ciphertext');
    end;
end; $$;
select set_config('request.jwt.claim.sub','a7fa0000-0000-4000-8000-000000000003',true);
select pg_temp.check_test((select count(*)=0 from public.encrypted_messages),'Third party cannot read ciphertext');
select pg_temp.check_test((select count(*)=0 from public.match_key_bundles),'Third party cannot read key bundles');
do $$ begin
    begin
        perform public.send_encrypted_message((select id from matching_test_match),gen_random_uuid(),
            gen_random_uuid(),gen_random_uuid(),'forged');
        raise exception 'Outsider sent a message';
    exception when insufficient_privilege then
        perform pg_temp.check_test(true,'Third party cannot send message');
    end;
end; $$;
select set_config('request.jwt.claim.sub','a7fa0000-0000-4000-8000-000000000001',true);
select public.end_match((select id from matching_test_match));
select public.end_match((select id from matching_test_match));
select pg_temp.check_test((select ended_at is not null from public.matches where id=(select id from matching_test_match)),'Closing retains history and is idempotent');
select pg_temp.check_test(public.matching_status()->>'state'='waiting','Former participants rejoin pool');
select pg_temp.check_test(public.retry_matching() is null,'Previous pair never matches again');
do $$ begin
    begin
        perform public.send_encrypted_message((select id from matching_test_match),gen_random_uuid(),
            'a7fa0000-0000-4000-8000-000000000011','a7fa0000-0000-4000-8000-000000000012','late');
        raise exception 'Closed match accepted message';
    exception when insufficient_privilege then
        perform pg_temp.check_test(true,'Closed match rejects new messages');
    end;
end; $$;
reset role;
-- Same IDs still cannot pair after off/on or profile edits.
update public.profiles set profile=profile || '{"autoMatchingEnabled":false}' where id='a7fa0000-0000-4000-8000-000000000001';
update public.profiles set profile=profile || '{"autoMatchingEnabled":true}' where id='a7fa0000-0000-4000-8000-000000000001';
select pg_temp.check_test(not exists(select 1 from matching_private.active_members where user_id in ('a7fa0000-0000-4000-8000-000000000001','a7fa0000-0000-4000-8000-000000000002')),'Off/on preserves permanent pair exclusion');
-- Require a verified photo: an exact score alone must no longer match.
update public.profiles set profile=profile || '{"requiresVerifiedPartnerPhoto":true}' where id in ('a7fa0000-0000-4000-8000-000000000001','a7fa0000-0000-4000-8000-000000000002');
update public.profiles set profile=profile || '{"autoMatchingEnabled":true}' where id='a7fa0000-0000-4000-8000-000000000003';
select pg_temp.check_test(not exists(select 1 from matching_private.active_members where user_id='a7fa0000-0000-4000-8000-000000000003'),'Verified-photo preference fails closed without attestation');
-- Disable others to make the final account-lifecycle test deterministic.
update public.profiles set profile=profile || '{"autoMatchingEnabled":false}' where id in ('a7fa0000-0000-4000-8000-000000000001','a7fa0000-0000-4000-8000-000000000002');
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000004',p,b from matching_fixture;
select pg_temp.check_test(exists(select 1 from matching_private.active_members where user_id='a7fa0000-0000-4000-8000-000000000004'),'Available new pair matches');
delete from public.profiles where id='a7fa0000-0000-4000-8000-000000000004';
select pg_temp.check_test(not exists(select 1 from matching_private.active_members where user_id='a7fa0000-0000-4000-8000-000000000003'),'Profile removal releases partner');
select pg_temp.check_test(exists(select 1 from matching_private.pool where user_id='a7fa0000-0000-4000-8000-000000000003'),'Released partner is returned to pool');
select pg_temp.check_test(exists(select 1 from public.matches where user_high='a7fa0000-0000-4000-8000-000000000004' and end_reason='profile_deleted'),'Profile removal retains past pair');
insert into auth.users(id,aud,role) values('a7fa0000-0000-4000-8000-000000000005','authenticated','authenticated');
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000005',p,b from matching_fixture;
select pg_temp.check_test(exists(select 1 from matching_private.active_members where user_id='a7fa0000-0000-4000-8000-000000000005'),'Account deletion fixture has active match');
delete from auth.users where id='a7fa0000-0000-4000-8000-000000000005';
select pg_temp.check_test(not exists(select 1 from matching_private.active_members where user_id='a7fa0000-0000-4000-8000-000000000003'),'Account deletion releases surviving partner');
select pg_temp.check_test(exists(select 1 from public.matches where user_low='a7fa0000-0000-4000-8000-000000000003' and user_high is null and ended_at is not null),'Account deletion retains ended surviving history');
-- Verification is bound to the selected photo and exact uploaded object version.
insert into storage.objects(id,bucket_id,name,updated_at) values('a7fa0000-0000-4000-8000-000000000031',
    'profile-photos','a7fa0000-0000-4000-8000-000000000001/a7fa0000-0000-4000-8000-000000000041.jpg','2000-01-01');
insert into matching_private.photo_verifications(object_id,object_updated_at)
    select id,updated_at from storage.objects where id='a7fa0000-0000-4000-8000-000000000031';
select pg_temp.check_test(matching_private.verified_photo('a7fa0000-0000-4000-8000-000000000001',
    jsonb_set(b,'{state,storedAutoMatching,photoID}','"A7FA0000-0000-4000-8000-000000000041"')),'Trusted selected photo is recognized') from matching_fixture;
update storage.objects set metadata='{"test":"replacement"}' where id='a7fa0000-0000-4000-8000-000000000031';
select pg_temp.check_test(not matching_private.verified_photo('a7fa0000-0000-4000-8000-000000000001',
    jsonb_set(b,'{state,storedAutoMatching,photoID}','"A7FA0000-0000-4000-8000-000000000041"')),'Replacing verified photo invalidates attestation') from matching_fixture;
select pg_temp.check_test(not has_function_privilege('anon','public.retry_matching()','execute'),'Anonymous matching denied');
select pg_temp.check_test(not has_table_privilege('anon','public.encrypted_messages','select'),'Anonymous messages denied');

create function pg_temp.personality_own(p jsonb, v integer) returns jsonb language plpgsql as $$
declare q text; begin
    foreach q in array matching_private.question_ids() loop
        if q='aloneTime' then p:=jsonb_set(p,'{lifestyle,aloneTime,own}',to_jsonb(v));
        else p:=jsonb_set(p,array['lifestyle','storedCompatibilityAnswers',q,'own'],to_jsonb(v)); end if;
    end loop;
    return p;
end; $$;
create function pg_temp.personality_partner(p jsonb,v integer) returns jsonb language plpgsql as $$
declare q text; begin
    foreach q in array matching_private.question_ids() loop
        if q='aloneTime' then p:=jsonb_set(p,'{lifestyle,aloneTime,partner}',to_jsonb(v));
        else p:=jsonb_set(p,array['lifestyle','storedCompatibilityAnswers',q,'partner'],to_jsonb(v)); end if;
    end loop; return p;
end; $$;
insert into auth.users(id,aud,role) values('a7fa0000-0000-4000-8000-000000000101','authenticated','authenticated');
insert into auth.users(id,aud,role) values('a7fa0000-0000-4000-8000-000000000102','authenticated','authenticated');
insert into auth.users(id,aud,role) values('a7fa0000-0000-4000-8000-000000000103','authenticated','authenticated');
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000101',pg_temp.personality_own(p,4) || '{"gender":"woman","interestedIn":["man"],"languages":["test-highest"]}',b from matching_fixture;
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000102',p || '{"gender":"woman","interestedIn":["man"],"languages":["test-highest"]}',b from matching_fixture;
update matching_private.pool set joined_at='2000-01-01' where user_id='a7fa0000-0000-4000-8000-000000000101';
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000103',p || '{"gender":"man","interestedIn":["woman"],"languages":["test-highest"]}',b from matching_fixture;
select pg_temp.check_test(exists(select 1 from public.matches where user_low='a7fa0000-0000-4000-8000-000000000102' and user_high='a7fa0000-0000-4000-8000-000000000103' and ended_at is null),'Highest mean wins over an older compatible candidate');
select pg_temp.check_test(exists(select 1 from matching_private.pool where user_id='a7fa0000-0000-4000-8000-000000000101'),'Lower ranked compatible candidate remains available');
insert into auth.users(id,aud,role) values('a7fa0000-0000-4000-8000-000000000201','authenticated','authenticated');
insert into auth.users(id,aud,role) values('a7fa0000-0000-4000-8000-000000000202','authenticated','authenticated');
insert into auth.users(id,aud,role) values('a7fa0000-0000-4000-8000-000000000203','authenticated','authenticated');
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000201',pg_temp.personality_own(p,4) || '{"gender":"woman","interestedIn":["man"],"languages":["test-reverse_breaker"]}',b from matching_fixture;
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000202',p || '{"gender":"woman","interestedIn":["man"],"languages":["test-reverse_breaker"],"preferredPartnerMinimumAge":60}',b from matching_fixture;
update matching_private.pool set joined_at='2000-01-01' where user_id='a7fa0000-0000-4000-8000-000000000201';
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000203',p || '{"gender":"man","interestedIn":["woman"],"languages":["test-reverse_breaker"]}',b from matching_fixture;
select pg_temp.check_test(exists(select 1 from public.matches where user_low='a7fa0000-0000-4000-8000-000000000201' and user_high='a7fa0000-0000-4000-8000-000000000203' and ended_at is null),'Perfect score cannot bypass candidate age dealbreaker');
insert into auth.users(id,aud,role) values('a7fa0000-0000-4000-8000-000000000301','authenticated','authenticated');
insert into auth.users(id,aud,role) values('a7fa0000-0000-4000-8000-000000000302','authenticated','authenticated');
insert into auth.users(id,aud,role) values('a7fa0000-0000-4000-8000-000000000303','authenticated','authenticated');
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000301',pg_temp.personality_partner(pg_temp.personality_own(p,4),4) || '{"gender":"woman","interestedIn":["man"],"languages":["test-reverse_threshold"]}',b from matching_fixture;
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000302',pg_temp.personality_partner(p,4) || '{"gender":"woman","interestedIn":["man"],"languages":["test-reverse_threshold"],"minimumMatchPercent":90}',b from matching_fixture;
update matching_private.pool set joined_at='2000-01-01' where user_id='a7fa0000-0000-4000-8000-000000000301';
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000303',p || '{"gender":"man","interestedIn":["woman"],"languages":["test-reverse_threshold"]}',b from matching_fixture;
select pg_temp.check_test(exists(select 1 from public.matches where user_low='a7fa0000-0000-4000-8000-000000000301' and user_high='a7fa0000-0000-4000-8000-000000000303' and ended_at is null),'Mean cannot bypass candidate personal score threshold');
insert into auth.users(id,aud,role) values('a7fa0000-0000-4000-8000-000000000401','authenticated','authenticated');
insert into auth.users(id,aud,role) values('a7fa0000-0000-4000-8000-000000000402','authenticated','authenticated');
insert into auth.users(id,aud,role) values('a7fa0000-0000-4000-8000-000000000403','authenticated','authenticated');
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000401',pg_temp.personality_own(p,3) || '{"gender":"woman","interestedIn":["man"],"languages":["test-tie"]}',b from matching_fixture;
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000402',p || '{"gender":"woman","interestedIn":["man"],"languages":["test-tie"]}',b from matching_fixture;
update matching_private.pool set joined_at='2000-01-01' where user_id='a7fa0000-0000-4000-8000-000000000401';
insert into public.profiles(id,profile,backup) select 'a7fa0000-0000-4000-8000-000000000403',p || '{"gender":"man","interestedIn":["woman"],"languages":["test-tie"]}',b from matching_fixture;
select pg_temp.check_test(exists(select 1 from public.matches where user_low='a7fa0000-0000-4000-8000-000000000401' and user_high='a7fa0000-0000-4000-8000-000000000403' and ended_at is null),'Equal means choose longest-waiting candidate');

select pg_temp.check_test((select matching_private.directional_score(a.profile,b.profile)=76 from public.profiles a cross join public.profiles b where a.id='a7fa0000-0000-4000-8000-000000000302' and b.id='a7fa0000-0000-4000-8000-000000000303'),'Reverse threshold fixture fails its own minimum despite higher mean');
create temporary table live_chat_test_match(id uuid);
insert into live_chat_test_match select match_id from matching_private.active_members where user_id='a7fa0000-0000-4000-8000-000000000103';
grant select on live_chat_test_match to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','a7fa0000-0000-4000-8000-000000000103',true);
select pg_temp.check_test((public.current_chat_match()->>'partner_id')='a7fa0000-0000-4000-8000-000000000102','Live match projection returns actual partner');
select public.register_chat_device((select id from live_chat_test_match),'a7fa0000-0000-4000-8000-000000001001',
    jsonb_build_object('protocol','hpke-auth-x25519-v1','key',encode(decode(repeat('11',32),'hex'),'base64')));
do $$ begin
    begin
        perform public.register_chat_device((select id from live_chat_test_match),'a7fa0000-0000-4000-8000-000000001002',
            jsonb_build_object('protocol','hpke-auth-x25519-v1','key',encode(decode(repeat('22',32),'hex'),'base64')));
        raise exception 'Replacement unexpectedly accepted';
    exception when raise_exception then
        if SQLERRM <> 'Device replacement confirmation required' then raise; end if;
        perform pg_temp.check_test(true,'Replacing device requires explicit confirmation');
    end;
end; $$;
select public.register_chat_device((select id from live_chat_test_match),'a7fa0000-0000-4000-8000-000000001002',
    jsonb_build_object('protocol','hpke-auth-x25519-v1','key',encode(decode(repeat('22',32),'hex'),'base64')),true);
select pg_temp.check_test((select count(*)=1 from public.match_key_bundles where match_id=(select id from live_chat_test_match) and user_id=auth.uid() and revoked_at is null),'Exactly one current device after rotation');
select pg_temp.check_test(exists(select 1 from public.match_key_bundles where device_id='a7fa0000-0000-4000-8000-000000001001' and revoked_at is not null),'Old public key retained as revoked');
select set_config('request.jwt.claim.sub','a7fa0000-0000-4000-8000-000000000102',true);
select public.register_chat_device((select id from live_chat_test_match),'a7fa0000-0000-4000-8000-000000001003',
    jsonb_build_object('protocol','hpke-auth-x25519-v1','key',encode(decode(repeat('33',32),'hex'),'base64')));
select set_config('request.jwt.claim.sub','a7fa0000-0000-4000-8000-000000000103',true);
do $$ begin
    begin
        perform public.send_encrypted_message((select id from live_chat_test_match),gen_random_uuid(),
            'a7fa0000-0000-4000-8000-000000001001','a7fa0000-0000-4000-8000-000000001003','revoked','hpke-auth-x25519-v1');
        raise exception 'Revoked device unexpectedly sent';
    exception when raise_exception then
        if SQLERRM <> 'Both device key bundles required' then raise; end if;
        perform pg_temp.check_test(true,'Revoked sender cannot send new message');
    end;
end; $$;
select public.send_encrypted_message((select id from live_chat_test_match),gen_random_uuid(),
    'a7fa0000-0000-4000-8000-000000001002','a7fa0000-0000-4000-8000-000000001003','opaque-hpke-envelope','hpke-auth-x25519-v1');
select pg_temp.check_test(exists(select 1 from public.encrypted_messages where match_id=(select id from live_chat_test_match) and protocol_version='hpke-auth-x25519-v1'),'Current devices can exchange HPKE envelopes');
select public.report_match((select id from live_chat_test_match),'spam','Transactional test report');
select pg_temp.check_test((select count(*)=1 from public.match_reports where match_id=(select id from live_chat_test_match)),'Participant can submit server-backed report');
select set_config('request.jwt.claim.sub','a7fa0000-0000-4000-8000-000000000101',true);
select pg_temp.check_test(public.current_chat_match() is null,'Unmatched account has no chat projection');
select pg_temp.check_test((select count(*)=0 from public.match_reports),'Report hidden from third party');
do $$ begin
    begin
        perform public.report_match((select id from live_chat_test_match),'spam','Third party');
        raise exception 'Third party submitted report';
    exception when insufficient_privilege then perform pg_temp.check_test(true,'Third party cannot report unrelated match'); end;
end; $$;
reset role;
-- The SELECT is the final result set shown by SQL Editor, even after ROLLBACK.
select name, 'PASS' as result, count(*) over () as total_passed from matching_test_results order by name;
rollback;
