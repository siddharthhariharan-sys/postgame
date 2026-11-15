# Builds the website from template.html + data.json.
#   .\build.ps1                 -> _site\index.html (full page for GitHub Pages)
#   .\build.ps1 -Fragment       -> index.html (page body only, for the claude.ai artifact)
param([string]$Data = "data.json", [string]$OutDir = "_site", [switch]$Fragment)
$root = $PSScriptRoot
$template = [IO.File]::ReadAllText((Join-Path $root "template.html"))
$json = [IO.File]::ReadAllText((Join-Path $root $Data)).Replace("</", "<\/")
$body = $template.Replace("__SNAPSHOT__", $json)
$utf8 = New-Object Text.UTF8Encoding $false

if ($Fragment) {
  [IO.File]::WriteAllText((Join-Path $root "index.html"), $body, $utf8)
  "Wrote index.html (fragment)"
  return
}

$head = @'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="description" content="Daily NBA Tracker: last night's top performers, standings, stat leaders, box scores and season leaders.">
<meta name="theme-color" content="#1d428a">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 40 40'%3E%3Ccircle cx='20' cy='20' r='18' fill='%231d428a'/%3E%3Ccircle cx='20' cy='20' r='15' fill='%23c8102e'/%3E%3Cg fill='none' stroke='%23fff' stroke-width='2'%3E%3Cpath d='M5 20h30M20 5v30M9.4 9.4c4.4 4.4 4.4 16.8 0 21.2M30.6 9.4c-4.4 4.4-4.4 16.8 0 21.2'/%3E%3C/g%3E%3C/svg%3E">
<style>:root{color-scheme:light;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}img{max-width:100%}[hidden]{display:none!important}</style>
</head>
<body>
'@

$out = Join-Path $root $OutDir
New-Item -ItemType Directory -Force $out | Out-Null
[IO.File]::WriteAllText((Join-Path $out "index.html"), $head + $body + "`n</body>`n</html>`n", $utf8)
"Wrote $OutDir/index.html"

# Culture Seeker is a separate, self-contained page served at /culture-seeker/
$cs = Join-Path $root "culture-seeker/index.html"
if (Test-Path $cs) {
  $csOut = Join-Path $out "culture-seeker"
  New-Item -ItemType Directory -Force $csOut | Out-Null
  Copy-Item $cs (Join-Path $csOut "index.html") -Force
  "Wrote $OutDir/culture-seeker/index.html"
}
