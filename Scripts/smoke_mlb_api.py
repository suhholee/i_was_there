#!/usr/bin/env python3
"""Smoke-test MLB Stats API endpoints used by I was there."""

from __future__ import annotations

import json
import ssl
import sys
import urllib.request

UA = "IWasThere/0.1 (prototype; smoke-test)"
BASE = "https://statsapi.mlb.com/api/v1"


def _ssl_context() -> ssl.SSLContext:
    # Prefer certifi when present; fall back to default, then unverified for local smoke only.
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except Exception:
        try:
            return ssl.create_default_context()
        except Exception:
            return ssl._create_unverified_context()


def get(path: str) -> dict:
    req = urllib.request.Request(f"{BASE}{path}", headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30, context=_ssl_context()) as resp:
        return json.load(resp)


def main() -> int:
    print("1) Schedule 2024-10-25 (WS G1)")
    schedule = get("/schedule?sportId=1&date=2024-10-25")
    games = schedule["dates"][0]["games"]
    assert games, "expected at least one game"
    game = games[0]
    game_pk = game["gamePk"]
    away = game["teams"]["away"]
    home = game["teams"]["home"]
    print(
        f"   gamePk={game_pk} {away['team']['name']} {away.get('score')} @ "
        f"{home['team']['name']} {home.get('score')} status={game['status']['detailedState']}"
    )
    assert game["status"]["detailedState"] == "Final"
    assert away.get("score") == 3 and home.get("score") == 6

    print(f"2) Boxscore {game_pk}")
    box = get(f"/game/{game_pk}/boxscore")
    freeman = None
    for player in box["teams"]["home"]["players"].values():
        if player["person"]["fullName"] == "Freddie Freeman":
            freeman = player
            break
    assert freeman is not None, "Freddie Freeman not in home boxscore"
    batting = freeman["stats"]["batting"]
    print(
        f"   Freeman #{freeman.get('jerseyNumber')}: "
        f"{batting['hits']}-{batting['atBats']}, HR={batting['homeRuns']}, RBI={batting['rbi']}, TB={batting['totalBases']}"
    )
    assert batting["homeRuns"] == 1 and batting["rbi"] == 4
    assert freeman.get("jerseyNumber"), "jersey numbers available for UI cards"
    # Game batting omits AVG/OPS — app computes from counting stats (BREF formulas).
    h, ab = batting["hits"], batting["atBats"]
    bb = batting.get("baseOnBalls") or 0
    hbp = batting.get("hitByPitch") or 0
    sf = batting.get("sacFlies") or 0
    tb = batting["totalBases"]
    avg = h / ab
    obp = (h + bb + hbp) / (ab + bb + hbp + sf)
    slg = tb / ab
    ops = obp + slg
    print(f"   computed AVG={avg:.3f} OBP={obp:.3f} SLG={slg:.3f} OPS={ops:.3f}")
    assert abs(avg - 0.400) < 1e-9
    assert abs(slg - 1.400) < 1e-9  # 7 TB / 5 AB
    assert abs(ops - (obp + slg)) < 1e-9

    # Pitcher IP outs notation
    flaherty = None
    for player in box["teams"]["home"]["players"].values():
        if player["person"]["fullName"] == "Jack Flaherty":
            flaherty = player
            break
    assert flaherty is not None
    pit = flaherty["stats"]["pitching"]
    outs = pit.get("outs")
    assert outs == 16  # 5.1 IP
    ip = outs / 3
    era = 9 * pit["earnedRuns"] / ip
    whip = (pit["hits"] + pit["baseOnBalls"]) / ip
    print(f"   Flaherty outs={outs} ERA={era:.2f} WHIP={whip:.2f} K={pit['strikeOuts']}")
    assert abs(era - (9 * 2 / (16 / 3))) < 1e-9

    print("3) Standings 2024")
    standings = get("/standings?leagueId=103,104&season=2024")
    lad = nyy = None
    for division in standings["records"]:
        for row in division["teamRecords"]:
            if row["team"]["id"] == 119:
                lad = row
            if row["team"]["id"] == 147:
                nyy = row
    assert lad and nyy
    print(f"   LAD {lad['wins']}-{lad['losses']} ({lad['winningPercentage']})")
    print(f"   NYY {nyy['wins']}-{nyy['losses']} ({nyy['winningPercentage']})")
    assert lad["winningPercentage"] == ".605"

    print("4) Team logo CDN (not Stats API)")
    logo_req = urllib.request.Request(
        "https://www.mlbstatic.com/team-logos/119.svg", headers={"User-Agent": UA}
    )
    with urllib.request.urlopen(logo_req, timeout=30, context=_ssl_context()) as resp:
        assert resp.status == 200
        body = resp.read(64)
        assert body.startswith(b"<svg") or b"svg" in body.lower()
    print("   mlbstatic.com/team-logos/119.svg OK")

    print("\nAll smoke checks passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
