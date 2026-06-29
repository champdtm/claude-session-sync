---
name: claude-session-sync
description: Sync Claude Desktop-app Claude Code sessions across two of Krit's Windows PCs using Syncthing. Use when setting up, pairing, repairing, or verifying cross-machine session sync, or when the user mentions sessions not showing up on the other PC, a OneDrive red X / conflict on claude-code-sessions, or "the other Claude/bot".
---

# Claude Desktop Session Sync (Syncthing)

Sync the **Claude Desktop app's** Claude Code sessions between Krit's two Windows PCs.

## Critical facts (read first)

- Desktop-app sessions live in `%APPDATA%\Claude\claude-code-sessions` (`.json`, layout `account-id\project-id\local_*.json`). This is the target. It is DIFFERENT from the CLI store `~/.claude/projects` (`.jsonl`).
- **Do NOT use OneDrive or junctions for this folder.** `%APPDATA%` is outside OneDrive, so OneDrive needs a junction, and OneDrive refuses to sync junctions/reparse points (shows a red circle/X). This was tried and abandoned.
- **Do NOT use claude-sync** (the npm tool) — it only syncs `~/.claude/projects`, not the Desktop store.
- The folder on every PC must be a **real folder**, never a junction.
- Syncthing folder ID must be exactly `claude-code-sessions` on both PCs or they won't pair.
- Caveat to tell the user: don't run the *same* session live on both PCs at once, or Syncthing creates `.sync-conflict` files.

## Shell

Windows PowerShell. GUI/API is at `http://127.0.0.1:8384`; API key lives in `%LOCALAPPDATA%\Syncthing\config.xml`.

## Procedure

Each PC does steps 1-4. Pairing (step 5) needs both PCs' Device IDs, exchanged via the handoff file at `OneDrive\.claude\SYNCTHING-HANDOFF.txt` (it syncs through the existing `~/.claude` OneDrive junction).

### Step 1 — Restore a real folder (undo any old junction), keep all sessions

```powershell
$p = "$env:APPDATA\Claude\claude-code-sessions"
# Safety backup first
Copy-Item $p "$env:USERPROFILE\Desktop\claude-sessions-backup" -Recurse -Force -ErrorAction SilentlyContinue
if ((Get-Item $p -ErrorAction SilentlyContinue).Attributes -match 'ReparsePoint') { cmd /c rmdir $p }
New-Item -ItemType Directory -Force $p | Out-Null
# Pull sessions back from a leftover OneDrive copy if one exists
if (Test-Path "$env:OneDrive\claude-code-sessions") { Copy-Item "$env:OneDrive\claude-code-sessions\*" $p -Recurse -Force -ErrorAction SilentlyContinue }
Write-Output "Real folder: $(-not ((Get-Item $p).Attributes -match 'ReparsePoint'))  Sessions: $((Get-ChildItem $p -Recurse -Filter '*.json' -ErrorAction SilentlyContinue|Measure-Object).Count)"
```
Then delete leftovers: `Remove-Item "$env:OneDrive\claude-code-sessions" -Recurse -Force -EA SilentlyContinue; Remove-Item "$env:OneDrive\fix-claude-sessions.ps1" -Force -EA SilentlyContinue`

### Step 2 — Install Syncthing, init, start

```powershell
winget install --id Syncthing.Syncthing --accept-source-agreements --accept-package-agreements --silent
$exe = (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter "syncthing.exe" | Select -First 1).FullName
& $exe generate --home "$env:LOCALAPPDATA\Syncthing"
Start-Process $exe -ArgumentList '--home',"$env:LOCALAPPDATA\Syncthing",'--no-browser','--no-restart' -WindowStyle Hidden
Start-Sleep 5
$api = ([xml](Get-Content "$env:LOCALAPPDATA\Syncthing\config.xml")).configuration.gui.apikey
$myID = (Invoke-RestMethod "http://127.0.0.1:8384/rest/system/status" -Headers @{'X-API-Key'=$api}).myID
Write-Output "THIS PC Device ID: $myID"
```

