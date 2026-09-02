-- Cache team names on attended_games for lightweight display (notifications, etc.).

alter table public.attended_games
    add column if not exists away_team_name text not null default '',
    add column if not exists home_team_name text not null default '';

-- Return type changed (new OUT columns); CREATE OR REPLACE is not enough.
drop function if exists public.list_incoming_game_invites();

create function public.list_incoming_game_invites()
returns table (
    invite_id uuid,
    from_user_id uuid,
    username text,
    display_name text,
    avatar_storage_path text,
    game_key text,
    league text,
    game_date timestamptz,
    official_date_string text,
    away_team_name text,
    home_team_name text,
    event_title text
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
        gi.id as invite_id,
        gi.from_user_id,
        p.username,
        p.display_name,
        p.avatar_storage_path,
        g.game_key,
        g.league,
        g.game_date,
        g.official_date_string,
        g.away_team_name,
        g.home_team_name,
        g.event_title
    from public.game_invites gi
    join public.attended_games g on g.id = gi.source_game_id
    join public.profiles p on p.user_id = gi.from_user_id
    where gi.to_user_id = me
      and gi.status = 'pending'
      and p.username is not null
    order by gi.created_at desc;
end;
$$;

grant execute on function public.list_incoming_game_invites() to authenticated;
