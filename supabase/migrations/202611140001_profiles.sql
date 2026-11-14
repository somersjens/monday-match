-- Private profile backups and matching data, owned by the signed-in user.
begin;
create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    profile jsonb not null,
    backup jsonb,
    updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
revoke all on public.profiles from anon;
grant select, insert, update, delete on public.profiles to authenticated;

create policy "Read own profile" on public.profiles
    for select to authenticated using ((select auth.uid()) = id);
create policy "Insert own profile" on public.profiles
    for insert to authenticated with check ((select auth.uid()) = id);
create policy "Update own profile" on public.profiles
    for update to authenticated using ((select auth.uid()) = id)
    with check ((select auth.uid()) = id);
create policy "Delete own profile" on public.profiles
    for delete to authenticated using ((select auth.uid()) = id);

create function public.set_profile_updated_at() returns trigger
language plpgsql set search_path = '' as $$
begin
    new.updated_at = now();
    return new;
end;
$$;
create trigger profiles_updated_at before update on public.profiles
    for each row execute function public.set_profile_updated_at();

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-photos', 'profile-photos', false, 10485760, array['image/jpeg']);

create policy "Read own profile photos" on storage.objects
    for select to authenticated using (
        bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text
    );
create policy "Upload own profile photos" on storage.objects
    for insert to authenticated with check (
        bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text
    );
create policy "Update own profile photos" on storage.objects
    for update to authenticated using (
        bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text
    ) with check (
        bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text
    );
create policy "Delete own profile photos" on storage.objects
    for delete to authenticated using (
        bucket_id = 'profile-photos' and (storage.foldername(name))[1] = (select auth.uid())::text
    );
commit;
