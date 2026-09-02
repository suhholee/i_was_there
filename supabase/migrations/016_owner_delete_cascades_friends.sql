-- Owner delete cascades to all invited friends' copies of the same game.

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
    is_shared_copy boolean;
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

    is_shared_copy := my_invited_from is not null;

    if not is_shared_copy then
        select exists (
            select 1
            from public.game_invites gi
            join public.attended_games src on src.id = gi.source_game_id
            where gi.to_user_id = me
              and gi.status = 'accepted'
              and src.game_key = p_game_key
        )
        into is_shared_copy;
    end if;

    if is_shared_copy then
        if my_invited_from is not null then
            select g.id
            into owner_game_id
            from public.attended_games g
            where g.user_id = my_invited_from
              and g.game_key = p_game_key
            limit 1;
        else
            select gi.from_user_id, gi.source_game_id
            into my_invited_from, owner_game_id
            from public.game_invites gi
            join public.attended_games src on src.id = gi.source_game_id
            where gi.to_user_id = me
              and gi.status = 'accepted'
              and src.game_key = p_game_key
            order by gi.responded_at desc nulls last, gi.created_at desc
            limit 1;
        end if;

        if my_invited_from is not null and owner_game_id is not null then
            delete from public.game_friends gf
            where gf.linked_user_id = me
              and gf.game_id = owner_game_id;

            insert into public.notifications (user_id, type, actor_user_id, reference_id)
            values (my_invited_from, 'game_invite_left', me, owner_game_id);
        end if;

        delete from public.attended_games
        where id = my_game_id;
    else
        delete from public.attended_games
        where game_key = p_game_key
          and (
            user_id = me
            or invited_from_user_id = me
            or user_id in (
                select gi.to_user_id
                from public.game_invites gi
                where gi.source_game_id = my_game_id
                  and gi.status = 'accepted'
            )
          );

        delete from public.game_invites
        where source_game_id = my_game_id;
    end if;
end;
$$;

grant execute on function public.delete_attended_game(text) to authenticated;
