#!/usr/bin/env python3
"""
One-time backfill: write scores, starters, and team ids onto existing attended_games rows.

Supabase SQL cannot call MLB/KBO. This script:
  1. Reads rows from attended_games (service role bypasses RLS)
  2. Fetches display data from MLB Stats API / Sports2i KBO
  3. PATCHes each row

Requires (export before running):
  export SUPABASE_URL="https://YOUR_REF.supabase.co"
  export SUPABASE_SERVICE_ROLE_KEY="..."   # Project Settings → API → service_role (keep secret)

Usage:
  python3 Scripts/backfill_attended_game_snapshots.py --dry-run
  python3 Scripts/backfill_attended_game_snapshots.py
  python3 Scripts/backfill_attended_game_snapshots.py --limit 10
"""

from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any

UA = "IWasThere/0.1 (snapshot-backfill)"
MLB_BASE = "https://statsapi.mlb.com/api/v1"
KBO_BASE = "https://sportsstatsjson.sports2i.com/ws/BaseBall.asmx"

KBO_TEAM_ID: dict[str, int] = {
    "HH": 9101,
    "HT": 9102,
    "KT": 9103,
    "LG": 9104,
    "LT": 9105,
    "NC": 9106,
    "OB": 9107,
    "SK": 9108,
    "SS": 9109,
    "WO": 9110,
}

_kbo_players_cache: dict[int, dict[int, str]] = {}


def ssl_context() -> ssl.SSLContext:
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        try:
            return ssl.create_default_context()
        except Exception:
            return ssl._create_unverified_context()


CTX = ssl_context()


def http_json(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    body: dict[str, Any] | None = None,
) -> Any:
    data = None
    hdrs = {"User-Agent": UA, "Accept": "application/json"}
    if headers:
        hdrs.update(headers)
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=hdrs)
    with urllib.request.urlopen(req, timeout=60, context=CTX) as resp:
        raw = resp.read()
        if not raw:
            return None
        return json.loads(raw.decode("utf-8"))


def needs_backfill(row: dict[str, Any]) -> bool:
    if row.get("home_score") is None or row.get("away_score") is None:
        return True
    if row.get("home_team_id") is None or row.get("away_team_id") is None:
        return True
    if not (row.get("home_starter_name") or "").strip():
        return True
    if not (row.get("away_starter_name") or "").strip():
        return True
    return False


def schedule_query_date(iso_or_date: str, game_date: str) -> str:
    if iso_or_date and len(iso_or_date) >= 10:
        return iso_or_date[:10]
    if game_date:
        try:
            dt = datetime.fromisoformat(game_date.replace("Z", "+00:00"))
            return dt.strftime("%Y-%m-%d")
        except ValueError:
            pass
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def mlb_get(path: str) -> dict:
    return http_json(f"{MLB_BASE}{path}")


def mlb_schedule(date: str) -> list[dict]:
    data = mlb_get(f"/schedule?sportId=1&date={date}")
    out: list[dict] = []
    for block in data.get("dates") or []:
        out.extend(block.get("games") or [])
    return out


def mlb_find_game(game_pk: int, around: str) -> dict | None:
    for delta in (0, -1, 1):
        d = datetime.strptime(around, "%Y-%m-%d") + timedelta(days=delta)
        for g in mlb_schedule(d.strftime("%Y-%m-%d")):
            if g.get("gamePk") == game_pk:
                return g
    return None


def mlb_starter_name(side: dict) -> str | None:
    for pid in side.get("pitchers") or []:
        player = (side.get("players") or {}).get(f"ID{pid}")
        if not player:
            continue
        pitching = (player.get("stats") or {}).get("pitching") or {}
        if (pitching.get("gamesStarted") or 0) > 0:
            return (player.get("person") or {}).get("fullName")
    pitchers = side.get("pitchers") or []
    if pitchers:
        player = (side.get("players") or {}).get(f"ID{pitchers[0]}")
        if player:
            return (player.get("person") or {}).get("fullName")
    return None


