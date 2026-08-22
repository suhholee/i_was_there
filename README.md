# iWasThere

MLB **직관 로그** (attendance diary) for iOS: log games you attended, attach photos/notes later, and accumulate **team/player stats only for those games**.

Display name: **#iWasThere**. Local-first SwiftUI prototype — no cloud backend. Remote data = [MLB Stats API](https://statsapi.mlb.com/).

## Current status

| Piece | Status |
|-------|--------|
| Tabs: Games · Home · Leaders · Settings | Done |
| **Add Game** (date → Final matchup → save boxscore) | **Phase 1 done** |
| Games list + detail (batters/pitchers, computed rates) | **Phase 1 done** |
| Photos & notes diary | Phase 2 |
| Attendance W% / Leaders / jersey cards | Phase 3 |
| Season dropdown + season-context WAR/wOBA/wRC+/FIP | Phase 3 (same MLB API `stats=sabermetrics`) |

## Architecture

```text
SwiftUI (Home / Games / Leaders / Settings / Add Game)
        │
        ├─► MLBClient ──► statsapi.mlb.com (schedule, boxscore, standings, sabermetrics later)
        │
        └─► SwiftData (AttendedGame, GamePlayerStat, …) + PhotoStore (Phase 2)
```

**Attendance-scoped stats (now):** store counting stats from the boxscore; compute AVG / OBP / SLG / OPS / ERA / WHIP / ISO / BABIP / K/9 via `StatFormulas` (BREF/MLB definitions). Sum counts across games, then divide.

**Season-context stats (Phase 3):** filter by season in the UI and load WAR, wOBA, wRC+, FIP from the **same** MLB Stats API (`stats=sabermetrics`, `seasonAdvanced`, `expectedStatistics`). These are season metrics — not summed from your attendance log.

## How to build & run

1. One-time Xcode setup (if needed):

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
```

2. Open and run:

```bash
cd /Users/suhholee/Desktop/i_was_there
xcodegen generate   # if .xcodeproj missing or after adding files
open IWasThere.xcodeproj
```

Select an iPhone simulator → **⌘R**.

3. Try Phase 1: **Home → Add game** (or Games **+**) → pick a past date with Final games (e.g. **Oct 25, 2024**) → select Yankees @ Dodgers → **Save to my log** → open the game for lines + computed OPS/ERA.

## Test MLB stats (no app)

```bash
python3 Scripts/smoke_mlb_api.py
```

Checks schedule, boxscore counting stats, computed rate formulas, standings, and team logo CDN.

## API cheat sheet

| Need | Endpoint |
|------|----------|
| Games on a date | `/api/v1/schedule?sportId=1&date=YYYY-MM-DD` |
| Box score | `/api/v1/game/{gamePk}/boxscore` |
| Standings | `/api/v1/standings?leagueId=103,104&season=YYYY` |
| Season sabermetrics (Phase 3) | `/api/v1/people/{id}/stats?stats=sabermetrics&group=hitting&season=YYYY&sportId=1` |

Jersey **numbers** come from the boxscore; jersey **art** and team **colors** are drawn in-app. Logos: `https://www.mlbstatic.com/team-logos/{teamId}.svg`.

## Roadmap

1. Phase 0 — shell + models + client  
2. **Phase 1 — Add Game + detail lines (current)**  
3. Phase 2 — photos + notes  
4. Phase 3 — Home W%, Leaders, jersey cards, **season dropdown + sabermetrics context**  
5. Phase 4 — polish  

## License / API note

MLB content is subject to [MLBAM terms](http://gdx.mlb.com/components/copyright.txt). Personal prototype only.
