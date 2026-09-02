-- Store favorite player display metadata (name, jersey, team) for Home before games are logged.

alter table public.profiles
    add column if not exists favorite_player_meta_json text not null default '[]';
