# ============================================================================
#  Claude Desktop Session Sync - join the mesh (Syncthing)
#  Run on ANY new PC:
#    irm https://raw.githubusercontent.com/champdtm/claude-session-sync/main/setup-claude-sync.ps1 | iex
#  Safe + lossless. Backs sessions to Desktop first. No junctions, no OneDrive for this folder.
# ============================================================================
$ErrorActionPreference = "Stop"
$HUB_ID    = "GX6ZIOL-F5MTEX2-E4RFWKI-W4YXNLA-GQIN3X7-ISVGDBU-MXUBYWS-22OX2QR"  # hub PC (introducer)
$FOLDER_ID = "claude-code-sessions"
$p = "$env:APPDATA\Claude\claude-code-sessions"

Write-Host "`n=== Step 1: restore a REAL sessions folder (undo any junction) ===" -ForegroundColor Cyan
Copy-Item $p "$env:USERPROFILE\Desktop\claude-sessions-backup" -Recurse -Force -ErrorAction SilentlyContinue
if ((Get-Item $p -ErrorAction SilentlyContinue).Attributes -match 'ReparsePoint') { cmd /c rmdir $p | Out-Null }
New-Item -ItemType Directory -Force $p | Out-Null
$cnt = (Get-ChildItem $p -Recurse -Filter '*.json' -ErrorAction SilentlyContinue | Measure-Object).Count
Write-Host ("  Real folder = {0}; existing sessions here = {1}" -f (-not ((Get-Item $p).Attributes -match 'ReparsePoint')), $cnt)

Write-Host "`n=== Step 2: install + start Syncthing ===" -ForegroundColor Cyan
if (-not (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "syncthing.exe" -ErrorAction SilentlyContinue)) {
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
Write-Host "  THIS PC Device ID: $myID" -ForegroundColor Green

Write-Host "`n=== Step 3: add the HUB as an introducer + share the folder ===" -ForegroundColor Cyan
# introducer=true => the hub will auto-introduce all other PCs in the mesh to this one
$dev = @{deviceID=$HUB_ID; name="hub"; introducer=$true; autoAcceptFolders=$true} | ConvertTo-Json
try { Invoke-RestMethod "http://127.0.0.1:8384/rest/config/devices" -Method Post -Headers $hdr -Body $dev | Out-Null } catch {}
$f = @{ id=$FOLDER_ID; label="Claude Code Sessions"; path=$p; type="sendreceive"; fsWatcherEnabled=$true; fsWatcherDelayS=10; rescanIntervalS=3600;
        devices=@(@{deviceID=$myID}, @{deviceID=$HUB_ID}) } | ConvertTo-Json -Depth 6
Invoke-RestMethod "http://127.0.0.1:8384/rest/config/folders" -Method Post -Headers $hdr -Body $f | Out-Null
Write-Host "  Hub added as introducer; folder '$FOLDER_ID' shared."

Write-Host "`n=== Step 4: auto-start Syncthing at logon ===" -ForegroundColor Cyan
$action  = New-ScheduledTaskAction -Execute $exe -Argument "--home `"$env:LOCALAPPDATA\Syncthing`" --no-browser --no-restart"
$trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERNAME"
$set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName "Syncthing (Claude sessions)" -Action $action -Trigger $trigger -Settings $set -Force -RunLevel Limited | Out-Null
Write-Host "  Scheduled task registered."

Write-Host "`n============================================================" -ForegroundColor Yellow
Write-Host " DONE. Give the HUB PC this Device ID to accept you into the mesh:" -ForegroundColor Yellow
Write-Host "   $myID" -ForegroundColor Green
Write-Host " Once the hub accepts you once, it auto-introduces every other PC." -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
