-- Phase 3 social: mutual follows, follow requests, notifications.

create table if not exists public.follows (
    id uuid primary key default gen_random_uuid(),
    follower_id uuid not null references auth.users (id) on delete cascade,
    following_id uuid not null references auth.users (id) on delete cascade,
    status text not null default 'pending' check (status in ('pending', 'accepted')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (follower_id, following_id),
    check (follower_id <> following_id)
);

create index if not exists follows_follower_status_idx
    on public.follows (follower_id, status);

create index if not exists follows_following_status_idx
    on public.follows (following_id, status);

alter table public.follows enable row level security;

create table if not exists public.notifications (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    type text not null check (type in ('follow_request', 'follow_accepted')),
    actor_user_id uuid references auth.users (id) on delete set null,
    reference_id uuid,
    read_at timestamptz,
    created_at timestamptz not null default now()
);

create index if not exists notifications_user_unread_idx
    on public.notifications (user_id, created_at desc)
    where read_at is null;

alter table public.notifications enable row level security;

create or replace function public.are_mutual_follows(user_a uuid, user_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select
        user_a is not null
        and user_b is not null
        and exists (
            select 1
            from public.follows f1
            join public.follows f2
              on f1.follower_id = f2.following_id
             and f1.following_id = f2.follower_id
            where f1.follower_id = user_a
              and f1.following_id = user_b
              and f1.status = 'accepted'
              and f2.status = 'accepted'
        );
$$;

grant execute on function public.are_mutual_follows(uuid, uuid) to authenticated;

-- Private profiles: games visible to mutual follows; public profiles: any signed-in user.
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
                  and (
                      coalesce(p.profile_visibility, 'public') = 'public'
                      or (
                          p.profile_visibility = 'private'
                          and public.are_mutual_follows(auth.uid(), target_user_id)
                      )
                  )
            )
        );
$$;

