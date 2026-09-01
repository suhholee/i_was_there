-- #iWasThere — user-owned data only.
-- Game scores, box scores, and player lines are NOT stored here; the iOS app
-- re-fetches those from the MLB / KBO APIs using game_key identifiers.

-- ---------------------------------------------------------------------------
-- Profiles (settings the user edits)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
    user_id uuid primary key references auth.users (id) on delete cascade,
    display_name text not null default '',
    favorite_team_id int,
    favorite_team_abbr text,
    favorite_kbo_team_id int,
    favorite_kbo_team_abbr text,
    active_league text not null default 'mlb',
    favorite_player_ids int[] not null default '{}',
    home_min_plate_appearances int not null default 0,
    home_min_batters_faced int not null default 0,
    updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Attendance log (which games + diary fields)
-- ---------------------------------------------------------------------------
create table if not exists public.attended_games (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    game_key text not null,
    league text not null,
    mlb_game_pk int not null,
    kbo_game_id text not null default '',
    kbo_g_dt text not null default '',
    official_date_string text not null default '',
    game_date timestamptz not null,
    season int not null,
    event_title text not null default '',
    note text not null default '',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (user_id, game_key)
);

create index if not exists attended_games_user_id_idx on public.attended_games (user_id);
create index if not exists attended_games_game_date_idx on public.attended_games (user_id, game_date desc);

-- ---------------------------------------------------------------------------
-- Friends per game (user input; linked_user_id for future social)
-- ---------------------------------------------------------------------------
create table if not exists public.game_friends (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    game_id uuid not null references public.attended_games (id) on delete cascade,
    name text not null,
    linked_user_id uuid references auth.users (id),
    created_at timestamptz not null default now()
);

create index if not exists game_friends_game_id_idx on public.game_friends (game_id);

-- ---------------------------------------------------------------------------
-- Photo metadata (bytes live in Storage bucket `game-photos`)
-- ---------------------------------------------------------------------------
create table if not exists public.game_photos (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users (id) on delete cascade,
    game_id uuid not null references public.attended_games (id) on delete cascade,
    storage_path text not null,
    created_at timestamptz not null default now()
);

create index if not exists game_photos_game_id_idx on public.game_photos (game_id);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.attended_games enable row level security;
alter table public.game_friends enable row level security;
alter table public.game_photos enable row level security;

create policy "profiles_select_own" on public.profiles
    for select using (auth.uid() = user_id);
create policy "profiles_insert_own" on public.profiles
    for insert with check (auth.uid() = user_id);
create policy "profiles_update_own" on public.profiles
    for update using (auth.uid() = user_id);

create policy "attended_games_select_own" on public.attended_games
    for select using (auth.uid() = user_id);
create policy "attended_games_insert_own" on public.attended_games
    for insert with check (auth.uid() = user_id);
create policy "attended_games_update_own" on public.attended_games
    for update using (auth.uid() = user_id);
create policy "attended_games_delete_own" on public.attended_games
    for delete using (auth.uid() = user_id);

create policy "game_friends_select_own" on public.game_friends
    for select using (auth.uid() = user_id);
create policy "game_friends_insert_own" on public.game_friends
    for insert with check (auth.uid() = user_id);
create policy "game_friends_update_own" on public.game_friends
    for update using (auth.uid() = user_id);
create policy "game_friends_delete_own" on public.game_friends
    for delete using (auth.uid() = user_id);

create policy "game_photos_select_own" on public.game_photos
    for select using (auth.uid() = user_id);
create policy "game_photos_insert_own" on public.game_photos
    for insert with check (auth.uid() = user_id);
create policy "game_photos_delete_own" on public.game_photos
    for delete using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Storage bucket (create in Dashboard or via API): `game-photos`
-- Policies (run after bucket exists):
-- ---------------------------------------------------------------------------
-- insert into storage.buckets (id, name, public) values ('game-photos', 'game-photos', false);
--
-- create policy "game_photos_storage_select" on storage.objects
--   for select using (bucket_id = 'game-photos' and auth.uid()::text = (storage.foldername(name))[1]);
-- create policy "game_photos_storage_insert" on storage.objects
--   for insert with check (bucket_id = 'game-photos' and auth.uid()::text = (storage.foldername(name))[1]);
-- create policy "game_photos_storage_delete" on storage.objects
--   for delete using (bucket_id = 'game-photos' and auth.uid()::text = (storage.foldername(name))[1]);
