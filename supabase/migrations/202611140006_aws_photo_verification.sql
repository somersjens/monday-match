begin;
create table matching_private.verification_attempts (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    photo_id uuid not null,
    object_id uuid not null references storage.objects(id) on delete cascade,
    object_updated_at timestamptz not null,
    aws_session_id text unique,
    status text not null default 'pending' check(status in ('pending','verified','rejected','expired')),
    consent_version text not null,
    created_at timestamptz not null default now(),
    expires_at timestamptz not null default now()+interval '3 minutes',
    completed_at timestamptz
);
create index verification_attempt_user on matching_private.verification_attempts(user_id,created_at desc);
alter table matching_private.verification_attempts enable row level security;
revoke all on matching_private.verification_attempts from public,anon,authenticated;

create function public.begin_photo_verification(p_photo_id uuid,p_consent_version text) returns jsonb
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
        and backup #>> '{state,profilePrivacyConsent,version}'='2026-11-14.v1') then
        raise exception 'Selected photo unavailable'; end if;
    select * into object from storage.objects where bucket_id='profile-photos' and name=uid::text||'/'||p_photo_id::text||'.jpg';
    if not found then raise exception 'Photo upload must finish first'; end if;
    insert into matching_private.verification_attempts(user_id,photo_id,object_id,object_updated_at,consent_version)
        values(uid,p_photo_id,object.id,object.updated_at,p_consent_version) returning * into attempt;
    return jsonb_build_object('request_id',attempt.id,'expires_at',attempt.expires_at);
end; $$;

-- These worker functions are callable only with the server's service-role key.
-- No browser/iPhone may choose or attest a verification outcome.
create function public.photo_verification_worker_request(p_request_id uuid,p_user_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare a matching_private.verification_attempts%rowtype;
begin
    select * into a from matching_private.verification_attempts where id=p_request_id and user_id=p_user_id;
    if not found then raise exception 'Verification unavailable' using errcode='42501'; end if;
    return jsonb_build_object('request_id',a.id,'status',a.status,'aws_session_id',a.aws_session_id,
        'expires_at',a.expires_at,'path',a.user_id::text||'/'||a.photo_id::text||'.jpg',
        'photo_current',exists(select 1 from storage.objects o join public.profiles p on p.id=a.user_id
            where o.id=a.object_id and o.updated_at=a.object_updated_at
            and lower(p.backup #>> '{state,storedAutoMatching,photoID}')=a.photo_id::text));
end; $$;
create function public.bind_photo_verification_session(p_request_id uuid,p_user_id uuid,p_session_id text) returns void
language plpgsql security definer set search_path='' as $$ begin
    update matching_private.verification_attempts set aws_session_id=p_session_id where id=p_request_id and user_id=p_user_id
        and status='pending' and expires_at>now() and (aws_session_id is null or aws_session_id=p_session_id);
    if not found then raise exception 'Verification expired or already bound'; end if;
end; $$;
create function public.complete_photo_verification(p_request_id uuid,p_user_id uuid,p_session_id text,p_passed boolean) returns boolean
language plpgsql security definer set search_path='' as $$
declare a matching_private.verification_attempts%rowtype; valid boolean;
begin
    -- Same lock/order as matching: never hold an object or attempt lock while waiting for the engine.
    perform pg_catalog.pg_advisory_xact_lock(724310261114::bigint);
    select * into a from matching_private.verification_attempts where id=p_request_id and user_id=p_user_id for update;
    if not found or a.aws_session_id is distinct from p_session_id or p_session_id is null then
        raise exception 'Verification session mismatch' using errcode='42501'; end if;
    valid:=exists(select 1 from storage.objects o join public.profiles p on p.id=a.user_id
        where o.id=a.object_id and o.updated_at=a.object_updated_at
        and lower(p.backup #>> '{state,storedAutoMatching,photoID}')=a.photo_id::text);
    if a.status='verified' then return valid; end if;
    if a.status<>'pending' then return false; end if;
    if a.expires_at<=now() then
        update matching_private.verification_attempts set status='expired',completed_at=now() where id=a.id; return false;
    end if;
    if p_passed is true and valid then
        insert into matching_private.photo_verifications(object_id,object_updated_at)
            values(a.object_id,a.object_updated_at) on conflict(object_id) do update
                set object_updated_at=excluded.object_updated_at,verified_at=now();
        update matching_private.verification_attempts set status='verified',completed_at=now() where id=a.id;
        perform matching_private.reconcile(a.user_id);
        return true;
    end if;
    update matching_private.verification_attempts set status='rejected',completed_at=now() where id=a.id;
    return false;
end; $$;
revoke all on function public.begin_photo_verification(uuid,text),public.photo_verification_worker_request(uuid,uuid),
    public.bind_photo_verification_session(uuid,uuid,text),public.complete_photo_verification(uuid,uuid,text,boolean)
    from public,anon,authenticated;
grant execute on function public.begin_photo_verification(uuid,text) to authenticated;
grant execute on function public.photo_verification_worker_request(uuid,uuid),public.bind_photo_verification_session(uuid,uuid,text),
    public.complete_photo_verification(uuid,uuid,text,boolean) to service_role;
notify pgrst,'reload schema';
commit;
