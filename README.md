# claude-session-sync

Sync the **Claude Desktop app's** Claude Code sessions across multiple Windows PCs using [Syncthing](https://syncthing.net/).

Sessions live in `%APPDATA%\Claude\claude-code-sessions`. This repo sets up a Syncthing mesh so every PC holds the same sessions, syncing automatically in the background.

## Provision a brand-new PC (skills + sessions, one command)

**Prerequisite (one time, manual):** install OneDrive on the new PC, sign in as `champ_dtm@hotmail.com`, and let it sync until `C:\Users\<you>\OneDrive\.claude` exists locally.

Then, in PowerShell:

```powershell
irm https://raw.githubusercontent.com/champdtm/claude-session-sync/main/provision.ps1 | iex
```

This does **both**:
- **Skills/settings/memory** — junctions `~/.claude` to `OneDrive\.claude` (backs up any existing local `~/.claude` first).
- **Sessions** — restores the sessions folder, installs + starts Syncthing, adds the hub as an introducer, shares the folder, and auto-starts at logon.

It prints the new PC's **Device ID**. Restart the Claude Desktop app afterward.

### Sessions only (skills already set up)

```powershell
irm https://raw.githubusercontent.com/champdtm/claude-session-sync/main/setup-claude-sync.ps1 | iex
```

## Finish pairing

Give the printed Device ID to the **hub PC** and accept it there once. Because the hub is an *introducer*, it then auto-introduces every other PC in the mesh to the new one. No need to pair every pair by hand.

- **Hub PC Device ID:** `GX6ZIOL-F5MTEX2-E4RFWKI-W4YXNLA-GQIN3X7-ISVGDBU-MXUBYWS-22OX2QR`
- **Folder ID (must match everywhere):** `claude-code-sessions`

## Files

- `setup-claude-sync.ps1` — the bootstrap/join script.
- `SKILL.md` — a Claude Code skill with the full procedure, verification, and troubleshooting. Drop it in `~/.claude/skills/claude-session-sync/` and invoke `/claude-session-sync`.

## Rules / gotchas

- Do **not** use OneDrive or junctions for this folder — OneDrive refuses to sync reparse points (red X).
- Do **not** run the *same* session live on two PCs at once, or Syncthing makes `.sync-conflict` copies. Different sessions in parallel is fine.
- Mesh uses Syncthing global discovery + relays, so no router/port-forwarding setup is needed. Direct connection is used when available (e.g. Tailscale/LAN).
