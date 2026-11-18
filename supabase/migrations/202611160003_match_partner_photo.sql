-- Stop Swiping: the other person's photo in an active match.
--
-- Runs after 202611160002_push_notifications.sql. The privacy policy already
-- says a match receives the profile name and photo; until now only the name
-- reached the other phone.
--
-- Only the photo chosen for automatic matching is shared, only with the
-- person someone is matched with, and only while that match is active. A
-- broken match keeps its conversation, not the photo. Whether the photo was
-- verified with a live scan comes from the same server-side attestation the
-- pool uses; a phone can never claim it.
begin;

-- The partner's current matching photo, as a Storage object name, when it
-- exists. Lower-cased the way the app uploads it.
create function matching_private.matching_photo_name(uid uuid) returns text
language sql stable security definer set search_path = '' as $$
    select o.name from public.profiles p
        join storage.objects o on o.bucket_id = 'profile-photos'
            and o.name = uid::text || '/' || lower(p.backup #>> '{state,storedAutoMatching,photoID}') || '.jpg'
        where p.id = uid;
$$;

-- One match as the app shows it, active or ended. Adds the partner's photo
-- and whether it was verified, for an active match only.
create or replace function matching_private.match_summary(m public.matches, uid uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
    select jsonb_build_object(
        'id', m.id,
        'partner_id', partner.id,
        'partner_name', coalesce(pr.profile->>'displayName', ''),
        'own_score', case when m.user_low = uid then m.score_low else m.score_high end,
        'partner_score', case when m.user_low = uid then m.score_high else m.score_low end,
        'matched_at', m.matched_at,
        'ended_at', m.ended_at,
        'end_reason', m.end_reason,
        'ended_by_me', coalesce(m.ended_by = uid, false),
        'partner_card', card.card,
        'partner_photo', photo.name,
        'partner_photo_verified', photo.name is not null and matching_private.has_verified_photo(
            partner.id, lower(pr.backup #>> '{state,storedAutoMatching,photoID}')),
        'unread_count', (select count(*) from public.encrypted_messages e
            where e.match_id = m.id and e.sender_id = partner.id
            and e.id > coalesce(own_read.last_read_message_id, 0)),
        'last_message_at', (select max(e.created_at) from public.encrypted_messages e where e.match_id = m.id),
        'partner_read_at', (select e.created_at from public.encrypted_messages e
            where e.id = partner_read.last_read_message_id))
    from (select case when m.user_low = uid then m.user_high else m.user_low end as id) partner
    left join public.profiles pr on pr.id = partner.id
    left join public.match_cards card on card.match_id = m.id and card.user_id = partner.id
    left join lateral (select matching_private.matching_photo_name(partner.id) as name
        where m.ended_at is null) photo on true
    left join public.match_read_states own_read on own_read.match_id = m.id and own_read.user_id = uid
    left join public.match_read_states partner_read on partner_read.match_id = m.id and partner_read.user_id = partner.id;
$$;

-- Storage asks this for every read of someone else's photo: only the
-- matching photo of the person this account is matched with right now.
create function public.can_view_match_photo(p_name text) returns boolean
language sql stable security definer set search_path = '' as $$
    select exists (
        select 1 from matching_private.matched_users mine
            join public.matches m on m.id = mine.match_id and m.ended_at is null
        where mine.user_id = (select auth.uid())
            and p_name = matching_private.matching_photo_name(
                case when m.user_low = mine.user_id then m.user_high else m.user_low end));
$$;
revoke all on function public.can_view_match_photo(text) from public, anon;
grant execute on function public.can_view_match_photo(text) to authenticated;
revoke all on function matching_private.matching_photo_name(uuid) from public, anon, authenticated;

create policy "Read active match partner photo" on storage.objects
    for select to authenticated using (
        bucket_id = 'profile-photos' and public.can_view_match_photo(name));

commit;
