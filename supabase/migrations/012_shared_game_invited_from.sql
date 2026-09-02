-- Mark games created by accepting a share invite (invitee copy).

alter table public.attended_games
    add column if not exists invited_from_user_id uuid references auth.users (id) on delete set null;

-- Backfill invite copies created before this migration.
update public.attended_games ag
set invited_from_user_id = gi.from_user_id
from public.game_invites gi
join public.attended_games src on src.id = gi.source_game_id
where ag.user_id = gi.to_user_id
  and ag.game_key = src.game_key
  and gi.status = 'accepted'
  and ag.invited_from_user_id is null;

create or replace function public.accept_game_invite(p_invite_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    inv public.game_invites%rowtype;
    src public.attended_games%rowtype;
    new_game_id uuid;
begin
    if me is null then
        raise exception 'Not authenticated';
    end if;

    select *
    into inv
    from public.game_invites gi
    where gi.id = p_invite_id
    for update;

    if not found or inv.to_user_id <> me or inv.status <> 'pending' then
        raise exception 'Invite not found';
    end if;

    select *
    into src
    from public.attended_games g
    where g.id = inv.source_game_id;

    if not found then
        raise exception 'Source game missing';
    end if;

    select g.id
    into new_game_id
    from public.attended_games g
    where g.user_id = me
      and g.game_key = src.game_key
    limit 1;

    if new_game_id is null then
        insert into public.attended_games (
            user_id,
            game_key,
            league,
            mlb_game_pk,
            kbo_game_id,
            kbo_g_dt,
            official_date_string,
            game_date,
            season,
            event_title,
            note,
            invited_from_user_id
        )
        values (
            me,
            src.game_key,
            src.league,
            src.mlb_game_pk,
            src.kbo_game_id,
            src.kbo_g_dt,
            src.official_date_string,
            src.game_date,
            src.season,
            src.event_title,
            src.note,
            inv.from_user_id
        )
        returning id into new_game_id;

        insert into public.game_friends (user_id, game_id, name, linked_user_id)
        select me, new_game_id, gf.name, gf.linked_user_id
        from public.game_friends gf
        where gf.game_id = src.id;

        insert into public.game_photos (user_id, game_id, storage_path)
        select me, new_game_id, gp.storage_path
        from public.game_photos gp
        where gp.game_id = src.id;
    end if;

    update public.game_invites
    set status = 'accepted', responded_at = now()
    where id = p_invite_id;

    update public.notifications
    set read_at = now()
    where user_id = me
      and type = 'game_invite'
      and reference_id = p_invite_id
      and read_at is null;

    insert into public.notifications (user_id, type, actor_user_id, reference_id)
    values (inv.from_user_id, 'game_invite_accepted', me, p_invite_id);

    return new_game_id;
end;
$$;

grant execute on function public.accept_game_invite(uuid) to authenticated;
