# Pulls one night of NBA games, conference standings and season leaders from ESPN into the compact JSON the page embeds.
# Usage: .\snapshot.ps1 -Date 20261113 -Out data.json
param([string]$Date = (Get-Date).AddDays(-1).ToString('yyyyMMdd'), [string]$Out = "data.json")
$base = "https://site.api.espn.com/apis/site/v2/sports/basketball/nba"
function num($v) { if ($v -eq $null -or $v -eq '' -or $v -eq '--') { 0 } else { [double]("$v" -replace '^\+','') } }

$sb = (Invoke-WebRequest -UseBasicParsing "$base/scoreboard?dates=$Date").Content | ConvertFrom-Json
$games = @()
foreach ($e in $sb.events) {
  $comp = $e.competitions[0]
  $s = (Invoke-WebRequest -UseBasicParsing "$base/summary?event=$($e.id)").Content | ConvertFrom-Json
  $teams = @($comp.competitors | ForEach-Object {
    [ordered]@{ abbr=$_.team.abbreviation; name=$_.team.displayName; short=$_.team.shortDisplayName; color="#"+$_.team.color; alt="#"+$_.team.alternateColor;
      score=[int](num $_.score); record=$(if ($_.records) { $_.records[0].summary } else { "" }); home=($_.homeAway -eq 'home'); winner=[bool]$_.winner }
  })
  $players = @()
  foreach ($tp in $s.boxscore.players) {
    $st = $tp.statistics[0]; $k = @($st.keys)
    foreach ($a in $st.athletes) {
      if ($a.didNotPlay -or -not $a.stats -or $a.stats.Count -eq 0) { continue }
      $m = @{}; for ($i=0; $i -lt $k.Count; $i++) { $m[$k[$i]] = $a.stats[$i] }
      $fg = "$($m['fieldGoalsMade-fieldGoalsAttempted'])".Split('-'); $tp3 = "$($m['threePointFieldGoalsMade-threePointFieldGoalsAttempted'])".Split('-'); $ft = "$($m['freeThrowsMade-freeThrowsAttempted'])".Split('-')
      $players += [ordered]@{ id=$a.athlete.id; n=$a.athlete.displayName; t=$tp.team.abbreviation; pos=$a.athlete.position.abbreviation;
        min=num $m['minutes']; pts=num $m['points']; reb=num $m['rebounds']; oreb=num $m['offensiveRebounds']; dreb=num $m['defensiveRebounds'];
        ast=num $m['assists']; stl=num $m['steals']; blk=num $m['blocks']; to=num $m['turnovers']; pf=num $m['fouls'];
        fgm=num $fg[0]; fga=num $fg[1]; tpm=num $tp3[0]; tpa=num $tp3[1]; ftm=num $ft[0]; fta=num $ft[1]; pm=num $m['plusMinus'] }
    }
  }
  $games += [ordered]@{ id=$e.id; detail=$e.status.type.shortDetail; final=($e.status.type.completed -eq $true); teams=$teams; players=$players }
}

# Plus/minus rows for one game (cached on disk once the game is final, so later runs only fetch new games)
$cacheDir = Join-Path $PSScriptRoot "cache"; New-Item -ItemType Directory -Force $cacheDir | Out-Null
function GamePM($eventId) {
  $f = Join-Path $cacheDir "pm-$eventId.json"
  if (Test-Path $f) { return ,@((Get-Content $f -Raw | ConvertFrom-Json) | ForEach-Object { $_ }) }
  $s = (Invoke-WebRequest -UseBasicParsing "$base/summary?event=$eventId").Content | ConvertFrom-Json
  $rows = @()
  foreach ($tp in $s.boxscore.players) {
    $st = $tp.statistics[0]; $k = @($st.keys); $iPm = [array]::IndexOf($k, 'plusMinus'); $iMin = [array]::IndexOf($k, 'minutes')
    foreach ($a in $st.athletes) {
      if ($a.didNotPlay -or -not $a.stats -or $a.stats.Count -eq 0) { continue }
      $rows += [ordered]@{ id=$a.athlete.id; n=$a.athlete.displayName; t=$tp.team.abbreviation; pm=(num $a.stats[$iPm]); min=(num $a.stats[$iMin]) }
    }
  }
  [IO.File]::WriteAllText($f, (ConvertTo-Json @($rows) -Depth 3 -Compress), (New-Object Text.UTF8Encoding $false))
  ,$rows
}

# Conference standings (team colors come from the teams list)
$colors = @{}
$tj = (Invoke-WebRequest -UseBasicParsing "$base/teams").Content | ConvertFrom-Json
foreach ($t in $tj.sports[0].leagues[0].teams) { $colors[$t.team.abbreviation] = @(("#" + $t.team.color), ("#" + $t.team.alternateColor)) }
$sj = (Invoke-WebRequest -UseBasicParsing "https://site.api.espn.com/apis/v2/sports/basketball/nba/standings").Content | ConvertFrom-Json
$standings = [ordered]@{}
foreach ($conf in $sj.children) {
  $key = if ($conf.name -match 'West') { 'west' } else { 'east' }
  $rows = @($conf.standings.entries | ForEach-Object {
    $st = @{}; foreach ($x in $_.stats) { $st[$x.name] = $x }
    $c = $colors[$_.team.abbreviation]; if (-not $c) { $c = @('#1d428a','#c8102e') }
    [ordered]@{ abbr=$_.team.abbreviation; short=$_.team.shortDisplayName; color=$c[0]; alt=$c[1]; seed=[int]$st['playoffSeed'].value;
      w=[int]$st['wins'].value; l=[int]$st['losses'].value; gb=$st['gamesBehind'].displayValue; streak=$st['streak'].displayValue }
  } | Sort-Object { $_.seed })
  $standings[$key] = $rows
}

