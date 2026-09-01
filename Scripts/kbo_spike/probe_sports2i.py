#!/usr/bin/env python3
"""Minimal KBO Sports2i spike probe. Writes JSON under Scripts/kbo_spike/out/."""

from __future__ import annotations

import json
import ssl
import urllib.request
from collections import defaultdict
from pathlib import Path

BASE = "https://sportsstatsjson.sports2i.com/ws/BaseBall.asmx"
OUT = Path(__file__).resolve().parent / "out"
CTX = ssl._create_unverified_context()


def get(path_query: str):
    url = f"{BASE}/{path_query}"
    req = urllib.request.Request(url, headers={"User-Agent": "IWasThere/0.1 (kbo-spike)"})
    with urllib.request.urlopen(req, timeout=60, context=CTX) as resp:
        return url, json.loads(resp.read().decode("utf-8"))


def save(name: str, data) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.json"
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote {path.name} ({len(data) if isinstance(data, list) else type(data)})")


def main() -> None:
    season, gdt = "2025", "20250422"
    url, games = get(f"Game?season={season}&gDt={gdt}")
    print("schedule", url, "count", len(games))
    save("schedule", games)

    finals = [g for g in games if str(g.get("state_sc")) == "3"]
    if not finals:
        raise SystemExit("No final games on sample date")
    game = finals[0]
    gid = game["g_id"]
    print("using", gid, game.get("a_t_id"), "@", game.get("h_t_id"))

    _, team_rec = get(f"GameTeamRecord?season={season}&gDt={gdt}")
    save("team_record", [r for r in team_rec if r.get("g_id") == gid])

    _, starters = get(f"GameStartPitcherRecord?season={season}&gDt={gdt}")
    save("starters", [r for r in starters if r.get("g_id") == gid])

    _, hitters = get(f"GameHitterBoxScore?season={season}&gDt={gdt}")
    hitters = [r for r in hitters if r.get("g_id") == gid]
    save("hitters", hitters)

    _, pitchers = get(f"GamePitcherBoxScore?season={season}&gDt={gdt}")
    pitchers = [r for r in pitchers if r.get("g_id") == gid]
    save("pitchers", pitchers)

    runs: dict[str, int] = defaultdict(int)
    for row in hitters:
        runs[row["tb_sc"]] += int(row.get("run_cn") or 0)
    print("derived score", dict(runs))

    _, rank = get(f"TeamRank?season={season}&gDt={gdt}")
    standings = [
        r
        for r in rank
        if r.get("le_id") == "1" and r.get("sr_id") == "0" and not r.get("group_sc")
    ]
    save("standings", standings)
    print("standings top3", [(r["t_id"], r["w_cn"], r["l_cn"], r["wra_rt"]) for r in standings[:3]])


if __name__ == "__main__":
    main()
