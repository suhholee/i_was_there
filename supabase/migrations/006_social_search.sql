-- Phase 2 social: user search + public profile viewing (games visible when profile is public).

create or replace function public.can_view_user_games(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        auth.uid() is not null
        and (
            auth.uid() = target_user_id
            or exists (
                select 1
                from public.profiles p
                where p.user_id = target_user_id
                  and p.profile_visibility = 'public'
            )
        );
$$;

grant execute on function public.can_view_user_games(uuid) to authenticated;

-- Search by @username prefix or display name (signed-in users only).
create or replace function public.search_users(search_query text, result_limit int default 25)
returns table (
    user_id uuid,
    username text,
    display_name text,
    avatar_storage_path text,
    profile_visibility text,
    favorite_team_id int,
    favorite_team_abbr text,
    favorite_kbo_team_id int,
    favorite_kbo_team_abbr text,
    active_league text
)
language plpgsql
security definer
set search_path = public
as $$
declare
    normalized text;
    lim int;
begin
    if auth.uid() is null then
        return;
    end if;

    normalized := lower(trim(both '@' from trim(coalesce(search_query, ''))));
    lim := greatest(1, least(coalesce(result_limit, 25), 50));

    if length(normalized) < 2 then
        return;
    end if;

    return query
    select
        p.user_id,
        p.username,
        p.display_name,
        p.avatar_storage_path,
        p.profile_visibility,
        p.favorite_team_id,
        p.favorite_team_abbr,
        p.favorite_kbo_team_id,
        p.favorite_kbo_team_abbr,
        p.active_league
    from public.profiles p
    where p.username is not null
      and (
          lower(p.username) like normalized || '%'
          or lower(p.display_name) like '%' || normalized || '%'
      )
    order by
        case when lower(p.username) = normalized then 0
             when lower(p.username) like normalized || '%' then 1
             else 2 end,
        lower(p.username)
    limit lim;
end;
$$;

grant execute on function public.search_users(text, int) to authenticated;

-- Full profile card for another user.
create or replace function public.get_user_profile(target_user_id uuid)
returns table (
    user_id uuid,
    username text,
    display_name text,
    avatar_storage_path text,
    profile_visibility text,
    favorite_team_id int,
    favorite_team_abbr text,
    favorite_kbo_team_id int,
    favorite_kbo_team_abbr text,
    active_league text,
    favorite_player_ids int[],
    favorite_player_meta_json text,
    can_view_games boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is null then
        return;
    end if;

    return query
    select
        p.user_id,
        p.username,
        p.display_name,
        p.avatar_storage_path,
        p.profile_visibility,
        p.favorite_team_id,
        p.favorite_team_abbr,
        p.favorite_kbo_team_id,
        p.favorite_kbo_team_abbr,
        p.active_league,
        p.favorite_player_ids,
        p.favorite_player_meta_json,
        public.can_view_user_games(p.user_id) as can_view_games
    from public.profiles p
    where p.user_id = target_user_id
      and p.username is not null;
end;
$$;

grant execute on function public.get_user_profile(uuid) to authenticated;

create or replace function public.get_user_profile_by_username(target_username text)
returns table (
    user_id uuid,
    username text,
    display_name text,
    avatar_storage_path text,
    profile_visibility text,
    favorite_team_id int,
    favorite_team_abbr text,
    favorite_kbo_team_id int,
    favorite_kbo_team_abbr text,
    active_league text,
    favorite_player_ids int[],
    favorite_player_meta_json text,
    can_view_games boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
    normalized text;
    target_id uuid;
begin
    if auth.uid() is null then
        return;
    end if;

    normalized := lower(trim(both '@' from trim(coalesce(target_username, ''))));

    select p.user_id into target_id
    from public.profiles p
    where lower(p.username) = normalized
    limit 1;

    if target_id is null then
        return;
    end if;

    return query
    select *
    from public.get_user_profile(target_id);
end;
$$;

grant execute on function public.get_user_profile_by_username(text) to authenticated;

-- Attended games for a user when visible to the viewer.
create or replace function public.list_user_attended_games(target_user_id uuid)
returns setof public.attended_games
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.can_view_user_games(target_user_id) then
        return;
    end if;

    return query
    select g.*
    from public.attended_games g
    where g.user_id = target_user_id
    order by g.game_date desc;
end;
$$;

grant execute on function public.list_user_attended_games(uuid) to authenticated;

create or replace function public.list_user_game_friends(p_game_id uuid)
returns table (name text)
language plpgsql
security definer
set search_path = public
as $$
declare
    owner_id uuid;
begin
    select g.user_id into owner_id
    from public.attended_games g
    where g.id = p_game_id;

    if owner_id is null or not public.can_view_user_games(owner_id) then
        return;
    end if;

    return query
    select gf.name
    from public.game_friends gf
    where gf.game_id = p_game_id
    order by gf.name;
end;
$$;

grant execute on function public.list_user_game_friends(uuid) to authenticated;

create or replace function public.list_user_game_photos(p_game_id uuid)
returns table (storage_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
    owner_id uuid;
begin
    select g.user_id into owner_id
    from public.attended_games g
    where g.id = p_game_id;

    if owner_id is null or not public.can_view_user_games(owner_id) then
        return;
    end if;

    return query
    select gp.storage_path
    from public.game_photos gp
    where gp.game_id = p_game_id
    order by gp.created_at;
end;
$$;

grant execute on function public.list_user_game_photos(uuid) to authenticated;

-- Allow signed-in users to view avatars and game photos returned by the RPCs above.
-- Run after the `avatars` and `game-photos` buckets exist.
--
-- create policy "avatars_storage_select_social" on storage.objects
--   for select to authenticated
--   using (bucket_id = 'avatars');
--
-- create policy "game_photos_storage_select_social" on storage.objects
--   for select to authenticated
--   using (bucket_id = 'game-photos');
