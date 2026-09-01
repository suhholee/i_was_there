-- Lets a signed-in user delete their own auth account (cascades to profiles, games, etc.).
create or replace function public.delete_own_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  delete from auth.users where id = auth.uid();
end;
$$;

grant execute on function public.delete_own_account() to authenticated;
