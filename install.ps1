# PowerShell installation script for NaviVibe on Windows
param (
    [switch]$SkipBuild,
    [switch]$Launch
)

$ErrorActionPreference = "Stop"

# Ensure we are in the project root directory
$ProjectRoot = $PSScriptRoot
Set-Location $ProjectRoot

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "        NaviVibe Windows Installer            " -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

$ReleaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
$ExePathInRelease = Join-Path $ReleaseDir "navivibe.exe"

# Step 1: Build if needed
if (-not $SkipBuild -or -not (Test-Path $ExePathInRelease)) {
    Write-Host "`n=== [1/5] Building NaviVibe for Windows (Release) ===" -ForegroundColor Yellow
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter build failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
} else {
    Write-Host "`n=== [1/5] Skipping build (using existing release artifacts) ===" -ForegroundColor Yellow
}

if (-not (Test-Path $ExePathInRelease)) {
    Write-Error "Release executable not found at $ExePathInRelease"
    exit 1
}

# Step 2: Prepare Destination Directory
$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\NaviVibe"
Write-Host "`n=== [2/5] Installing to $InstallDir ===" -ForegroundColor Yellow

# Stop any running instances of navivibe before overwriting
$runningProcesses = Get-Process -Name "navivibe" -ErrorAction SilentlyContinue
if ($runningProcesses) {
    Write-Host "Stopping running NaviVibe instance(s)..." -ForegroundColor Yellow
    $runningProcesses | Stop-Process -Force
    Start-Sleep -Seconds 1
}

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# Copy release artifacts
Copy-Item -Path "$ReleaseDir\*" -Destination $InstallDir -Recurse -Force
$InstalledExe = Join-Path $InstallDir "navivibe.exe"

# Copy Icon if available
$IconSrc = Join-Path $ProjectRoot "windows\runner\resources\app_icon.ico"
$IconDest = Join-Path $InstallDir "app_icon.ico"
if (Test-Path $IconSrc) {
    Copy-Item -Path $IconSrc -Destination $IconDest -Force
}

# Step 3: Create Shortcuts
Write-Host "`n=== [3/5] Creating Desktop & Start Menu Shortcuts ===" -ForegroundColor Yellow
$WshShell = New-Object -ComObject WScript.Shell

# Desktop Shortcut
$DesktopFolder = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
$DesktopShortcutPath = Join-Path $DesktopFolder "NaviVibe.lnk"
$DesktopShortcut = $WshShell.CreateShortcut($DesktopShortcutPath)
$DesktopShortcut.TargetPath = $InstalledExe
$DesktopShortcut.WorkingDirectory = $InstallDir
$DesktopShortcut.Description = "NaviVibe Music Player"
if (Test-Path $IconDest) {
    $DesktopShortcut.IconLocation = "$IconDest,0"
}
$DesktopShortcut.Save()

# Start Menu Shortcut
$StartMenuPrograms = [Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)
$StartMenuShortcutPath = Join-Path $StartMenuPrograms "NaviVibe.lnk"
$StartMenuShortcut = $WshShell.CreateShortcut($StartMenuShortcutPath)
$StartMenuShortcut.TargetPath = $InstalledExe
$StartMenuShortcut.WorkingDirectory = $InstallDir
$StartMenuShortcut.Description = "NaviVibe Music Player"
if (Test-Path $IconDest) {
    $StartMenuShortcut.IconLocation = "$IconDest,0"
}
$StartMenuShortcut.Save()

# Step 4: Add to User PATH
Write-Host "`n=== [4/5] Configuring Environment PATH ===" -ForegroundColor Yellow
$UserPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
if ($UserPath -notlike "*$InstallDir*") {
    $NewUserPath = "$UserPath;$InstallDir"
    [Environment]::SetEnvironmentVariable("Path", $NewUserPath, [EnvironmentVariableTarget]::User)
    $env:Path = "$env:Path;$InstallDir"
    Write-Host "Added NaviVibe to User PATH." -ForegroundColor Green
} else {
    Write-Host "NaviVibe is already in User PATH." -ForegroundColor DarkGray
}

