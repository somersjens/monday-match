-- The match screen and its conversation.
--   * match_cards: each participant shares the same compact profile code a
--     QR exchange would show, so the other side can draw the match heart,
--     both scores and the answers behind them. The server never parses it.
--   * match_read_states: how far each participant has read, for unread
--     badges and read receipts. Messages themselves stay end-to-end encrypted.
--   * Reports gain more reasons and can break the match in the same call.
--   * current_chat_match() returns everything the home card needs at once.
begin;

create table public.match_cards (
    match_id uuid not null references public.matches(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    -- Base64 of ProfileCode.encoded(sharedCopy): age only, ~1 km location.
    card text not null check (octet_length(card) between 1 and 4096),
    shared_at timestamptz not null default now(),
    primary key (match_id, user_id)
);

create table public.match_read_states (
    match_id uuid not null references public.matches(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    last_read_message_id bigint not null default 0,
    read_at timestamptz not null default now(),
    primary key (match_id, user_id)
);

alter table public.match_cards enable row level security;
alter table public.match_read_states enable row level security;
revoke all on public.match_cards, public.match_read_states from public, anon, authenticated;
grant select on public.match_cards, public.match_read_states to authenticated;
create policy "Participants read match cards" on public.match_cards for select to authenticated
    using (exists (select 1 from public.matches m where m.id = match_id
        and (select auth.uid()) in (m.user_low, m.user_high)));
create policy "Participants read read states" on public.match_read_states for select to authenticated
    using (exists (select 1 from public.matches m where m.id = match_id
        and (select auth.uid()) in (m.user_low, m.user_high)));

-- The card is frozen once shared, like a saved match on the phone: scores
-- and answers stay as they were on the day of the match.
create function public.share_match_card(p_match_id uuid, p_card text) returns void
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null or not exists(select 1 from public.matches where id = p_match_id
        and ended_at is null and auth.uid() in (user_low, user_high)) then
        raise exception 'Active match required' using errcode = '42501'; end if;
    if p_card is null or octet_length(p_card) not between 1 and 4096 then
        raise exception 'Invalid match card'; end if;
    insert into public.match_cards(match_id, user_id, card) values(p_match_id, auth.uid(), p_card)
        on conflict (match_id, user_id) do nothing;
end; $$;

-- Read positions only move forward and only to messages of this match.
create function public.mark_chat_read(p_match_id uuid, p_message_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null or not exists(select 1 from public.matches where id = p_match_id
        and auth.uid() in (user_low, user_high)) then
        raise exception 'Match unavailable' using errcode = '42501'; end if;
    if not exists(select 1 from public.encrypted_messages where id = p_message_id and match_id = p_match_id) then
        raise exception 'Message unavailable'; end if;
    insert into public.match_read_states(match_id, user_id, last_read_message_id, read_at)
        values(p_match_id, auth.uid(), p_message_id, now())
        on conflict (match_id, user_id) do update
            set last_read_message_id = greatest(public.match_read_states.last_read_message_id, excluded.last_read_message_id),
                read_at = case when excluded.last_read_message_id > public.match_read_states.last_read_message_id
                    then now() else public.match_read_states.read_at end;
end; $$;

drop function public.current_chat_match();
create function public.current_chat_match() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid(); result jsonb;
begin
    if uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
    select jsonb_build_object(
        'id', m.id,
        'partner_id', p.id,
        'partner_name', p.profile->>'displayName',
        'own_score', case when m.user_low = uid then m.score_low else m.score_high end,
        'partner_score', case when m.user_low = uid then m.score_high else m.score_low end,
        'matched_at', m.matched_at,
        'partner_card', card.card,
        'unread_count', (select count(*) from public.encrypted_messages e
            where e.match_id = m.id and e.sender_id = p.id
            and e.id > coalesce(own_read.last_read_message_id, 0)),
        'last_message_at', (select max(e.created_at) from public.encrypted_messages e where e.match_id = m.id),
        'partner_read_at', (select e.created_at from public.encrypted_messages e
            where e.id = partner_read.last_read_message_id))
        into result
        from matching_private.active_members a
        join public.matches m on m.id = a.match_id
        join public.profiles p on p.id = case when m.user_low = uid then m.user_high else m.user_low end
        left join public.match_cards card on card.match_id = m.id and card.user_id = p.id
        left join public.match_read_states own_read on own_read.match_id = m.id and own_read.user_id = uid
        left join public.match_read_states partner_read on partner_read.match_id = m.id and partner_read.user_id = p.id
        where a.user_id = uid and m.ended_at is null;
    return result;
end; $$;

-- More reasons, and the option to break the match with the report.
alter table public.match_reports drop constraint match_reports_reason_check;
alter table public.match_reports add constraint match_reports_reason_check
    check (reason in ('inappropriateContent', 'harassment', 'fakeProfile', 'spam', 'offlineBehavior',
                      'underage', 'hateSpeech', 'other'));
alter table public.match_reports add column ended_match boolean not null default false;
create index match_reports_match on public.match_reports(match_id, created_at desc);

drop function public.report_match(uuid, text, text);
create function public.report_match(p_match_id uuid, p_reason text, p_details text,
    p_end_match boolean default false) returns void
language plpgsql security definer set search_path = '' as $$
begin
    if auth.uid() is null or not exists(select 1 from public.matches where id = p_match_id
        and auth.uid() in (user_low, user_high)) then
        raise exception 'Match unavailable' using errcode = '42501'; end if;
    -- One report per reason per hour keeps a single person from flooding moderation.
    if not exists(select 1 from public.match_reports where match_id = p_match_id and reporter_id = auth.uid()
        and reason = p_reason and created_at > now() - interval '1 hour') then
        insert into public.match_reports(match_id, reporter_id, reason, details, ended_match)
            values(p_match_id, auth.uid(), p_reason, coalesce(p_details, ''), coalesce(p_end_match, false));
    end if;
    if coalesce(p_end_match, false) then
        perform public.end_match(p_match_id, 'blocked');
    end if;
end; $$;

revoke all on function public.share_match_card(uuid, text), public.mark_chat_read(uuid, bigint),
    public.current_chat_match(), public.report_match(uuid, text, text, boolean)
    from public, anon, authenticated;
grant execute on function public.share_match_card(uuid, text), public.mark_chat_read(uuid, bigint),
    public.current_chat_match(), public.report_match(uuid, text, text, boolean)
    to authenticated;
notify pgrst, 'reload schema';
commit;
