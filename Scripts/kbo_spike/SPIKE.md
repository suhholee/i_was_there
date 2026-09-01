# KBO API Spike Report

**Branch:** `feature/kbo`  
**Date:** 2026-08-26  
**Source under test:** Sports2i public JSON (`https://sportsstatsjson.sports2i.com/ws/BaseBall.asmx/...`)

## Verdict

**KBO support is feasible for a first `#iWasThere` KBO mode**, using Sports2i — not an official KBO developer API.

It can cover the core loop (pick date → finished game → player lines → standings → season totals), with these caveats:

1. **Unofficial / partner-style feed** — can change or lock down; SSL cert chain is messy on some clients.
2. **Full MLB-parity box lines are incomplete** — classic `GameHitterRecord` / `GamePitcherRecord` return `[]`; use **BoxScore** endpoints instead (fewer batter counting stats).
3. **Attendance** — not found.
4. **Inning scoreboard endpoints** (`ScoreInning` / `Scorerheb`) — empty/error publicly; **final score can be derived** by summing `GameHitterBoxScore.run_cn` per team (validated NC 6 – LG 5 for `20250422NCLG0`).

## Working endpoints (probed live)

| Need | Endpoint | Status |
|------|----------|--------|
| Schedule by date | `Game?season={yyyy}&gDt={yyyyMMdd}` | ✅ |
| Team W/L for game | `GameTeamRecord?season=&gDt=` | ✅ `result_sc` W/L/D |
| Starters | `GameStartPitcherRecord?season=&gDt=` | ✅ `t_pit_p_id` / `b_pit_p_id` |
| Batter game lines | `GameHitterBoxScore?season=&gDt=` | ✅ filter client-side by `g_id` |
| Pitcher game lines | `GamePitcherBoxScore?season=&gDt=` | ✅ filter by `g_id` |
| Diary extras (HR notes etc.) | `GameEtcInfo?season=&gDt=` | ✅ Korean notes; no attendance |
| Teams | `Team?season=` | ✅ filter `le_id=1` (10 clubs + All-Star) |
| Players | `Player?season=` | ✅ large; filter `le_id=1` |
| Standings | `TeamRank?season=&gDt=` | ✅ W/L/D + win% |
| Season batting | `SeasonBatterRecord?season=&gDt=` | ✅ includes OPS |
| Season pitching | `SeasonPitcherRecord?season=&gDt=` | ✅ includes ERA/WHIP |

## Broken / empty (do not rely on)

| Endpoint | Result |
|----------|--------|
| `GameHitterRecord` | always `[]` in probes (2015–2025) |
| `GamePitcherRecord` | always `[]` |
| `ScoreInning` / `Scoreining` / `Scorerheb` | empty or 500 |
| `LiveHitterRecord` / `LivePitcherRecord` | empty for historical dates |

## Sample game proof

- Date `20250422`, game `20250422NCLG0` (NC @ LG), `state_sc=3` (final)
- `GameTeamRecord`: NC `W`, LG `L`
- Derived score from batter box `run_cn`: **NC 6 – LG 5**
- Pitcher box includes IP outs (`inn2_cn`), K, ER, W/H/S/L flags
- Starters: away `68902`, home `61101` (resolve names via `Player`)

## Field mapping vs current MLB app

| App feature | MLB | KBO via Sports2i |
|-------------|-----|------------------|
| Add game by date | schedule | `Game` |
| Final only | abstractGameState | `state_sc` (`3` = 종료) |
| Scores | schedule scores | derive from box `run_cn` (or find better later) |
| Batter AB/H/RBI | boxscore | BoxScore ✅ |
| Batter HR/BB/TB/OPS game lines | boxscore | ❌ incomplete in BoxScore (HR/BB/TB missing) |
| Pitcher IP/K/ER | boxscore | BoxScore ✅ (`inn2_cn` = outs) |
| Starters | boxscore | `GameStartPitcherRecord` ✅ |
| Standings / favorite W% | standings | `TeamRank` ✅ (KBO has draws) |
| Player season OPS/ERA | people/stats | SeasonBatter/Pitcher ✅ |
| Attendance | boxscore info | ❌ not found |
| Team themes/logos | local + mlbstatic | local map for 10 teams; logos TBD |

**Leaders implication:** KBO attendance leaders can support AVG, R, RBI, pitcher ERA/K/IP initially. Full OPS/HR categories need another source or play-string parsing later.

## League switch architecture (recommended)

Keep MLB data; add `league` on models (`mlb` | `kbo`) and an `activeLeague` on profile. Queries filter by active league. Introduce `SportProvider` protocol:

- `schedule(date)`
- `boxscore(gameID)`
- `standings(season)`
- `player(id)` / `seasonStats(id)`

`MLBClient` and `KBOSports2iClient` both conform.

KBO team codes: `HH, HT, KT, LG, LT, NC, OB, SK, SS, WO` (`SK` = SSG).

## Risks

- No public ToS / SLA — treat as prototype-grade.
- Large payloads (`Player` ~2MB, season stats ~3–5MB) — cache on device.
- `g_id` filter on BoxScore may be ignored server-side — always filter client-side.
- Player IDs appear across `le_id` values (Futures etc.) — prefer `le_id=1` + team code.

## Next implementation step (when approved)

1. Add `League` + `SportProvider` stubs.
2. Implement `KBOSports2iClient` for schedule → box → standings.
3. Persist `AttendedGame.league` and filter Home/Games/Leaders.
4. Ship reduced KBO leader categories first; expand OPS/HR when a richer line source is found.

## Reproduce

```bash
cd Scripts/kbo_spike
python3 probe_sports2i.py
```