def backfill_mlb(row: dict[str, Any]) -> dict[str, Any] | None:
    game_pk = int(row.get("mlb_game_pk") or 0)
    if game_pk <= 0:
        return None
    around = schedule_query_date(row.get("official_date_string") or "", row.get("game_date") or "")
    schedule = mlb_find_game(game_pk, around)
    if not schedule:
        return None

    away = schedule["teams"]["away"]
    home = schedule["teams"]["home"]
    away_score = away.get("score")
    home_score = home.get("score")
    if away_score is None or home_score is None:
        return None

    away_won = away.get("isWinner")
    home_won = home.get("isWinner")
    if away_won is None:
        away_won = away_score > home_score
    if home_won is None:
        home_won = home_score > away_score

    patch: dict[str, Any] = {
        "away_score": away_score,
        "home_score": home_score,
        "away_team_id": away["team"]["id"],
        "home_team_id": home["team"]["id"],
        "away_won": bool(away_won),
        "home_won": bool(home_won),
    }
    if not (row.get("away_team_name") or "").strip():
        patch["away_team_name"] = away["team"]["name"]
    if not (row.get("home_team_name") or "").strip():
        patch["home_team_name"] = home["team"]["name"]

    need_starters = not (row.get("away_starter_name") or "").strip() or not (
        row.get("home_starter_name") or ""
    ).strip()
    if need_starters:
        try:
            box = mlb_get(f"/game/{game_pk}/boxscore")
            away_name = mlb_starter_name(box["teams"]["away"])
            home_name = mlb_starter_name(box["teams"]["home"])
            if away_name:
                patch["away_starter_name"] = away_name
            if home_name:
                patch["home_starter_name"] = home_name
        except urllib.error.HTTPError:
            pass

    return patch


def kbo_get(path_query: str) -> Any:
    url = f"{KBO_BASE}/{path_query}"
    return http_json(url)


def kbo_players(season: int) -> dict[int, str]:
    if season in _kbo_players_cache:
        return _kbo_players_cache[season]
    rows = kbo_get(f"Player?season={season}")
    names: dict[int, str] = {}
    for row in rows:
        if row.get("le_id") != "1":
            continue
        pid = row.get("p_id")
        if not pid:
            continue
        try:
            player_id = int(pid)
        except ValueError:
            continue
        name = (row.get("p_full_nm") or row.get("p_nm") or "").strip() or f"Player {player_id}"
        names[player_id] = name
    _kbo_players_cache[season] = names
    return names


def kbo_gdt(row: dict[str, Any]) -> str:
    g_dt = (row.get("kbo_g_dt") or "").strip()
    if g_dt:
        return g_dt
    gid = (row.get("kbo_game_id") or "").strip()
    if len(gid) >= 8 and gid[:8].isdigit():
        return gid[:8]
    official = (row.get("official_date_string") or "")[:10]
    if len(official) == 10:
        return official.replace("-", "")
    return ""


def kbo_find_game(game_id: str, g_dt: str, season: int) -> dict | None:
    if not game_id or not g_dt:
        return None
    for delta in (0, -1, 1):
        try:
            base = datetime.strptime(g_dt, "%Y%m%d") + timedelta(days=delta)
            probe = base.strftime("%Y%m%d")
        except ValueError:
            continue
        games = kbo_get(f"Game?season={season}&gDt={probe}")
        for g in games:
            if g.get("g_id") == game_id:
                return g
    return None


def kbo_derived_scores(hitters: list[dict]) -> dict[str, int]:
    runs: dict[str, int] = defaultdict(int)
    for row in hitters:
        code = row.get("tb_sc")
        if not code:
            continue
        runs[code] += int(row.get("run_cn") or 0)
    return dict(runs)


