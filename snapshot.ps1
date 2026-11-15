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

# Full box score for one finished game: team totals + player lines (cached on disk, so later runs only fetch new games)
$cacheDir = Join-Path $PSScriptRoot "cache"; New-Item -ItemType Directory -Force $cacheDir | Out-Null
function Split2($v) { $p = "$v".Split('-'); @((num $p[0]), (num $p[1])) }
function GameBox($eventId) {
  $f = Join-Path $cacheDir "box-$eventId.json"
  if (Test-Path $f) { return (Get-Content $f -Raw | ConvertFrom-Json) }
  $s = (Invoke-WebRequest -UseBasicParsing "$base/summary?event=$eventId").Content | ConvertFrom-Json
  $players = @()
  foreach ($tp in $s.boxscore.players) {
    $st = $tp.statistics[0]; $k = @($st.keys)
    foreach ($a in $st.athletes) {
      if ($a.didNotPlay -or -not $a.stats -or $a.stats.Count -eq 0) { continue }
      $m = @{}; for ($i=0; $i -lt $k.Count; $i++) { $m[$k[$i]] = $a.stats[$i] }
      $fg = Split2 $m['fieldGoalsMade-fieldGoalsAttempted']; $t3 = Split2 $m['threePointFieldGoalsMade-threePointFieldGoalsAttempted']; $ft = Split2 $m['freeThrowsMade-freeThrowsAttempted']
      $players += [ordered]@{ id="$($a.athlete.id)"; n=$a.athlete.displayName; t=$tp.team.abbreviation; min=num $m['minutes']; pts=num $m['points'];
        reb=num $m['rebounds']; oreb=num $m['offensiveRebounds']; ast=num $m['assists']; stl=num $m['steals']; blk=num $m['blocks'];
        to=num $m['turnovers']; pf=num $m['fouls']; fgm=$fg[0]; fga=$fg[1]; tpm=$t3[0]; ftm=$ft[0]; fta=$ft[1]; pm=num $m['plusMinus'] }
    }
  }
  $teams = @()
  foreach ($tt in $s.boxscore.teams) {
    $m = @{}; foreach ($x in $tt.statistics) { $m[$x.name] = $x.displayValue }
    $fg = Split2 $m['fieldGoalsMade-fieldGoalsAttempted']; $ft = Split2 $m['freeThrowsMade-freeThrowsAttempted']
    $ab = $tt.team.abbreviation; $pts = 0; foreach ($p in $players) { if ($p.t -eq $ab) { $pts += $p.pts } }
    $teams += [ordered]@{ t=$ab; pts=$pts; fgm=$fg[0]; fga=$fg[1]; ftm=$ft[0]; fta=$ft[1]; oreb=num $m['offensiveRebounds']; reb=num $m['totalRebounds'];
      ast=num $m['assists']; to=num $m['totalTurnovers']; pf=num $m['fouls'] }
  }
  $box = [ordered]@{ teams=$teams; players=$players }
  [IO.File]::WriteAllText($f, (ConvertTo-Json $box -Depth 4 -Compress), (New-Object Text.UTF8Encoding $false))
  return ((ConvertTo-Json $box -Depth 4 -Compress) | ConvertFrom-Json)
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

# Walk every regular-season box score through $Date, keeping running season totals. From them come
# season plus/minus, team ratings, and day-by-day trendlines for the current top 5 in each category.
$start = ([datetime]$lj.currentSeason.type.startDate).Date; $end = [datetime]::ParseExact($Date, 'yyyyMMdd', $null)
$tot = @{}; $T = @{}; $lg = @{ pts=0.0; fgm=0.0; fga=0.0; ftm=0.0; fta=0.0; oreb=0.0; reb=0.0; ast=0.0; to=0.0; pf=0.0; poss=0.0; min=0.0 }
$trendCats = [ordered]@{ pointsPerGame='pts'; reboundsPerGame='reb'; assistsPerGame='ast'; blocksPerGame='blk'; stealsPerGame='stl'; PER='per' }
$track = @{}; foreach ($cat in $trendCats.Keys) { $track[$cat] = @($leaders[$cat] | ForEach-Object { "$($_.id)" }) }
$series = @{}; foreach ($cat in $trendCats.Keys) { $series[$cat] = @{}; foreach ($id in $track[$cat]) { $series[$cat][$id] = New-Object System.Collections.ArrayList } }
$trendDates = New-Object System.Collections.ArrayList; $perHist = @{}; $lastPer = @{}
function Poss($t) { $t.fga - $t.oreb + $t.to + 0.44 * $t.fta }
function PerAll {
  # Hollinger PER from running totals: unadjusted PER, pace-adjusted, then scaled so the league average is 15.
  $out = @{}; if ($lg.fgm -le 0 -or $lg.pf -le 0) { return $out }
  $factor = (2/3) - (0.5 * ($lg.ast / $lg.fgm)) / (2 * ($lg.fgm / $lg.ftm))
  $vop = $lg.pts / ($lg.fga - $lg.oreb + $lg.to + 0.44 * $lg.fta)
  $drb = ($lg.reb - $lg.oreb) / $lg.reb
  $pfTerm = ($lg.ftm / $lg.pf) - 0.44 * ($lg.fta / $lg.pf) * $vop
  $lgPace = 48 * $lg.poss / ($lg.min / 5)
  $sumA = 0.0; $sumMin = 0.0
  foreach ($kv in $tot.GetEnumerator()) {
    $p = $kv.Value; $tm = $T[$p.t]; if ($p.min -le 0 -or -not $tm -or $tm.fgm -le 0) { continue }
    $ar = $tm.ast / $tm.fgm
    $u = (1 / $p.min) * ($p.tpm + (2/3) * $p.ast + (2 - $factor * $ar) * $p.fgm + $p.ftm * 0.5 * (1 + (1 - $ar) + (2/3) * $ar) -
      $vop * $p.to - $vop * $drb * ($p.fga - $p.fgm) - $vop * 0.44 * (0.44 + 0.56 * $drb) * ($p.fta - $p.ftm) +
      $vop * (1 - $drb) * ($p.reb - $p.oreb) + $vop * $drb * $p.oreb + $vop * $p.stl + $vop * $drb * $p.blk - $p.pf * $pfTerm)
    $a = ($lgPace / (48 * $tm.poss / ($tm.min / 5))) * $u
    $out[$kv.Key] = $a; $sumA += $a * $p.min; $sumMin += $p.min
  }
  $lgA = $sumA / $sumMin; foreach ($k in @($out.Keys)) { $out[$k] = $out[$k] * 15 / $lgA }
  $out
}
for ($day = $start; $day -le $end; $day = $day.AddDays(1)) {
  $ds = $day.ToString('yyyyMMdd'); $idx = Join-Path $cacheDir "day-$ds.json"
  if (Test-Path $idx) { $ids = @((Get-Content $idx -Raw | ConvertFrom-Json) | ForEach-Object { $_ }) }
  else {
    $evs = @(((Invoke-WebRequest -UseBasicParsing "$base/scoreboard?dates=$ds").Content | ConvertFrom-Json).events)
    $ids = @($evs | Where-Object { $_.status.type.completed } | ForEach-Object { $_.id })
    if ($ids.Count -eq $evs.Count) { [IO.File]::WriteAllText($idx, (ConvertTo-Json @($ids) -Compress)) }
  }
  $played = $false
  foreach ($id in $ids) { if (-not $id) { continue }
    $box = GameBox $id; $bt = @($box.teams); if ($bt.Count -ne 2) { continue }
    $played = $true
    $gp = ((Poss $bt[0]) + (Poss $bt[1])) / 2
    foreach ($r in $box.players) {
      $key = "$($r.id)"
      if (-not $tot.ContainsKey($key)) { $tot[$key] = @{ n=$r.n; t=$r.t; gp=0; pm=0.0; min=0.0; pts=0.0; reb=0.0; oreb=0.0; ast=0.0; stl=0.0; blk=0.0; to=0.0; pf=0.0; fgm=0.0; fga=0.0; tpm=0.0; ftm=0.0; fta=0.0 } }
      $x = $tot[$key]; $x.gp++; $x.t = $r.t
      foreach ($f in 'pm','min','pts','reb','oreb','ast','stl','blk','to','pf','fgm','fga','tpm','ftm','fta') { $x[$f] += $r.$f }
    }
    for ($i = 0; $i -lt 2; $i++) {
      $me = $bt[$i]; $op = $bt[1 - $i]
      if (-not $T.ContainsKey($me.t)) { $T[$me.t] = @{ gp=0; pts=0.0; opp=0.0; poss=0.0; min=0.0; ast=0.0; fgm=0.0 } }
      $tm = $T[$me.t]; $tm.gp++; $tm.pts += $me.pts; $tm.opp += $op.pts; $tm.poss += $gp; $tm.ast += $me.ast; $tm.fgm += $me.fgm
      foreach ($r in $box.players) { if ($r.t -eq $me.t) { $tm.min += $r.min } }
      foreach ($f in 'pts','fgm','fga','ftm','fta','oreb','reb','ast','to','pf') { $lg[$f] += $me.$f }
      $lg.poss += $gp
    }
  }
  if (-not $played) { continue }
  $lg.min = 0.0; foreach ($tm in $T.Values) { $lg.min += $tm.min }
  [void]$trendDates.Add($day.ToString('yyyy-MM-dd'))
  $per = PerAll; $di = $trendDates.Count - 1
  foreach ($kv in $per.GetEnumerator()) { if ($tot[$kv.Key].gp -ge 3) { if (-not $perHist.ContainsKey($kv.Key)) { $perHist[$kv.Key] = @{} }; $perHist[$kv.Key][$di] = [Math]::Round($kv.Value, 1) } }
  $lastPer = $per
  foreach ($cat in $trendCats.Keys) {
    $stat = $trendCats[$cat]; if ($stat -eq 'per') { continue }
    foreach ($id in $track[$cat]) {
      $x = $tot[$id]; $v = $null
      # Each line starts at a player's 3rd game, so one hot opening night doesn't swamp the chart.
      if ($x -and $x.gp -ge 3) { $v = if ($stat -eq 'per') { if ($per.ContainsKey($id)) { [Math]::Round($per[$id], 1) } } else { [Math]::Round($x[$stat] / $x.gp, 1) } }
      [void]$series[$cat][$id].Add($v)
    }
  }
}
$trends = [ordered]@{ dates=@($trendDates); cats=[ordered]@{} }
foreach ($cat in $trendCats.Keys) {
  if ($cat -eq 'PER') { continue }
  $trends.cats[$cat] = @($leaders[$cat] | ForEach-Object { [ordered]@{ id="$($_.id)"; n=$_.n; t=$_.t; v=@($series[$cat]["$($_.id)"]) } })
}
# PER trend: ESPN's PER board includes players with only a couple of games, so rank qualified players ourselves.
$maxGpAll = 0; foreach ($x in $tot.Values) { if ($x.gp -gt $maxGpAll) { $maxGpAll = $x.gp } }
$qGp = [Math]::Max(3, [Math]::Ceiling(0.7 * $maxGpAll))
$trends.perRule = "min. $qGp games, 15 min per game"
$trends.cats['PER'] = @($lastPer.GetEnumerator() | Where-Object { $x = $tot[$_.Key]; $x.gp -ge $qGp -and ($x.min / $x.gp) -ge 15 } |
  Sort-Object Value -Descending | Select-Object -First 5 | ForEach-Object {
    $id = $_.Key; $h = $perHist[$id]
    [ordered]@{ id=$id; n=$tot[$id].n; t=$tot[$id].t; v=@(for ($i = 0; $i -lt $trendDates.Count; $i++) { if ($h -and $h.ContainsKey($i)) { $h[$i] } else { $null } }) } })
$shortOf = @{}; foreach ($r in ($standings.west + $standings.east)) { $shortOf[$r.abbr] = $r.short }
$teamStats = @($T.GetEnumerator() | Where-Object { $_.Value.poss -gt 0 } | ForEach-Object {
  $tm = $_.Value; $c = $colors[$_.Key]; if (-not $c) { $c = @('#1d428a','#c8102e') }
  $o = 100 * $tm.pts / $tm.poss; $dr = 100 * $tm.opp / $tm.poss
  [ordered]@{ abbr=$_.Key; short=$shortOf[$_.Key]; color=$c[0]; alt=$c[1]; gp=$tm.gp; ppg=[Math]::Round($tm.pts / $tm.gp, 1); oppg=[Math]::Round($tm.opp / $tm.gp, 1);
    ortg=[Math]::Round($o, 1); drtg=[Math]::Round($dr, 1); net=[Math]::Round($o - $dr, 1); pace=[Math]::Round($tm.poss / $tm.gp, 1) } })
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
$obj = [ordered]@{ date=$d; fetched=(Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mmZ"); season=$lj.currentSeason.displayName; pmRule=$pmRule; games=$games; standings=$standings; leaders=$leaders; teamStats=$teamStats; trends=$trends }
$json = $obj | ConvertTo-Json -Depth 8 -Compress
[IO.File]::WriteAllText($Out, $json, (New-Object Text.UTF8Encoding $false))
"games=$($games.Count) west=$($standings.west.Count) east=$($standings.east.Count) per=$($leaders.PER.Count) bytes=$($json.Length)"
