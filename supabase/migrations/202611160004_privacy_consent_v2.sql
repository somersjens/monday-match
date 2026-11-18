-- Stop Swiping: accept the current privacy consent version.
--
-- Runs after 202611160003_match_partner_photo.sql. The app's privacy copy
-- moved to version 2026-11-15.v2 (PrivacyConsentKind.version), but the
-- server still required 2026-11-14.v1. Every profile that accepted the new
-- copy dropped out of the matching pool, and begin_photo_verification
-- refused to start a scan ("Selected photo unavailable"), so no check ever
-- reached AWS. Only consent to the current copy counts: the app asks anyone
-- who accepted 2026-11-14.v1 to accept again. Only the version checks
-- change; both function bodies are otherwise the baseline's.
begin;

create or replace function matching_private.eligible(p jsonb, b jsonb) returns boolean
language plpgsql stable set search_path = '' as $$
declare q text; a jsonb; habit text; years integer;
begin
    if not coalesce((p->>'autoMatchingEnabled')::boolean, false)
        or not coalesce((p->>'profileComplete')::boolean, false)
        or b #>> '{state,profilePrivacyConsent,version}' is distinct from '2026-11-15.v2'
        or b #>> '{state,storedAutoMatching,privacyConsent,version}' is distinct from '2026-11-15.v2'
        or coalesce((b #>> '{state,isUnderageLocked}')::boolean, false)
        or nullif(trim(p->>'displayName'), '') is null then return false; end if;
    years := extract(year from age(current_date, ((p->>'dateOfBirth')::timestamptz at time zone 'UTC')::date));
    if years is null or years < 18 or years > 120
        or p->>'gender' is null or jsonb_array_length(p->'interestedIn') = 0
        or jsonb_array_length(p->'languages') = 0
        or (p->>'heightCentimeters')::integer not between 50 and 250
        or (p->>'ownAttractiveness')::integer not between 1 and 10
        or (p->>'partnerMinimumAttractiveness')::integer not between 1 and 10
        or (p->>'minimumMatchPercent')::integer not between 50 and 90
        or (p->>'coarseLatitude')::numeric not between -90 and 90
        or (p->>'coarseLongitude')::numeric not between -180 and 180
        or (p->>'preferredRadiusKilometers')::integer <= 0
        or (p->>'preferredPartnerMinimumAge')::integer < 18
        or (p->>'preferredPartnerMaximumAge')::integer < (p->>'preferredPartnerMinimumAge')::integer
        or not coalesce(p #>> '{lifestyle,hasChildren}' in ('true','false'), false)
        or not coalesce(p #>> '{lifestyle,openToPartnerWithChildren}' in ('true','false'), false)
        or not coalesce(p #>> '{lifestyle,futureChildren}' in ('yes','no','notSure'), false)
        then return false; end if;
    if not (p ?& array['gender','interestedIn','languages','heightCentimeters','ownAttractiveness',
        'partnerMinimumAttractiveness','minimumMatchPercent','coarseLatitude','coarseLongitude',
        'preferredRadiusKilometers','preferredPartnerMinimumAge','preferredPartnerMaximumAge',
        'religion','acceptedPartnerReligions'])
        or exists (select 1 from jsonb_each(p) e where e.key = any(array['gender','heightCentimeters',
            'ownAttractiveness','partnerMinimumAttractiveness','minimumMatchPercent','preferredRadiusKilometers','coarseLatitude','coarseLongitude',
            'preferredPartnerMinimumAge','preferredPartnerMaximumAge',
            'religion','acceptedPartnerReligions']) and e.value = 'null'::jsonb)
        then return false; end if;
    foreach q in array matching_private.question_ids() loop
        a := matching_private.answer(p,q);
        if not coalesce((a->>'own')::integer between 1 and 5
            and (a->>'partner')::integer between 1 and 5
            and (a->>'importance')::integer between 1 and 5, false) then return false; end if;
    end loop;
    foreach habit in array array['alcohol','smoking','drugs'] loop
        a := p #> array['lifestyle','substances',habit];
        if not coalesce((a->>'ownLevel')::integer between 0 and 5
            and (a->>'partnerMaximumLevel')::integer between 0 and 5, false) then return false; end if;
    end loop;
    return true;
exception when data_exception then return false;
end;
$$;

create or replace function public.begin_photo_verification(p_photo_id uuid,p_consent_version text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); object storage.objects%rowtype; attempt matching_private.verification_attempts%rowtype;
begin
    if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
    if p_consent_version is distinct from '2026-11-14.aws.v1' then raise exception 'AWS verification consent required'; end if;
    perform pg_catalog.pg_advisory_xact_lock(hashtextextended('photo-verification:'||uid::text,0));
    if (select count(*) from matching_private.verification_attempts where user_id=uid and created_at>now()-interval '1 day')>=5 then
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

commit;