def backfill_kbo(row: dict[str, Any]) -> dict[str, Any] | None:
    game_id = (row.get("kbo_game_id") or "").strip()
    season = int(row.get("season") or 0)
    g_dt = kbo_gdt(row)
    if not game_id or not g_dt or season <= 0:
        return None

    schedule_row = kbo_find_game(game_id, g_dt, season)
    if not schedule_row:
        return None

    away_code = schedule_row.get("a_t_id") or ""
    home_code = schedule_row.get("h_t_id") or ""
    hitters = [r for r in kbo_get(f"GameHitterBoxScore?season={season}&gDt={g_dt}") if r.get("g_id") == game_id]
    scores = kbo_derived_scores(hitters)
    away_score = scores.get(away_code, 0)
    home_score = scores.get(home_code, 0)

    team_rec = [r for r in kbo_get(f"GameTeamRecord?season={season}&gDt={g_dt}") if r.get("g_id") == game_id]
    away_result = next((r.get("result_sc") for r in team_rec if r.get("t_id") == away_code), None)
    home_result = next((r.get("result_sc") for r in team_rec if r.get("t_id") == home_code), None)
    away_won = away_result == "W" or (away_result != "L" and away_score > home_score)
    home_won = home_result == "W" or (home_result != "L" and home_score > away_score)

    patch: dict[str, Any] = {
        "away_score": away_score,
        "home_score": home_score,
        "away_team_id": KBO_TEAM_ID.get(away_code, 9198),
        "home_team_id": KBO_TEAM_ID.get(home_code, 9199),
        "away_won": bool(away_won),
        "home_won": bool(home_won),
    }

    starters_rows = [r for r in kbo_get(f"GameStartPitcherRecord?season={season}&gDt={g_dt}") if r.get("g_id") == game_id]
    if starters_rows:
        st = starters_rows[0]
        players = kbo_players(season)
        away_pid = st.get("t_pit_p_id")
        home_pid = st.get("b_pit_p_id")
        if away_pid:
            try:
                patch["away_starter_name"] = players.get(int(away_pid), "")
            except ValueError:
                pass
        if home_pid:
            try:
                patch["home_starter_name"] = players.get(int(home_pid), "")
            except ValueError:
                pass

    return patch


def supabase_fetch_games(base_url: str, service_key: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    offset = 0
    page = 500
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
    }
    while True:
        q = urllib.parse.urlencode({"select": "*", "order": "game_date.desc", "offset": offset, "limit": page})
        url = f"{base_url.rstrip('/')}/rest/v1/attended_games?{q}"
        batch = http_json(url, headers=headers)
        if not batch:
            break
        rows.extend(batch)
        if len(batch) < page:
            break
        offset += page
    return rows


def supabase_patch_game(base_url: str, service_key: str, game_id: str, patch: dict[str, Any]) -> None:
    headers = {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Prefer": "return=minimal",
    }
    q = urllib.parse.urlencode({"id": f"eq.{game_id}"})
    url = f"{base_url.rstrip('/')}/rest/v1/attended_games?{q}"
    http_json(url, method="PATCH", headers=headers, body=patch)


def main() -> int:
    parser = argparse.ArgumentParser(description="Backfill attended_games display snapshots via MLB/KBO APIs.")
    parser.add_argument("--dry-run", action="store_true", help="Print patches without writing to Supabase")
    parser.add_argument("--limit", type=int, default=0, help="Max rows to update (0 = all needing backfill)")
    parser.add_argument("--sleep", type=float, default=0.15, help="Seconds between API-heavy rows")
    args = parser.parse_args()

    base_url = os.environ.get("SUPABASE_URL", "").strip()
    service_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not base_url or not service_key:
        print(
            "Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY (service_role, not anon).",
            file=sys.stderr,
        )
        return 1

    print("Fetching attended_games…")
    all_rows = supabase_fetch_games(base_url, service_key)
    pending = [r for r in all_rows if needs_backfill(r)]
    print(f"Total rows: {len(all_rows)}; need backfill: {len(pending)}")

    updated = 0
    skipped = 0
    failed = 0

    for row in pending:
        if args.limit and updated + failed >= args.limit:
            break

        game_uuid = row["id"]
        league = (row.get("league") or "mlb").lower()
        label = row.get("game_key") or game_uuid

        try:
            if league == "kbo":
                patch = backfill_kbo(row)
            else:
                patch = backfill_mlb(row)
        except Exception as exc:  # noqa: BLE001
            print(f"FAIL {label}: {exc}", file=sys.stderr)
            failed += 1
            continue

        if not patch:
            print(f"SKIP {label} (API could not resolve game)")
            skipped += 1
            continue

        print(f"{'DRY' if args.dry_run else 'OK'} {label} → {patch}")
        if not args.dry_run:
            supabase_patch_game(base_url, service_key, game_uuid, patch)
            updated += 1
        else:
            updated += 1

        if args.sleep > 0:
            time.sleep(args.sleep)

    print(f"Done. updated={updated} skipped={skipped} failed={failed}")
    if not args.dry_run and updated > 0:
        print("Tip: run migration 018 or `notify pgrst, 'reload schema';` if clients still omit columns.")
    return 0 if failed == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
