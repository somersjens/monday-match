-- Deleting a profile removes the signed-in account itself. Every row that
-- belongs to it follows through the existing foreign keys:
--   profiles (cascade) -> profiles_matching_deleted trigger leaves the pool,
--     ends an active match and returns the partner to the pool;
--   match_key_bundles, encrypted_messages, match_reports and
--     verification_attempts (cascade); matches keep no reference (set null).
-- Profile photos must be removed through the Storage API first: Storage does
-- not allow deleting its objects with SQL. App Store purchases are tied to the
-- Apple ID, not to this account, and are unaffected.
begin;
create function public.delete_account() returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
    if uid is null then raise exception 'Not signed in'; end if;
    delete from auth.users where id = uid;
end;
$$;
revoke all on function public.delete_account() from public, anon, authenticated;
grant execute on function public.delete_account() to authenticated;
commit;