### Step 3 — Add the shared folder (this PC only, for now)

```powershell
$hdr=@{'X-API-Key'=$api;'Content-Type'='application/json'}
$f=@{id="claude-code-sessions";label="Claude Code Sessions";path="$env:APPDATA\Claude\claude-code-sessions";type="sendreceive";fsWatcherEnabled=$true;fsWatcherDelayS=10;rescanIntervalS=3600;devices=@(@{deviceID=$myID})}|ConvertTo-Json -Depth 6
Invoke-RestMethod "http://127.0.0.1:8384/rest/config/folders" -Method Post -Headers $hdr -Body $f
```

### Step 4 — Auto-start at logon

```powershell
$action=New-ScheduledTaskAction -Execute $exe -Argument "--home `"$env:LOCALAPPDATA\Syncthing`" --no-browser --no-restart"
$trigger=New-ScheduledTaskTrigger -AtLogOn -User "$env:USERNAME"
$set=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName "Syncthing (Claude sessions)" -Action $action -Trigger $trigger -Settings $set -Force -RunLevel Limited
```
Note: PowerShell `$HOME`/`$home` is read-only — never use that variable name for the home path; use `$env:LOCALAPPDATA\Syncthing` inline as above.

### Step 5 — Pair the two PCs (run on BOTH, with the OTHER PC's ID)

Write your own ID to the handoff file so the peer can read it; read the peer's ID from the same file once it has synced:
```powershell
# publish my ID
"DeviceID=$myID at $(Get-Date -f s) on $env:COMPUTERNAME" | Out-File "$env:OneDrive\.claude\SYNCTHING-HANDOFF-$env:COMPUTERNAME.txt"
```
Then, with `$peerID` = the other PC's Device ID, add the peer device and share the folder with it:
```powershell
$hdr=@{'X-API-Key'=$api;'Content-Type'='application/json'}
$dev=@{deviceID=$peerID;name="PeerPC"}|ConvertTo-Json
Invoke-RestMethod "http://127.0.0.1:8384/rest/config/devices" -Method Post -Headers $hdr -Body $dev
$f=@{id="claude-code-sessions";label="Claude Code Sessions";path="$env:APPDATA\Claude\claude-code-sessions";type="sendreceive";fsWatcherEnabled=$true;devices=@(@{deviceID=$myID},@{deviceID=$peerID})}|ConvertTo-Json -Depth 6
Invoke-RestMethod "http://127.0.0.1:8384/rest/config/folders" -Method Post -Headers $hdr -Body $f
```
Both PCs must list the other's Device ID under the folder. First connection can take a minute (uses global discovery + relays — both on by default, so no port-forwarding needed).

## Verify it's working

```powershell
$api = ([xml](Get-Content "$env:LOCALAPPDATA\Syncthing\config.xml")).configuration.gui.apikey
$h=@{'X-API-Key'=$api}
Invoke-RestMethod "http://127.0.0.1:8384/rest/system/connections" -Headers $h | % {$_.connections.PSObject.Properties | ? {$_.Value.connected} | % {$_.Name}}  # connected peers
(Invoke-RestMethod "http://127.0.0.1:8384/rest/db/status?folder=claude-code-sessions" -Headers $h) | Select state,localFiles,globalFiles,needFiles
```
Healthy = the peer Device ID shows connected, and `globalFiles` matches across both PCs with `needFiles` dropping to 0.

## Troubleshooting

- **Peer never connects:** confirm both have the folder ID `claude-code-sessions` and each other's Device ID; check `globalAnnounceEnabled` and `relaysEnabled` are true in `/rest/config/options`.
- **Red X / won't sync (legacy):** the folder is still a junction — redo Step 1 to make it a real folder.
- **`.sync-conflict` files:** the same session was edited live on both PCs. Keep the newer one; it's safe to delete the conflict copy.
- Data is never lost by removing a *junction* (it's only a pointer); real sessions also remain in the Desktop backup from Step 1.

## Related memory

See `[[claude-desktop-session-sync]]` and `[[onedrive-sync-setup]]`.
