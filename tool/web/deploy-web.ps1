<#
.SYNOPSIS
  Puts a NaviVibe web build live on this Windows machine (served by Caddy on
  127.0.0.1:8090, published by a Cloudflare Tunnel as https://subimusic.me).

.DESCRIPTION
  1. Gets a build: the newest GitHub release's navivibe-web-*.zip (default),
     a zip you name, or a local `flutter build web` (-Build).
  2. Unpacks it into <Root>\releases\<time> and checks it is a NaviVibe build.
  3. Switches atomically: writes <Root>\active.caddy (the live folder) and runs
     `caddy reload`, which swaps the whole config at once. Visitors get the new
     build on their next load, and open pages show "New version - Reload".
  4. Keeps the newest -Keep releases for rollback.
  Needs caddy.exe on PATH (winget install CaddyServer.Caddy). No admin rights.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\web\deploy-web.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\web\deploy-web.ps1 -Build
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\web\deploy-web.ps1 -Zip C:\Downloads\navivibe-web-1.0.0+130.zip
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tool\web\deploy-web.ps1 -Rollback
#>
[CmdletBinding()]
param(
  [switch]$Build,
  [string]$Zip,
  [string]$Tag,
  [switch]$Rollback,
  [switch]$Start,
  [string]$Root = (Join-Path $env:LOCALAPPDATA 'NaviVibeWeb'),
  [string]$Repo = 'Subicharan1018/flutter-_navi',
  [int]$Keep = 5
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $here '..\..')
$releases = Join-Path $Root 'releases'
$active = Join-Path $Root 'active.caddy'
$caddyfile = Join-Path $Root 'Caddyfile'
$required = 'index.html', 'flutter_bootstrap.js', 'sw.js', 'manifest.json', 'sqlite3.wasm', 'drift_worker.js'

New-Item -ItemType Directory -Force $releases | Out-Null

function Get-Caddy {
  $c = Get-Command caddy -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  return $null
}

function Test-CaddyRunning {
  try { Invoke-WebRequest -UseBasicParsing -TimeoutSec 3 'http://localhost:2019/config/' | Out-Null; return $true }
  catch { return $false }
}

function Set-Live([string]$dir) {
  # Caddy wants forward slashes and a quoted path.
  $path = ($dir -replace '\\', '/')
  Set-Content -Encoding ascii -Path $active -Value "root * `"$path`""
  Copy-Item -Force (Join-Path $here 'Caddyfile.windows') $caddyfile
  $caddy = Get-Caddy
  if (-not $caddy) {
    Write-Warning 'caddy.exe not found on PATH: install it (winget install CaddyServer.Caddy), then run with -Start.'
    return
  }
  if (Test-CaddyRunning) {
    & $caddy reload --config $caddyfile --adapter caddyfile
    if ($LASTEXITCODE -ne 0) { throw 'caddy reload failed; the previous build is still live' }
    Write-Host "   live (reloaded): $dir"
  } elseif ($Start) {
    Start-Process -WindowStyle Hidden -FilePath $caddy -ArgumentList @('run', '--config', "`"$caddyfile`"", '--adapter', 'caddyfile') -WorkingDirectory $Root
    Start-Sleep -Seconds 2
    Write-Host "   Caddy started; live: $dir"
  } else {
    Write-Host "   live folder set: $dir"
    Write-Host "   Caddy is not running. Start it with -Start, or see docs/web-deploy.md (start at logon)."
  }
}

if ($Rollback) {
  $all = @(Get-ChildItem -Directory $releases | Sort-Object Name -Descending)
  $current = if (Test-Path $active) { (Get-Content $active) -replace '^root \* "(.*)"$', '$1' -replace '/', '\' } else { '' }
  $idx = [Array]::FindIndex($all, [Predicate[object]] { param($d) $d.FullName -eq $current })
  if ($idx -lt 0 -or $idx + 1 -ge $all.Count) { throw 'no older release to roll back to' }
  Set-Live $all[$idx + 1].FullName
  return
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$dest = Join-Path $releases $stamp
$tmp = Join-Path ([IO.Path]::GetTempPath()) "navivibe-web-$stamp"
New-Item -ItemType Directory -Force $tmp | Out-Null
try {
  if ($Build) {
    Write-Host '== building (flutter build web --release --wasm --no-web-resources-cdn)'
    Push-Location $repoRoot
    try {
      flutter build web --release --wasm --no-web-resources-cdn
      if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed' }
    } finally { Pop-Location }
    $src = Join-Path $repoRoot 'build\web'
  } else {
    if (-not $Zip) {
      Write-Host "== downloading the web build from $Repo ($(if ($Tag) { $Tag } else { 'latest release' }))"
      $gh = Get-Command gh -ErrorAction SilentlyContinue
      if ($gh) {
        $ghArgs = @('release', 'download')
        if ($Tag) { $ghArgs += $Tag }
        $ghArgs += @('--repo', $Repo, '--pattern', 'navivibe-web-*.zip', '--dir', $tmp)
        & gh @ghArgs
        if ($LASTEXITCODE -ne 0) { throw 'gh release download failed (is there a web zip on that release?)' }
      } else {
        $api = if ($Tag) { "https://api.github.com/repos/$Repo/releases/tags/$([uri]::EscapeDataString($Tag))" } else { "https://api.github.com/repos/$Repo/releases/latest" }
        $rel = Invoke-RestMethod -Headers @{ 'User-Agent' = 'navivibe-deploy' } $api
        $asset = $rel.assets | Where-Object { $_.name -like 'navivibe-web-*.zip' } | Select-Object -First 1
        if (-not $asset) { throw "release $($rel.tag_name) has no navivibe-web-*.zip (web builds come from main)" }
        Invoke-WebRequest -UseBasicParsing -Headers @{ 'User-Agent' = 'navivibe-deploy' } $asset.browser_download_url -OutFile (Join-Path $tmp $asset.name)
      }
      $Zip = (Get-ChildItem $tmp -Filter 'navivibe-web-*.zip' | Select-Object -First 1).FullName
    }
    Write-Host "== unpacking $Zip"
    $unz = Join-Path $tmp 'unz'
    Expand-Archive -Path $Zip -DestinationPath $unz -Force
    $src = (Get-ChildItem -Recurse -Filter index.html $unz | Select-Object -First 1).DirectoryName
    if (-not $src) { throw 'no index.html in the zip' }
  }

  foreach ($f in $required) {
    if (-not (Test-Path (Join-Path $src $f))) { throw "$f missing: not a NaviVibe web build" }
  }
  Copy-Item -Recurse -Path $src -Destination $dest
  Get-ChildItem -Recurse -Path $dest -Filter '*.symbols' | Remove-Item -Force
  Write-Host "== new release: $dest"

  Set-Live $dest

  # Keep the newest $Keep (never the live one).
  Get-ChildItem -Directory $releases | Sort-Object Name -Descending | Select-Object -Skip $Keep |
    Where-Object { $_.FullName -ne $dest } | Remove-Item -Recurse -Force
} finally {
  Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

try {
  $code = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 'http://127.0.0.1:8090/').StatusCode
  Write-Host "   http://127.0.0.1:8090/ -> $code"
} catch { Write-Host '   http://127.0.0.1:8090/ not answering yet' }
Write-Host 'Roll back with -Rollback.'
