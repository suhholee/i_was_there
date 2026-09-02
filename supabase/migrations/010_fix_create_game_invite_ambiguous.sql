-- Fix create_game_invite: parameter names matched column names (ambiguous to_user_id).

create or replace function public.create_game_invite(
    source_game_id uuid,
    to_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    owner_id uuid;
    invite_id uuid;
    v_source_game_id uuid := source_game_id;
    v_to_user_id uuid := to_user_id;
begin
    if me is null then
        raise exception 'Not authenticated';
    end if;

    if v_to_user_id = me then
        raise exception 'Cannot invite yourself';
    end if;

    select g.user_id into owner_id
    from public.attended_games g
    where g.id = v_source_game_id;

    if owner_id is null or owner_id <> me then
        raise exception 'Game not found';
    end if;

    if not public.are_mutual_follows(me, v_to_user_id) then
        raise exception 'Can only invite mutual friends';
    end if;

    if exists (
        select 1
        from public.game_invites gi
        where gi.from_user_id = me
          and gi.to_user_id = v_to_user_id
          and gi.source_game_id = v_source_game_id
          and gi.status = 'pending'
    ) then
        select gi.id into invite_id
        from public.game_invites gi
        where gi.from_user_id = me
          and gi.to_user_id = v_to_user_id
          and gi.source_game_id = v_source_game_id
          and gi.status = 'pending'
        limit 1;
        return invite_id;
    end if;

    insert into public.game_invites (from_user_id, to_user_id, source_game_id)
    values (me, v_to_user_id, v_source_game_id)
    returning id into invite_id;

    insert into public.notifications (user_id, type, actor_user_id, reference_id)
    values (v_to_user_id, 'game_invite', me, invite_id);

    return invite_id;
end;
$$;

grant execute on function public.create_game_invite(uuid, uuid) to authenticated;
