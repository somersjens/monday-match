begin;
alter table public.match_key_bundles add column revoked_at timestamptz;
create unique index one_active_chat_device on public.match_key_bundles(match_id,user_id) where revoked_at is null;
alter table public.encrypted_messages drop constraint encrypted_messages_protocol_version_check;
alter table public.encrypted_messages add constraint encrypted_messages_protocol_version_check
    check (protocol_version in ('e2ee-v1','hpke-auth-x25519-v1'));

create function public.current_chat_match() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare uid uuid:=auth.uid(); result jsonb;
begin
    if uid is null then raise exception 'Authentication required' using errcode='42501'; end if;
    select jsonb_build_object('id',m.id,'partner_id',p.id,'partner_name',p.profile->>'displayName',
        'own_score',case when m.user_low=uid then m.score_low else m.score_high end,
        'partner_score',case when m.user_low=uid then m.score_high else m.score_low end)
        into result from matching_private.active_members a join public.matches m on m.id=a.match_id
        join public.profiles p on p.id=case when m.user_low=uid then m.user_high else m.user_low end
        where a.user_id=uid and m.ended_at is null;
    return result;
end; $$;

create function public.register_chat_device(p_match_id uuid,p_device_id uuid,p_public_bundle jsonb,
    p_replace_device boolean default false) returns void
language plpgsql security definer set search_path='' as $$
begin
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    if auth.uid() is null or not exists(select 1 from public.matches where id=p_match_id and ended_at is null
        and auth.uid() in (user_low,user_high)) then raise exception 'Active match required' using errcode='42501'; end if;
    if p_public_bundle->>'protocol' is distinct from 'hpke-auth-x25519-v1'
        or octet_length(decode(p_public_bundle->>'key','base64')) is distinct from 32 then
        raise exception 'Invalid public key bundle'; end if;
    if exists(select 1 from public.match_key_bundles where match_id=p_match_id and user_id=auth.uid()
        and device_id=p_device_id and revoked_at is not null) then raise exception 'Device revoked'; end if;
    if exists(select 1 from public.match_key_bundles where match_id=p_match_id and user_id=auth.uid()
        and device_id<>p_device_id and revoked_at is null) then
        if not p_replace_device then raise exception 'Device replacement confirmation required'; end if;
        update public.match_key_bundles set revoked_at=now() where match_id=p_match_id and user_id=auth.uid()
            and device_id<>p_device_id and revoked_at is null;
    end if;
    perform public.publish_match_key_bundle(p_match_id,p_device_id,p_public_bundle);
end; $$;

create table public.match_reports (
    id uuid primary key default gen_random_uuid(),
    match_id uuid not null references public.matches(id),
    reporter_id uuid not null references auth.users(id) on delete cascade,
    reason text not null check(reason in ('inappropriateContent','harassment','fakeProfile','spam','offlineBehavior','other')),
    details text not null check(octet_length(details)<=8000),
    created_at timestamptz not null default now()
);
alter table public.match_reports enable row level security;
revoke all on public.match_reports from public,anon,authenticated;
grant select on public.match_reports to authenticated;
create policy "Read own match reports" on public.match_reports for select to authenticated
    using (reporter_id=(select auth.uid()));
create function public.report_match(p_match_id uuid,p_reason text,p_details text) returns void
language plpgsql security definer set search_path='' as $$ begin
    if auth.uid() is null or not exists(select 1 from public.matches where id=p_match_id
        and auth.uid() in (user_low,user_high)) then raise exception 'Match unavailable' using errcode='42501'; end if;
    insert into public.match_reports(match_id,reporter_id,reason,details) values(p_match_id,auth.uid(),p_reason,p_details);
end; $$;
create or replace function public.send_encrypted_message(p_match_id uuid, p_client_message_id uuid,
    p_sender_device_id uuid, p_recipient_device_id uuid, p_ciphertext text,
    p_protocol_version text default 'e2ee-v1') returns bigint
language plpgsql security definer set search_path = '' as $$
declare result bigint; existing public.encrypted_messages%rowtype;
begin
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    if auth.uid() is null or not exists(select 1 from public.matches where id=p_match_id
        and ended_at is null and auth.uid() in (user_low,user_high)) then
        raise exception 'Active match required' using errcode='42501'; end if;
    if not exists(select 1 from public.match_key_bundles where match_id=p_match_id
        and user_id=auth.uid() and device_id=p_sender_device_id and revoked_at is null)
        or not exists(select 1 from public.match_key_bundles where match_id=p_match_id
        and user_id<>auth.uid() and device_id=p_recipient_device_id and revoked_at is null) then
        raise exception 'Both device key bundles required'; end if;
    insert into public.encrypted_messages(match_id,sender_id,client_message_id,sender_device_id,
        recipient_device_id,ciphertext,protocol_version)
        values(p_match_id,auth.uid(),p_client_message_id,p_sender_device_id,p_recipient_device_id,p_ciphertext,p_protocol_version)
        on conflict (match_id,sender_id,client_message_id) do nothing returning id into result;
    if result is not null then return result; end if;
    select * into existing from public.encrypted_messages where match_id=p_match_id
        and sender_id=auth.uid() and client_message_id=p_client_message_id;
    if existing.ciphertext is distinct from p_ciphertext or existing.sender_device_id is distinct from p_sender_device_id
        or existing.recipient_device_id is distinct from p_recipient_device_id or existing.protocol_version is distinct from p_protocol_version then
        raise exception 'Message identifier already used'; end if;
    return existing.id;
end;
$$;


revoke all on function public.current_chat_match(),public.register_chat_device(uuid,uuid,jsonb,boolean),public.report_match(uuid,text,text)
    from public,anon,authenticated;
grant execute on function public.current_chat_match(),public.register_chat_device(uuid,uuid,jsonb,boolean),public.report_match(uuid,text,text)
    to authenticated;
notify pgrst,'reload schema';
commit;
