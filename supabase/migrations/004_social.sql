-- Phase 1 social: @username, optional avatar, public/private profile visibility.

alter table public.profiles
    add column if not exists username text,
    add column if not exists avatar_storage_path text,
    add column if not exists profile_visibility text not null default 'public';

alter table public.profiles
    drop constraint if exists profiles_profile_visibility_check;

alter table public.profiles
    add constraint profiles_profile_visibility_check
    check (profile_visibility in ('public', 'private'));

create unique index if not exists profiles_username_lower_idx
    on public.profiles (lower(username))
    where username is not null;

-- Returns true when `desired` is valid and not taken by another user.
create or replace function public.check_username_available(desired text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
    normalized text;
begin
    normalized := lower(trim(both '@' from trim(coalesce(desired, ''))));

    if length(normalized) < 3 or length(normalized) > 30 then
        return false;
    end if;

    if normalized !~ '^[a-z0-9_]+$' then
        return false;
    end if;

    if normalized in ('admin', 'help', 'iwasthere', 'moderator', 'root', 'support', 'system') then
        return false;
    end if;

    return not exists (
        select 1
        from public.profiles p
        where lower(p.username) = normalized
          and p.user_id <> coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
    );
end;
$$;

grant execute on function public.check_username_available(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Avatars bucket (create in Dashboard → Storage if it does not exist):
--   id: avatars, name: avatars, private
--
-- Policies (run after bucket exists):
-- ---------------------------------------------------------------------------
-- create policy "avatars_storage_select" on storage.objects
--   for select using (
--     bucket_id = 'avatars'
--     and auth.uid()::text = (storage.foldername(name))[1]
--   );
--
-- create policy "avatars_storage_insert" on storage.objects
--   for insert with check (
--     bucket_id = 'avatars'
--     and auth.uid()::text = (storage.foldername(name))[1]
--   );
--
-- create policy "avatars_storage_update" on storage.objects
--   for update using (
--     bucket_id = 'avatars'
--     and auth.uid()::text = (storage.foldername(name))[1]
--   );
--
-- create policy "avatars_storage_delete" on storage.objects
--   for delete using (
--     bucket_id = 'avatars'
--     and auth.uid()::text = (storage.foldername(name))[1]
--   );