create or replace function public.get_follow_status(target_user_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then
        return 'none';
    end if;

    if me = target_user_id then
        return 'self';
    end if;

    if public.are_mutual_follows(me, target_user_id) then
        return 'mutual';
    end if;

    if exists (
        select 1
        from public.follows f
        where f.follower_id = me
          and f.following_id = target_user_id
          and f.status = 'pending'
    ) then
        return 'outgoing_pending';
    end if;

    if exists (
        select 1
        from public.follows f
        where f.follower_id = target_user_id
          and f.following_id = me
          and f.status = 'pending'
    ) then
        return 'incoming_pending';
    end if;

    return 'none';
end;
$$;

grant execute on function public.get_follow_status(uuid) to authenticated;

-- Return type changed from 006 (adds follow_status); must drop before recreate.
drop function if exists public.get_user_profile_by_username(text);
drop function if exists public.get_user_profile(uuid);

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
    can_view_games boolean,
    follow_status text
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
        public.can_view_user_games(p.user_id) as can_view_games,
        public.get_follow_status(p.user_id) as follow_status
    from public.profiles p
    where p.user_id = target_user_id
      and p.username is not null;
end;
$$;

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
    can_view_games boolean,
    follow_status text
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

grant execute on function public.get_user_profile(uuid) to authenticated;
grant execute on function public.get_user_profile_by_username(text) to authenticated;

create or replace function public.accept_mutual_follow(requester_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    follow_row public.follows%rowtype;
begin
    if me is null then
        raise exception 'Not authenticated';
    end if;

    if requester_user_id = me then
        raise exception 'Cannot follow yourself';
    end if;

    select *
    into follow_row
    from public.follows f
    where f.follower_id = requester_user_id
      and f.following_id = me
      and f.status = 'pending'
    for update;

    if not found then
        raise exception 'Follow request not found';
    end if;

    update public.follows
    set status = 'accepted', updated_at = now()
    where id = follow_row.id;

    insert into public.follows (follower_id, following_id, status)
    values (me, requester_user_id, 'accepted')
    on conflict (follower_id, following_id)
    do update set status = 'accepted', updated_at = now();

    update public.notifications
    set read_at = now()
    where user_id = me
      and type = 'follow_request'
      and actor_user_id = requester_user_id
      and read_at is null;

    insert into public.notifications (user_id, type, actor_user_id, reference_id)
    values (requester_user_id, 'follow_accepted', me, follow_row.id);
end;
$$;

grant execute on function public.accept_mutual_follow(uuid) to authenticated;

create or replace function public.request_follow(target_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    new_follow_id uuid;
begin
    if me is null then
        raise exception 'Not authenticated';
    end if;

    if target_user_id = me then
        raise exception 'Cannot follow yourself';
    end if;

    if public.are_mutual_follows(me, target_user_id) then
        return 'mutual';
    end if;

    -- If they already requested you, accept immediately.
    if exists (
        select 1
        from public.follows f
        where f.follower_id = target_user_id
          and f.following_id = me
          and f.status = 'pending'
    ) then
        perform public.accept_mutual_follow(target_user_id);
        return 'mutual';
    end if;

    if exists (
        select 1
        from public.follows f
        where f.follower_id = me
          and f.following_id = target_user_id
          and f.status = 'pending'
    ) then
        return 'outgoing_pending';
    end if;

    insert into public.follows (follower_id, following_id, status)
    values (me, target_user_id, 'pending')
    returning id into new_follow_id;

    insert into public.notifications (user_id, type, actor_user_id, reference_id)
    values (target_user_id, 'follow_request', me, new_follow_id);

    return 'outgoing_pending';
end;
$$;

grant execute on function public.request_follow(uuid) to authenticated;

create or replace function public.decline_follow_request(requester_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then
        raise exception 'Not authenticated';
    end if;

    delete from public.follows
    where follower_id = requester_user_id
      and following_id = me
      and status = 'pending';

    update public.notifications
    set read_at = now()
    where user_id = me
      and type = 'follow_request'
      and actor_user_id = requester_user_id
      and read_at is null;
end;
$$;

grant execute on function public.decline_follow_request(uuid) to authenticated;

create or replace function public.cancel_follow_request(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then
        raise exception 'Not authenticated';
    end if;

    delete from public.follows
    where follower_id = me
      and following_id = target_user_id
      and status = 'pending';

    update public.notifications
    set read_at = now()
    where user_id = target_user_id
      and type = 'follow_request'
      and actor_user_id = me
      and read_at is null;
end;
$$;

grant execute on function public.cancel_follow_request(uuid) to authenticated;

create or replace function public.unfollow_user(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then
        raise exception 'Not authenticated';
    end if;

    delete from public.follows
    where (follower_id = me and following_id = target_user_id)
       or (follower_id = target_user_id and following_id = me);
end;
$$;

grant execute on function public.unfollow_user(uuid) to authenticated;

create or replace function public.list_incoming_follow_requests()
returns table (
    request_id uuid,
    requester_user_id uuid,
    username text,
    display_name text,
    avatar_storage_path text,
    created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
begin
    if me is null then
        return;
    end if;

    return query
    select
        f.id as request_id,
        f.follower_id as requester_user_id,
        p.username,
        p.display_name,
        p.avatar_storage_path,
        f.created_at
    from public.follows f
    join public.profiles p on p.user_id = f.follower_id
    where f.following_id = me
      and f.status = 'pending'
      and p.username is not null
    order by f.created_at desc;
end;
$$;

grant execute on function public.list_incoming_follow_requests() to authenticated;

create or replace function public.count_pending_follow_requests()
returns int
language sql
stable
security definer
set search_path = public
as $$
    select count(*)::int
    from public.follows f
    where f.following_id = auth.uid()
      and f.status = 'pending';
$$;

grant execute on function public.count_pending_follow_requests() to authenticated;

create or replace function public.list_mutual_follows(result_limit int default 50)
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
    me uuid := auth.uid();
    lim int;
begin
    if me is null then
        return;
    end if;

    lim := greatest(1, least(coalesce(result_limit, 50), 100));

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
      and public.are_mutual_follows(me, p.user_id)
    order by lower(p.username)
    limit lim;
end;
$$;

grant execute on function public.list_mutual_follows(int) to authenticated;
