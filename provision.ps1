# ============================================================================
#  Provision a NEW Windows PC for Claude Code: skills + sessions, one command.
#    irm https://raw.githubusercontent.com/champdtm/claude-session-sync/main/provision.ps1 | iex
#
#  - Skills/settings/memory  -> OneDrive junction (~/.claude -> OneDrive\.claude)
#  - Desktop sessions        -> Syncthing mesh (folder 'claude-code-sessions')
#  Safe + lossless: backs up any existing ~/.claude and sessions first.
#
#  PREREQUISITE (manual, one time on the new PC):
#    1. Install OneDrive, sign in as champ_dtm@hotmail.com
#    2. Let it finish syncing so C:\Users\<you>\OneDrive\.claude exists locally
#  Then run this script. It does everything else.
# ============================================================================
$ErrorActionPreference = "Stop"
$HUB_ID    = "GX6ZIOL-F5MTEX2-E4RFWKI-W4YXNLA-GQIN3X7-ISVGDBU-MXUBYWS-22OX2QR"
$FOLDER_ID = "claude-code-sessions"
$stamp     = Get-Date -Format "yyyyMMdd-HHmmss"

# ---------------------------------------------------------------------------
Write-Host "`n########## PART A: SKILLS via OneDrive junction ##########" -ForegroundColor Magenta
$od = if ($env:OneDrive) { $env:OneDrive } elseif ($env:OneDriveConsumer) { $env:OneDriveConsumer } else { "$env:USERPROFILE\OneDrive" }
$odClaude = Join-Path $od ".claude"
$localClaude = "$env:USERPROFILE\.claude"

if (-not (Test-Path $odClaude)) {
  Write-Host "  SKIPPING skills sync: '$odClaude' not found." -ForegroundColor Yellow
  Write-Host "  -> Install OneDrive, sign in as champ_dtm@hotmail.com, let it sync, then re-run." -ForegroundColor Yellow
} elseif ((Get-Item $localClaude -ErrorAction SilentlyContinue).Target -eq $odClaude) {
  Write-Host "  Already a junction to OneDrive. Skills already synced." -ForegroundColor Green
} else {
  if (Test-Path $localClaude) {
    $bak = "$env:USERPROFILE\.claude-backup-$stamp"
    Write-Host "  Backing up existing ~/.claude -> $bak"
    Move-Item $localClaude $bak -Force
  }
  cmd /c mklink /J "$localClaude" "$odClaude" | Out-Null
  $ok = (Get-Item $localClaude).Target -eq $odClaude
  Write-Host "  Junction created: $ok  (skills: $((Get-ChildItem "$localClaude\skills" -Directory -ErrorAction SilentlyContinue|Measure-Object).Count))" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
Write-Host "`n########## PART B: SESSIONS via Syncthing ##########" -ForegroundColor Magenta
$p = "$env:APPDATA\Claude\claude-code-sessions"
Copy-Item $p "$env:USERPROFILE\Desktop\claude-sessions-backup" -Recurse -Force -ErrorAction SilentlyContinue
if ((Get-Item $p -ErrorAction SilentlyContinue).Attributes -match 'ReparsePoint') { cmd /c rmdir $p | Out-Null }
New-Item -ItemType Directory -Force $p | Out-Null
Write-Host "  Sessions folder ready (real folder)."

if (-not (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "syncthing.exe" -ErrorAction SilentlyContinue)) {
  Write-Host "  Installing Syncthing..."
  winget install --id Syncthing.Syncthing --accept-source-agreements --accept-package-agreements --silent
}
$exe = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "syncthing.exe" | Select-Object -First 1).FullName
& $exe generate --home "$env:LOCALAPPDATA\Syncthing" | Out-Null
if (-not (Get-Process syncthing -ErrorAction SilentlyContinue)) {
  Start-Process $exe -ArgumentList '--home',"$env:LOCALAPPDATA\Syncthing",'--no-browser','--no-restart' -WindowStyle Hidden
}
Start-Sleep 6
$api  = ([xml](Get-Content "$env:LOCALAPPDATA\Syncthing\config.xml")).configuration.gui.apikey
$hdr  = @{'X-API-Key'=$api; 'Content-Type'='application/json'}
$myID = (Invoke-RestMethod "http://127.0.0.1:8384/rest/system/status" -Headers @{'X-API-Key'=$api}).myID

$dev = @{deviceID=$HUB_ID; name="hub"; introducer=$true; autoAcceptFolders=$true} | ConvertTo-Json
try { Invoke-RestMethod "http://127.0.0.1:8384/rest/config/devices" -Method Post -Headers $hdr -Body $dev | Out-Null } catch {}
$f = @{ id=$FOLDER_ID; label="Claude Code Sessions"; path=$p; type="sendreceive"; fsWatcherEnabled=$true; fsWatcherDelayS=10; rescanIntervalS=3600;
        devices=@(@{deviceID=$myID}, @{deviceID=$HUB_ID}) } | ConvertTo-Json -Depth 6
Invoke-RestMethod "http://127.0.0.1:8384/rest/config/folders" -Method Post -Headers $hdr -Body $f | Out-Null
Write-Host "  Hub added as introducer; folder shared." -ForegroundColor Green

$action  = New-ScheduledTaskAction -Execute $exe -Argument "--home `"$env:LOCALAPPDATA\Syncthing`" --no-browser --no-restart"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERNAME"
$set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName "Syncthing (Claude sessions)" -Action $action -Trigger $trigger -Settings $set -Force -RunLevel Limited | Out-Null
Write-Host "  Syncthing auto-start at logon registered." -ForegroundColor Green

# ---------------------------------------------------------------------------
Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host " DONE. Final step to join the session mesh:" -ForegroundColor Yellow
Write-Host "   Send this Device ID to the HUB PC and accept it there once:" -ForegroundColor Yellow
Write-Host "   $myID" -ForegroundColor Green
Write-Host " The hub then auto-introduces every other PC to this one." -ForegroundColor Yellow
Write-Host " Restart the Claude Desktop app so it picks up synced sessions + skills." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
