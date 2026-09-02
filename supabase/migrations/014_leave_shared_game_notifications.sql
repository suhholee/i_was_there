-- Leave shared game: notify owner, keep cloud delete durable.

alter table public.attended_games
    add column if not exists invited_from_user_id uuid references auth.users (id) on delete set null;

alter table public.notifications
    drop constraint if exists notifications_type_check;

alter table public.notifications
    add constraint notifications_type_check
    check (type in (
        'follow_request',
        'follow_accepted',
        'game_invite',
        'game_invite_accepted',
        'game_invite_left'
    ));

create or replace function public.delete_attended_game(p_game_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    my_game_id uuid;
    my_invited_from uuid;
    owner_user_id uuid;
    owner_game_id uuid;
begin
    if me is null then
        raise exception 'Not authenticated';
    end if;

    select g.id, g.invited_from_user_id
    into my_game_id, my_invited_from
    from public.attended_games g
    where g.user_id = me
      and g.game_key = p_game_key;

    if my_game_id is null then
        return;
    end if;

    owner_user_id := my_invited_from;

    if owner_user_id is null then
        select gi.from_user_id, gi.source_game_id
        into owner_user_id, owner_game_id
        from public.game_invites gi
        join public.attended_games src on src.id = gi.source_game_id
        where gi.to_user_id = me
          and gi.status = 'accepted'
          and src.game_key = p_game_key
        order by gi.responded_at desc nulls last, gi.created_at desc
        limit 1;
    else
        select g.id
        into owner_game_id
        from public.attended_games g
        where g.user_id = owner_user_id
          and g.game_key = p_game_key
        limit 1;
    end if;

    if owner_user_id is not null and owner_game_id is not null then
        delete from public.game_friends gf
        where gf.linked_user_id = me
          and gf.game_id = owner_game_id;

        insert into public.notifications (user_id, type, actor_user_id, reference_id)
        values (owner_user_id, 'game_invite_left', me, owner_game_id);
    end if;

    delete from public.attended_games
    where id = my_game_id;
end;
$$;

grant execute on function public.delete_attended_game(text) to authenticated;

create or replace function public.count_unread_game_left_notifications()
returns int
language sql
stable
security definer
set search_path = public
as $$
    select count(*)::int
    from public.notifications n
    where n.user_id = auth.uid()
      and n.type = 'game_invite_left'
      and n.read_at is null;
$$;

grant execute on function public.count_unread_game_left_notifications() to authenticated;

create or replace function public.list_game_left_notifications()
returns table (
    notification_id uuid,
    actor_user_id uuid,
    username text,
    display_name text,
    avatar_storage_path text,
    game_key text,
    league text,
    game_date timestamptz,
    official_date_string text,
    away_team_name text,
    home_team_name text,
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
        n.id as notification_id,
        n.actor_user_id,
        p.username,
        p.display_name,
        p.avatar_storage_path,
        g.game_key,
        g.league,
        g.game_date,
        g.official_date_string,
        g.away_team_name,
        g.home_team_name,
        n.created_at
    from public.notifications n
    join public.profiles p on p.user_id = n.actor_user_id
    join public.attended_games g on g.id = n.reference_id
    where n.user_id = me
      and n.type = 'game_invite_left'
      and n.read_at is null
      and p.username is not null
    order by n.created_at desc;
end;
$$;

grant execute on function public.list_game_left_notifications() to authenticated;

create or replace function public.mark_game_left_notifications_read()
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

    update public.notifications
    set read_at = now()
    where user_id = me
      and type = 'game_invite_left'
      and read_at is null;
end;
$$;

grant execute on function public.mark_game_left_notifications_read() to authenticated;
