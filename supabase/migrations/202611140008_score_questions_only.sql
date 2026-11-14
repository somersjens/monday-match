-- Scores count only the 50 compatibility questions. Alcohol, smoking and drugs
-- stay hard limits (a candidate above the seeker's maximum is never matched)
-- but no longer weigh in the percentage, matching MatchReport in the app.
begin;
create or replace function matching_private.directional_score(s jsonb, c jsonb) returns integer
language plpgsql stable set search_path = '' as $$
declare q text; a jsonb; ca jsonb; habit text; years integer; d double precision;
    w numeric; total numeric := 0; weights numeric := 0; n integer := 0;
begin
    years := extract(year from age(current_date, ((c->>'dateOfBirth')::timestamptz at time zone 'UTC')::date));
    if not (s->'interestedIn' ? (c->>'gender'))
        or years not between (s->>'preferredPartnerMinimumAge')::integer and (s->>'preferredPartnerMaximumAge')::integer
        or (c->>'heightCentimeters')::integer not between coalesce((s->>'preferredPartnerMinimumHeight')::integer,50) and coalesce((s->>'preferredPartnerMaximumHeight')::integer,250)
        or not (s->'acceptedPartnerReligions' ? (c->>'religion'))
        or not exists (select 1 from jsonb_array_elements_text(s->'languages') l(value) where c->'languages' ? l.value)
        or (c->>'ownAttractiveness')::integer < (s->>'partnerMinimumAttractiveness')::integer
        or (s #>> '{lifestyle,openToPartnerWithChildren}' = 'false' and c #>> '{lifestyle,hasChildren}' = 'true')
        or (s #>> '{lifestyle,futureChildren}' = 'yes' and c #>> '{lifestyle,futureChildren}' = 'no')
        or (s #>> '{lifestyle,futureChildren}' = 'no' and c #>> '{lifestyle,futureChildren}' = 'yes')
        then return null; end if;
    -- The selected arrangement is an explicit mutual requirement.
    if not exists (select 1 from jsonb_array_elements_text(s #> '{relationshipPreferences,sexualArrangement}') x(value)
        where c #> '{relationshipPreferences,sexualArrangement}' ? x.value) then return null; end if;
    d := 6371.0088 * 2 * asin(sqrt(least(1.0, greatest(0.0,
        power(sin(radians((c->>'coarseLatitude')::double precision - (s->>'coarseLatitude')::double precision)/2),2)
        + cos(radians((s->>'coarseLatitude')::double precision)) * cos(radians((c->>'coarseLatitude')::double precision))
        * power(sin(radians((c->>'coarseLongitude')::double precision - (s->>'coarseLongitude')::double precision)/2),2)))));
    if d > (s->>'preferredRadiusKilometers')::double precision then return null; end if;
    -- Habits: only the seeker's maximum, never part of the score.
    foreach habit in array array['alcohol','smoking','drugs'] loop
        if (c #>> array['lifestyle','substances',habit,'ownLevel'])::integer
            > (s #>> array['lifestyle','substances',habit,'partnerMaximumLevel'])::integer then return null; end if;
    end loop;
    foreach q in array matching_private.question_ids() loop
        a := matching_private.answer(s,q); ca := matching_private.answer(c,q);
        w := (array[0,1,2,4,8])[(a->>'importance')::integer];
        total := total + w * (1 - abs((ca->>'own')::integer - (a->>'partner')::integer)/4.0);
        weights := weights + w; n := n+1;
    end loop;
    return case when weights > 0 then round(total/weights*100)::integer when n > 0 then 100 else 0 end;
exception when data_exception then return null;
end;
$$;
commit;
