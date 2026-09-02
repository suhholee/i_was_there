-- Deleting a shared game copy removes the invitee from the owner's friend list.

create or replace function public.delete_attended_game(p_game_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    my_game public.attended_games%rowtype;
begin
    if me is null then
        raise exception 'Not authenticated';
    end if;

    select *
    into my_game
    from public.attended_games g
    where g.user_id = me
      and g.game_key = p_game_key;

    if not found then
        return;
    end if;

    if my_game.invited_from_user_id is not null then
        delete from public.game_friends gf
        where gf.linked_user_id = me
          and gf.game_id in (
              select g.id
              from public.attended_games g
              where g.user_id = my_game.invited_from_user_id
                and g.game_key = p_game_key
          );
    else
        delete from public.game_friends gf
        where gf.linked_user_id = me
          and gf.game_id in (
              select gi.source_game_id
              from public.game_invites gi
              join public.attended_games src on src.id = gi.source_game_id
              where gi.to_user_id = me
                and gi.status = 'accepted'
                and src.game_key = p_game_key
          );
    end if;

    delete from public.attended_games
    where id = my_game.id;
end;
$$;

grant execute on function public.delete_attended_game(text) to authenticated;