# Season shooting splits (per game) for the scoring leaders
$bj = (Invoke-WebRequest -UseBasicParsing "https://site.web.api.espn.com/apis/common/v3/sports/basketball/nba/statistics/byathlete?category=offensive&sort=offensive.avgPoints:desc&limit=50").Content | ConvertFrom-Json
$on = @(($bj.categories | Where-Object { $_.name -eq 'offensive' }).names)
$splits = @{}
foreach ($a in $bj.athletes) {
  $c = $a.categories | Where-Object { $_.name -eq 'offensive' }; $m = @{}
  for ($i=0; $i -lt $on.Count; $i++) { $m[$on[$i]] = $c.totals[$i] }
  $splits["$($a.athlete.id)"] = [ordered]@{ fgm=$m.avgFieldGoalsMade; fga=$m.avgFieldGoalsAttempted; fg=$m.fieldGoalPct;
    tpm=$m.avgThreePointFieldGoalsMade; tpa=$m.avgThreePointFieldGoalsAttempted; tp=$m.threePointFieldGoalPct;
    ftm=$m.avgFreeThrowsMade; fta=$m.avgFreeThrowsAttempted; ft=$m.freeThrowPct }
}

# Season leaders from ESPN
$lj = (Invoke-WebRequest -UseBasicParsing "https://site.api.espn.com/apis/site/v3/sports/basketball/nba/leaders?limit=5").Content | ConvertFrom-Json
$leaders = [ordered]@{}
foreach ($cat in 'pointsPerGame','reboundsPerGame','assistsPerGame','blocksPerGame','stealsPerGame','PER','3PointsMadePerGame','avgTurnovers') {
  $c = $lj.leaders.categories | Where-Object { $_.name -eq $cat }
  $leaders[$cat] = @($c.leaders | ForEach-Object { $row = [ordered]@{ id=$_.athlete.id; n=$_.athlete.displayName; pos=$_.athlete.position.abbreviation;
    t=$_.team.abbreviation; tname=$_.team.shortDisplayName; color="#"+$_.team.color; alt="#"+$_.team.alternateColor; v=$_.displayValue }
    if ($cat -eq 'pointsPerGame') { $row.sp = $splits["$($_.athlete.id)"] }
    $row })
}

# Season plus/minus per game, added up from every regular-season box score through $Date
$start = ([datetime]$lj.currentSeason.type.startDate).Date; $end = [datetime]::ParseExact($Date, 'yyyyMMdd', $null)
$tot = @{}
for ($day = $start; $day -le $end; $day = $day.AddDays(1)) {
  $ds = $day.ToString('yyyyMMdd'); $idx = Join-Path $cacheDir "day-$ds.json"
  if (Test-Path $idx) { $ids = @((Get-Content $idx -Raw | ConvertFrom-Json) | ForEach-Object { $_ }) }
  else {
    $evs = @(((Invoke-WebRequest -UseBasicParsing "$base/scoreboard?dates=$ds").Content | ConvertFrom-Json).events)
    $ids = @($evs | Where-Object { $_.status.type.completed } | ForEach-Object { $_.id })
    if ($ids.Count -eq $evs.Count) { [IO.File]::WriteAllText($idx, (ConvertTo-Json @($ids) -Compress)) }
  }
  foreach ($id in $ids) { if (-not $id) { continue }
    foreach ($r in (GamePM $id)) {
      $key = "$($r.id)"; if (-not $tot.ContainsKey($key)) { $tot[$key] = @{ n=$r.n; t=$r.t; gp=0; pm=0.0; min=0.0 } }
      $x = $tot[$key]; $x.gp++; $x.pm += $r.pm; $x.min += $r.min; $x.t = $r.t
    }
  }
}
$maxGp = 0; foreach ($x in $tot.Values) { if ($x.gp -gt $maxGp) { $maxGp = $x.gp } }
$minGp = [Math]::Max(3, [Math]::Ceiling(0.7 * $maxGp))
$leaders['plusMinus'] = @($tot.GetEnumerator() | Where-Object { $_.Value.gp -ge $minGp -and ($_.Value.min / $_.Value.gp) -ge 15 } |
  Sort-Object { $_.Value.pm / $_.Value.gp } -Descending | Select-Object -First 5 | ForEach-Object {
    $x = $_.Value; $c = $colors[$x.t]; if (-not $c) { $c = @('#1d428a','#c8102e') }
    $avg = $x.pm / $x.gp
    [ordered]@{ id=$_.Key; n=$x.n; t=$x.t; tname=(($standings.west + $standings.east) | Where-Object { $_.abbr -eq $x.t } | Select-Object -First 1).short;
      color=$c[0]; alt=$c[1]; v=('{0}{1:0.0}' -f $(if ($avg -ge 0) { '+' } else { '' }), $avg); gp=$x.gp } })
$pmRule = "min. $minGp games, 15 min per game"

$d = "{0}-{1}-{2}" -f $Date.Substring(0,4), $Date.Substring(4,2), $Date.Substring(6,2)
$obj = [ordered]@{ date=$d; fetched=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mmZ"); season=$lj.currentSeason.displayName; pmRule=$pmRule; games=$games; standings=$standings; leaders=$leaders }
$json = $obj | ConvertTo-Json -Depth 8 -Compress
[IO.File]::WriteAllText($Out, $json, (New-Object Text.UTF8Encoding $false))
"games=$($games.Count) west=$($standings.west.Count) east=$($standings.east.Count) per=$($leaders.PER.Count) bytes=$($json.Length)"
