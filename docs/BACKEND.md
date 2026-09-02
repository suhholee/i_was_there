# Backend setup (Supabase) — email sign-in (no Apple Developer fee)

The cloud database stores **only user-owned data**. Scores, box scores, and player stat lines are **not** uploaded — the app re-fetches those from the MLB Stats API and Sports2i KBO API using `game_key` identifiers.

## What is stored in Supabase

| Table | Contents |
|-------|----------|
| `profiles` | Display name, @username, avatar, public/private visibility, favorite teams, league mode, leader filters |
| `attended_games` | Which games you attended + diary (`event_title`, `note`) + API lookup keys |
| `game_friends` | Friend names per game (text now; `linked_user_id` later) |
| `game_photos` | Storage path metadata (JPEG bytes in Storage) |

---

## Part A — Supabase (one-time)

### 1. Create project & save keys

1. [supabase.com](https://supabase.com) → **New project**
2. **Project Settings** (gear, bottom-left) → **API**
3. Copy:
   - **Project URL** → `https://xxxxx.supabase.co`
   - **anon public** key (not service_role)

### 2. Database schema

**SQL Editor** → paste all of `supabase/migrations/001_user_data.sql` → **Run**

Check **Table Editor** for: `profiles`, `attended_games`, `game_friends`, `game_photos`.

### 3. Photo storage

**Storage** → **New bucket** → name `game-photos`, **private**

If storage policies already exist, skip. Otherwise run the three `create policy` statements at the bottom of `001_user_data.sql`.

### 4. Enable email auth (free — no Apple)

**Authentication → Providers → Email**

- **Enable Email provider** → ON
- For production, turn **Confirm email** → **ON**
- **Save**

**Authentication → URL Configuration → Redirect URLs** — add:

```text
com.suhholee.iwasthere://auth-callback
```

After a user taps the confirmation link in their email, the app opens and shows profile setup (display name + favorite teams).

### 5. Account deletion function

In **SQL Editor**, run `supabase/migrations/002_delete_own_account.sql` (after `001_user_data.sql`).

### 6. Social profile fields (Phase 1)

In **SQL Editor**, run `supabase/migrations/004_social.sql` (after `003_home_leader_stats.sql`).

**Storage** → **New bucket** → name `avatars`, **private**

Then run the four `avatars_storage_*` policy statements at the bottom of `004_social.sql`.

### 7. Social search + public profiles (Phase 2)

In **SQL Editor**, run `supabase/migrations/006_social_search.sql` (after `004_social.sql`).

Then add two **additional** storage read policies so signed-in users can view other users' avatars and game photos (paths are only returned by security-definer RPCs):

```sql
create policy "avatars_storage_select_social" on storage.objects
  for select to authenticated
  using (bucket_id = 'avatars');

create policy "game_photos_storage_select_social" on storage.objects
  for select to authenticated
  using (bucket_id = 'game-photos');
```

### 8. Mutual follows (Phase 3)

In **SQL Editor**, run `supabase/migrations/007_social_follows.sql` (after `006_social_search.sql`).

This adds follow requests, mutual friendships, notifications, and updates private-profile game visibility to mutual follows only.

### 9. Game invites (Phase 4)

In **SQL Editor**, run `supabase/migrations/008_game_invites.sql` (after `007_social_follows.sql`).

This adds game share invites between mutual friends, accept/decline flows, game-invite notifications, and diary-friend decline cleanup (removes tagged friend from inviter's game when declined).

**Do not run `009` before `008`.** If `game_invites` does not exist, run `008` only. Run `009_diary_friend_invite_decline.sql` only if you already applied an older `008` without the updated decline function.

If **Add friend** shows `column reference "to_user_id" is ambiguous`, run `supabase/migrations/010_fix_create_game_invite_ambiguous.sql` in **SQL Editor** (after `008`).

For game-invite notifications with team names, run `supabase/migrations/011_game_invite_team_names.sql` (after `010`). Re-open the app so games re-sync team names to the cloud.

For shared-game friend permissions, run `supabase/migrations/012_shared_game_invited_from.sql` (after `011`).

When an invitee deletes their shared copy, run `supabase/migrations/013_delete_shared_game_removes_friend.sql` so they are removed from the owner's friend list in the cloud (owner sees the update on next sync).

Then run `supabase/migrations/014_leave_shared_game_notifications.sql` for leave confirmations, durable cloud delete, and owner notifications when a friend leaves a shared game.

If delete fails with `invited_from_user_id`, run `supabase/migrations/015_fix_shared_game_delete_and_friends.sql` (adds the column, fixes delete, and corrects shared-game friend lists).

When the owner deletes a game, run `supabase/migrations/016_owner_delete_cascades_friends.sql` so invited friends' copies are removed from the cloud too.

**Phase 5 (diary @tag friends):** iOS syncs `linked_user_id` on `game_friends` when you tag a mutual friend in a game diary. No extra migration beyond `008` for new installs.

### 10. Favorite player metadata sync

In **SQL Editor**, run `supabase/migrations/005_favorite_player_meta.sql` if not already applied.

### 11. (Optional) Disable other providers

Under **Authentication → Providers**, disable anything you are not using so users only see email.

---

## Part B — iOS app

### 1. Config plist

```bash
cd "/Users/suhholee/Desktop/i_was_there"
cp IWasThere/Config/SupabaseConfig.example.plist IWasThere/Config/SupabaseConfig.plist
```

Edit `IWasThere/Config/SupabaseConfig.plist`:

```xml
<key>SUPABASE_URL</key>
<string>https://YOUR_REF.supabase.co</string>
<key>SUPABASE_ANON_KEY</key>
<string>eyJ...</string>
```

This file is gitignored — never commit it.

### 2. Xcode (no Sign in with Apple required)

```bash
xcodegen generate
open IWasThere.xcodeproj
```

1. Select **IWasThere** target → **Signing & Capabilities**
2. **Team** → your **Personal Team** (free Apple ID is fine)
3. You do **not** need **Sign in with Apple** for email auth

### 3. Run

1. Build & run (⌘R)
2. Enter email + password → **Create account** or **Sign in**
3. Add a game → check **Table Editor → attended_games** in Supabase

---

## Sync behaviour

- **Sign in** → pull cloud profile + attendance → hydrate games from MLB/KBO APIs → download photos
- **Add / edit game** → save locally → sync user rows + photos
- **Settings → Save** → sync profile

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| “Add SupabaseConfig.plist” | Create plist from example with real URL + anon key |
| “Wrong email or password” | Use **Create account** first, or reset password in Supabase **Authentication → Users** |
| “Confirm your email” message | Turn on **Confirm email** in Email provider and add redirect URL `com.suhholee.iwasthere://auth-callback` |
| Profile setup not showing after email | Confirm redirect URL is in Supabase; rebuild app after `xcodegen generate` |
| Remove account fails | Run `002_delete_own_account.sql` in SQL Editor |
| Storage upload fails | Bucket `game-photos` + RLS policies |
| Games don’t restore | Network required; check `attended_games` has rows |

---

## Later: Sign in with Apple

When you enroll in the **Apple Developer Program** ($99/yr), see the Apple section in git history or add Apple provider in Supabase + enable capability in Xcode.

---

## Branch

```bash
git checkout feature/backend
```