# Step 5: Register Uninstaller and Windows App Entry
Write-Host "`n=== [5/5] Registering Application in Windows ===" -ForegroundColor Yellow

# Create uninstaller script
$UninstallerScript = @"
`$ErrorActionPreference = "SilentlyContinue"
Write-Host "Uninstalling NaviVibe..." -ForegroundColor Yellow

# Kill running processes
Get-Process -Name "navivibe" | Stop-Process -Force

# Remove Shortcuts
`$DesktopShortcut = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)) "NaviVibe.lnk"
if (Test-Path `$DesktopShortcut) { Remove-Item -Force `$DesktopShortcut }

`$StartMenuShortcut = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Programs)) "NaviVibe.lnk"
if (Test-Path `$StartMenuShortcut) { Remove-Item -Force `$StartMenuShortcut }

# Remove Registry
Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\NaviVibe" -Recurse -Force

# Remove from User PATH
`$InstallDir = "$InstallDir"
`$UserPath = [Environment]::GetEnvironmentVariable("Path", [EnvironmentVariableTarget]::User)
if (`$UserPath -like "*`$InstallDir*") {
    `$Parts = `$UserPath -split ';' | Where-Object { `$_ -ne `$InstallDir -and `$_ -ne "" }
    `$NewUserPath = `$Parts -join ';'
    [Environment]::SetEnvironmentVariable("Path", `$NewUserPath, [EnvironmentVariableTarget]::User)
}

# Delete Install Directory
Start-Process -FilePath "cmd.exe" -ArgumentList "/c timeout /t 2 /nobreak & rmdir /s /q `"$InstallDir`"" -WindowStyle Hidden
Write-Host "NaviVibe uninstalled successfully." -ForegroundColor Green
"@
Set-Content -Path (Join-Path $InstallDir "uninstall.ps1") -Value $UninstallerScript -Encoding UTF8

# Register in HKCU Uninstall
$UninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\NaviVibe"
if (-not (Test-Path $UninstallKey)) {
    New-Item -Path $UninstallKey -Force | Out-Null
}

$PubspecPath = Join-Path $ProjectRoot "pubspec.yaml"
$Version = "1.0.0"
if (Test-Path $PubspecPath) {
    $VersionMatch = Select-String -Path $PubspecPath -Pattern "^version:\s*([^\s\+]+)"
    if ($VersionMatch) {
        $Version = $VersionMatch.Matches[0].Groups[1].Value
    }
}

Set-ItemProperty -Path $UninstallKey -Name "DisplayName" -Value "NaviVibe"
Set-ItemProperty -Path $UninstallKey -Name "DisplayVersion" -Value $Version
Set-ItemProperty -Path $UninstallKey -Name "Publisher" -Value "NaviVibe"
Set-ItemProperty -Path $UninstallKey -Name "InstallLocation" -Value $InstallDir
Set-ItemProperty -Path $UninstallKey -Name "DisplayIcon" -Value "$InstalledExe,0"
Set-ItemProperty -Path $UninstallKey -Name "UninstallString" -Value "powershell.exe -ExecutionPolicy Bypass -File `"$InstallDir\uninstall.ps1`""
Set-ItemProperty -Path $UninstallKey -Name "NoModify" -Value 1 -Type DWord
Set-ItemProperty -Path $UninstallKey -Name "NoRepair" -Value 1 -Type DWord

Write-Host "`n==============================================" -ForegroundColor Green
Write-Host "     Installation Completed Successfully!      " -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host "Installed Location: $InstallDir"
Write-Host "Desktop Shortcut:   $DesktopShortcutPath"
Write-Host "Start Menu:         $StartMenuShortcutPath"
Write-Host "`nYou can launch NaviVibe by typing 'navivibe' or from your Start Menu/Desktop."

if ($Launch) {
    Write-Host "`nLaunching NaviVibe..." -ForegroundColor Cyan
    Start-Process -FilePath $InstalledExe -WorkingDirectory $InstallDir
}
