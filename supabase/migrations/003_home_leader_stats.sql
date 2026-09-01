-- Leader stat preferences for Home and per-game top player cards.
alter table public.profiles
    add column if not exists home_batter_stat text not null default 'ops',
    add column if not exists home_pitcher_stat text not null default 'era';
