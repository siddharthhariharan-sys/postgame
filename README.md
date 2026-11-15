# Daily NBA Tracker

An unofficial fan site with last night's NBA games: top performers, conference standings, stat leaders, box score milestones, a box score for every game, and season leaders. Works on desktop and mobile, with light, dark and team color modes.

## How it stays up to date

- **In the browser:** the page loads live scores, standings and leaders from ESPN's public API every time it opens. It refreshes every minute while games are in progress and every 10 minutes otherwise.
- **Every morning (GitHub Actions):** `.github/workflows/update.yml` runs `snapshot.ps1` to save the previous night's games, then walks every box score of the season (each game is cached in `cache/box-<id>.json`) to compute what ESPN doesn't publish:
  - season plus/minus per game
  - team offensive, defensive and net ratings (points per 100 estimated possessions)
  - trendlines: the current top 5 in PPG, RPG, APG, BPG, SPG and PER, with each player's season average after every game day (PER uses Hollinger's formula)
  
  Then the workflow rebuilds and redeploys the site. The saved data is the fallback if ESPN can't be reached.

To refresh by hand, open the **Actions** tab, choose **Update data and deploy**, and click **Run workflow**.

## Files

| File | What it does |
| --- | --- |
| `template.html` | The page: layout, styles and all rendering code |
| `snapshot.ps1` | Pulls one night of data from ESPN into `data.json` |
| `build.ps1` | Combines `template.html` + `data.json` into `_site/index.html` |
| `data.json` | Latest saved snapshot |
| `cache/` | Per-game plus/minus rows, so daily runs only fetch new games |

## Run locally

```powershell
.\snapshot.ps1 -Date 20261113 -Out data.json
.\build.ps1
start _site\index.html
```

Data from ESPN. Not affiliated with the NBA or ESPN.
