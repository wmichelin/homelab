# G5 LAN storage guide

Host: `wmichelin-G5-5000` · IP: `192.168.0.54` · **LAN only**

Ubuntu OS lives on **NVMe only** (`nvme0n1`) and was never wiped.

Credentials: `~/code/homelab/secrets/lan-samba-passwords.txt` (mode 600; also symlinked from `~/.config/`)

## Quick map

| Path / share | Purpose |
|--------------|---------|
| `/mnt/storage/safe` · SMB `safe` | SnapRAID-protected files (~5 TB pool) |
| `/mnt/storage/media` | Movies/music/TV on unprotected bulk |
| `/mnt/storage` · SMB `storage` | Glue tree (`safe` + `media` + `torrents` + `apps`) |
| `/mnt/tm/walter` · SMB `tm-walter` | Your Time Machine (4 TB HDD) |
| `/mnt/tm/marissa` · SMB `tm-marissa` | Marissa's Time Machine (2 TB Crucial SSD) |
| `/mnt/disks/parity1` | SnapRAID parity (~5 TB on Expansion) |

## Disk labels (stable — ignore `/dev/sdX` letters)

| Label | Serial / model | Role | SnapRAID data? |
|-------|----------------|------|----------------|
| `tm-walter` | Seagate Portable `NT3FAHPX` | Walter's TM | Yes |
| `tm-marissa` | Crucial `2337433E955F` | Marissa's TM | Yes |
| `disk-ssd1` | SanDisk Extreme `201426804192` | Protected pool | Yes |
| `disk-ssd2` | Extreme 55AE `3234…` | Protected pool | Yes |
| `disk-wd931` | WDC `WD-WCC6Y0HC973C` | Protected pool | Yes |
| `disk-hgst1` | HGST `170412JD10424B0ZZ65S` | Protected pool | Yes |
| `disk-hdd22` | Expansion `NT17ZN9E` remainder | Media/torrents bulk (~15 TiB) | **No** |
| `parity1` | Expansion first ~5 TiB | Parity only | — |
| OS NVMe | Kioxia `11VPC4TMQL52` | Ubuntu | — |

**Protected files (`safe`):** ~5 TB mergerfs of the four pool disks (SnapRAID).  
**Unprotected media:** `disk-hdd22` bind-mounted at `/mnt/storage/media` (+ `torrents`, `apps`).  
**SnapRAID total data members:** ~11 TB (four pool disks + both TM disks).  

## Mac: SnapRAID-protected files

Finder → Go → Connect to Server → `smb://192.168.0.54/safe`  
Or CLI: `mount_smbfs //wmichelin@192.168.0.54/safe ~/mnt/safe`

## Mac: general tree (includes media)

Finder → Go → Connect to Server → `smb://192.168.0.54/storage`  
User: `wmichelin` (password in `~/code/homelab/secrets/lan-samba-passwords.txt`)

## Mac: Time Machine

1. Connect once: `smb://192.168.0.54/tm-walter` (Walter) or `…/tm-marissa` (Marissa account).
2. System Settings → General → Time Machine → Add disk → pick the share.
3. After a backup, wait for nightly SnapRAID sync (03:30) or run: `sudo snapraid sync`

## Media apps (LAN browser)

| App | URL | Login |
|-----|-----|--------|
| Jellyfin | http://192.168.0.54:8096 | first-run wizard |
| Radarr | http://192.168.0.54:7878 | set auth in UI |
| Lidarr | http://192.168.0.54:8686 | set auth in UI |
| qBittorrent | http://192.168.0.54:8080 | `admin` + `QBITTORRENT_WEBUI_PASSWORD` in secrets |
| Prowlarr | http://192.168.0.54:9696 | indexer manager (synced to Radarr) |

Compose: `~/code/homelab/apps/media-stack/docker-compose.yml`  
Libraries: `/mnt/storage/media/movies`, `…/music`, `…/tv`  
Downloads:
- **Incomplete (scratch):** OS NVMe `/var/lib/qbittorrent/incomplete` → container `/downloads/incomplete`
- **Complete (seed + Radarr):** `disk-hdd22` `/mnt/disks/disk-hdd22/torrents/complete` → `/downloads/complete`  
  (Finish move is a cross-disk copy; Radarr hardlinks from `complete` → `media/movies` still work.)

### First-run checklist

**Done on server:** Jellyfin admin + Movies/Music/TV libraries; Radarr root `/movies` + qBittorrent; **Prowlarr** synced to Radarr with public indexers (YTS, TPB, Knaben, LimeTorrents).

**Your turn:**
1. Open **Jellyfin** → http://192.168.0.54:8096 — login `wmichelin` (password in secrets).
2. Open **Radarr** → http://192.168.0.54:7878 — add movies. Prefer quality profile **Ultra-HD** (or **Any (4K preferred)**). Upgrades stay on until Remux-2160p.
3. Open **Prowlarr** → http://192.168.0.54:9696 — add better indexers (see below).
4. **qBittorrent** → http://192.168.0.54:8080 — `admin` + password in secrets.
5. **Mac SMB / TM** — connect shares; reserve `192.168.0.54` on the router if needed.

### Indexers (Prowlarr)

Public ones need **no account** (already added). Better results usually need a **private tracker** invite or a **Usenet** provider:

| Type | How you get access |
|------|--------------------|
| Public torrent sites | Add in Prowlarr → Indexers → no login for many |
| Private trackers | Community invite / application (ratio rules); paste API/passkey into Prowlarr |
| Usenet | Pay a provider + an indexer (e.g. NZBGeek-style); add both in Prowlarr |

Do **not** publish tracker invites or API keys. Creds live in `~/code/homelab/secrets/lan-samba-passwords.txt`.

## Offsite config backup

Weekly timer uploads docs/scripts/secrets/compose configs to Google Drive folder **G5-networked-storage/** (Sundays ~06:30). Manual: `~/code/homelab/scripts/backup-to-gdrive.sh`. See `docs/backup-google-drive.md`.

## SnapRAID ops

```bash
sudo snapraid status
sudo snapraid sync          # after big TM or media adds
sudo snapraid scrub -p 100 -o 30
```

Timers: `snapraid-sync.timer` nightly 03:30 · `snapraid-scrub.timer` Sundays 05:00

Warning: with 6 data disks, SnapRAID recommends 2 parity levels; we run **1** (survives one disk loss).

## If a USB disk disconnects

- Mounts use UUID + `nofail` + automount — reconnect should remount.
- Then mergerfs may need: `sudo systemctl start g5-remount-mergerfs`
- Do not yank disks during TM backup or `snapraid sync`.

## Related docs

- RDP / remote desktop: `~/.config/lan-remote-access.md`
- Follow-ups: `~/.config/lan-unraid-like-followups.md`
- Plan: `~/.cursor/plans/mergerfs SnapRAID storage-57f49d67.plan.md`
