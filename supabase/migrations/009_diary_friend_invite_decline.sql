-- Phase 5b: diary friend decline removes tagged friend from inviter's game.
--
-- PREREQUISITE: Run 008_game_invites.sql first if you see:
--   relation "public.game_invites" does not exist
--
-- If you have NOT run 008 yet, run 008_game_invites.sql instead (it already
-- includes this decline behavior). Only run this file if you applied 008 before
-- the decline logic was updated.

do $$
begin
    if not exists (
        select 1
        from information_schema.tables
        where table_schema = 'public'
          and table_name = 'game_invites'
    ) then
        raise exception 'Missing public.game_invites. Run supabase/migrations/008_game_invites.sql first.';
    end if;
end $$;

create or replace function public.decline_game_invite(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    me uuid := auth.uid();
    inv public.game_invites%rowtype;
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

    update public.game_invites
    set status = 'declined', responded_at = now()
    where id = p_invite_id;

    delete from public.game_friends gf
    where gf.game_id = inv.source_game_id
      and gf.linked_user_id = me;

    update public.notifications
    set read_at = now()
    where user_id = me
      and type = 'game_invite'
      and reference_id = p_invite_id
      and read_at is null;
end;
$$;

grant execute on function public.decline_game_invite(uuid) to authenticated;
