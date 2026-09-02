-- Phase 4 social: game share invites between mutual friends.

alter table public.notifications
    drop constraint if exists notifications_type_check;

alter table public.notifications
    add constraint notifications_type_check
    check (type in ('follow_request', 'follow_accepted', 'game_invite', 'game_invite_accepted'));

create table if not exists public.game_invites (
    id uuid primary key default gen_random_uuid(),
    from_user_id uuid not null references auth.users (id) on delete cascade,
    to_user_id uuid not null references auth.users (id) on delete cascade,
    source_game_id uuid not null references public.attended_games (id) on delete cascade,
    status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
    created_at timestamptz not null default now(),
    responded_at timestamptz,
    check (from_user_id <> to_user_id)
);

create unique index if not exists game_invites_pending_unique_idx
    on public.game_invites (from_user_id, to_user_id, source_game_id)
    where status = 'pending';

create index if not exists game_invites_to_user_pending_idx
    on public.game_invites (to_user_id, created_at desc)
    where status = 'pending';

alter table public.game_invites enable row level security;

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

create or replace function public.list_incoming_game_invites()
returns table (
    invite_id uuid,
    from_user_id uuid,
    username text,
    display_name text,
    avatar_storage_path text,
    game_key text,
    league text,
    game_date timestamptz,
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

create or replace function public.count_pending_game_invites()
returns int
language sql
stable
security definer
set search_path = public
as $$
    select count(*)::int
    from public.game_invites gi
    where gi.to_user_id = auth.uid()
      and gi.status = 'pending';
$$;

grant execute on function public.count_pending_game_invites() to authenticated;

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
            note
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
            src.note
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
