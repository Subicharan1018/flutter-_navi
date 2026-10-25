<#
  Local dry run of what .github/workflows/release.yml does. Nothing is uploaded,
  pushed or published: everything lands in build\release_local\.

  .\tool\make_release_local.ps1                       # build APKs, manifest, checksums
  .\tool\make_release_local.ps1 -PrevDir <dir>        # also cut patches from earlier builds
  .\tool\make_release_local.ps1 -Windows              # also zip the Windows build (+ Velopack if vpk is installed)

  -PrevDir is a folder of <build>\NaviVibe-<abi>.apk, e.g. earlier runs of this script
  (each run leaves its APKs in build\release_local\archive\<build>\).

  Signing: android\key.properties (git-ignored) if present, else the debug key.
  See docs\RELEASING.md for how to point it at your existing debug keystore.
#>
param(
  [int]$Build = 0,
  [string]$PrevDir = '',
  [switch]$Windows,
  [switch]$Public   # build like the GitHub release does: --dart-define=PUBLIC_BUILD=true (no online downloads)
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)

$full = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$name = $full.Split('+')[0]
if ($Build -le 0) { $Build = [int](Get-Date -UFormat %s) % 100000000 }  # monotonic enough for a dry run
$tag = "v$name+$Build"
Write-Host "Dry run for $tag" -ForegroundColor Cyan

$root = 'build\release_local'
$dist = "$root\dist"
$out = "$root\out"
Remove-Item $dist, $out -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $dist, $out | Out-Null

$flags = @('--release', "--build-name=$name", "--build-number=$Build", "--dart-define=NAVI_BUILD=$Build")
if ($Public) { $flags += '--dart-define=PUBLIC_BUILD=true' }
flutter build apk @flags --split-per-abi
if ($LASTEXITCODE) { throw 'split build failed' }
foreach ($abi in 'arm64-v8a', 'armeabi-v7a', 'x86_64') {
  Copy-Item "build\app\outputs\flutter-apk\app-$abi-release.apk" "$dist\NaviVibe-$abi.apk"
}
flutter build apk @flags
if ($LASTEXITCODE) { throw 'universal build failed' }
Copy-Item 'build\app\outputs\flutter-apk\app-release.apk' "$dist\NaviVibe-universal.apk"

python tool/release/verify_apk.py "$dist\NaviVibe-arm64-v8a.apk" "$dist\NaviVibe-armeabi-v7a.apk" "$dist\NaviVibe-x86_64.apk"
if ($LASTEXITCODE) { throw 'native libs are compressed' }

$winArgs = @()
if ($Windows) {
  flutter build windows --release "--build-name=$name" "--build-number=$Build" "--dart-define=NAVI_BUILD=$Build" $(if ($Public) { '--dart-define=PUBLIC_BUILD=true' })
  if ($LASTEXITCODE) { throw 'windows build failed' }
  $win = "$root\windows"
  Remove-Item $win -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $win | Out-Null
  $rel = 'build\windows\x64\runner\Release'
  Compress-Archive -Path "$rel\*" -DestinationPath "$win\NaviVibe-windows-x64.zip"
  if (Get-Command vpk -ErrorAction SilentlyContinue) {
    $parts = $name.Split('.')
    vpk pack --packId NaviVibe --packVersion "$($parts[0]).$($parts[1]).$Build" --packDir $rel --mainExe navivibe.exe --packTitle NaviVibe -o "$root\velopack"
    Copy-Item "$root\velopack\*" $win -Include *.nupkg, *Setup.exe, releases.*.json
  } else {
    Write-Warning 'vpk not found (dotnet tool install -g vpk): skipping the Velopack installer.'
  }
  $winArgs = @('--windows-dir', $win)
}

$prev = @()
if ($PrevDir) { $prev = @('--prev-dir', $PrevDir) }
"- Local dry run" | Set-Content "$root\notes.md" -Encoding utf8
python tool/release/package_release.py --apk-dir $dist @prev --out $out --version $name --build $Build --tag $tag --notes-file "$root\notes.md" @winArgs
if ($LASTEXITCODE) { throw 'packaging failed' }

# Keep these APKs so the next run can cut patches against them.
$arch = "$root\archive\$Build"
New-Item -ItemType Directory -Force $arch | Out-Null
Copy-Item "$dist\NaviVibe-*-*.apk" $arch

Write-Host "`nSizes" -ForegroundColor Cyan
Get-ChildItem $dist, $out -File | Where-Object { $_.Extension -in '.apk', '.patch' } |
  Sort-Object Name | ForEach-Object { '{0,-44} {1,8:N2} MB' -f $_.Name, ($_.Length / 1MB) }
Write-Host "`nOutput: $out (latest.json, SHA256SUMS.txt, patches) and $dist (APKs)." -ForegroundColor Green
