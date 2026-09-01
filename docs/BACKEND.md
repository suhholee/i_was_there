# Backend setup (Supabase) — email sign-in (no Apple Developer fee)

The cloud database stores **only user-owned data**. Scores, box scores, and player stat lines are **not** uploaded — the app re-fetches those from the MLB Stats API and Sports2i KBO API using `game_key` identifiers.

## What is stored in Supabase

| Table | Contents |
|-------|----------|
| `profiles` | Display name, favorite teams, league mode, leader filters |
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

### 6. (Optional) Disable other providers

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
