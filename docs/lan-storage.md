# G5 LAN storage guide

Host: `wmichelin-G5-5000` · IP: `192.168.0.54` · **LAN only**

Ubuntu OS lives on **NVMe only** (`nvme0n1`) and was never wiped.

Credentials: `~/code/homelab/secrets/homelab.env` (mode 600; keys `SMB_*`, `JELLYFIN_*`, `RADARR_*`, …)

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
User: `wmichelin` (password in `~/code/homelab/secrets/homelab.env` → `SMB_PASS_WALTER`)

## Mac: Time Machine

1. Connect once: `smb://192.168.0.54/tm-walter` (Walter) or `…/tm-marissa` (Marissa account).
2. System Settings → General → Time Machine → Add disk → pick the share.
3. After a backup, wait for nightly SnapRAID sync (03:30) or run: `sudo snapraid sync`

## Media apps (LAN browser)

Prefer **`*.g5.internal`** on the home LAN (Flint DNS + Caddy — `docs/headscale-tailscale.md`). Use **`*.g5.lan`** over Tailscale. Port URLs still work.

| App | LAN | Tailscale | Direct |
|-----|-----|-----------|--------|
| Hub | https://g5.internal | https://g5.lan | — |
| Jellyfin | https://jellyfin.g5.internal | https://jellyfin.g5.lan | http://192.168.0.54:8096 |
| Tunarr | https://tunarr.g5.internal | https://tunarr.g5.lan | http://192.168.0.54:8000 |
| Radarr | https://radarr.g5.internal | https://radarr.g5.lan | http://192.168.0.54:7878 |
| Sonarr | https://sonarr.g5.internal | https://sonarr.g5.lan | http://192.168.0.54:8989 |
| Lidarr | https://lidarr.g5.internal | https://lidarr.g5.lan | http://192.168.0.54:8686 |
| qBittorrent | https://qbittorrent.g5.internal | https://qbittorrent.g5.lan | http://192.168.0.54:8080 (`admin` + secrets); host net, BT bound to `proton0` — *arr download client host: `host.docker.internal` |
| NZBGet | https://nzbget.g5.internal | https://nzbget.g5.lan | http://192.168.0.54:6789 (`NZBGET_*` in secrets); Usenet via Eweka SSL — not Proton |
| Prowlarr | https://prowlarr.g5.internal | https://prowlarr.g5.lan | http://192.168.0.54:9696 |
| Seerr | https://seerr.g5.internal | https://seerr.g5.lan | http://192.168.0.54:5055 |
| Immich | https://immich.g5.internal | https://immich.g5.lan | http://192.168.0.54:2283 |
| OpenCode | https://opencode.g5.internal | https://opencode.g5.lan | http://192.168.0.54:4096 (no basic auth; Tailscale or LAN HTTPS) |

Torrent egress uses **Proton VPN** on the host — see [`docs/proton-vpn-g5.md`](proton-vpn-g5.md). If indexers die with SSL errors but Prowlarr’s UI is up, run `./scripts/proton-vpn-fix.sh recover` on G5.

Compose: `~/code/homelab/apps/media-stack/docker-compose.yml`  
Libraries: `/mnt/storage/media/movies`, `…/music`, `…/tv`  
Downloads:
- **Incomplete + complete:** `disk-hdd22` `/mnt/disks/disk-hdd22/torrents/{incomplete,complete}` → `/downloads/{incomplete,complete}` (same disk so finish is a rename; keeps the OS NVMe from filling up). Radarr/Sonarr/Lidarr hardlink from `complete` → `media/...`.
- **Usenet (NZBGet):** `/mnt/disks/disk-hdd22/usenet/{incomplete,complete}` → `/downloads/{incomplete,complete}`. Direct SSL to Eweka (`news.eweka.nl:563`) — not via Proton. NewsLazer (Mac) is a separate desktop client; it does not feed NZBGet. Upload NZBs in the NZBGet WebUI (or add a Newznab indexer later). *arr remote path map: `/downloads/` → `/data/usenet/`.
- **Max active downloads:** capped at **2** in qBittorrent (large UHD remuxes).

### Tunarr (virtual Live TV)

[Tunarr](https://tunarr.com) runs as `tunarr` in the media-stack (`chrisbenincasa/tunarr:latest`, port **8000**). Config: `apps/media-stack/config/tunarr/`. UI: https://tunarr.g5.internal (or https://tunarr.g5.lan)

Prefer **HDHomeRun** in Jellyfin (more stable than M3U at program boundaries). From inside the compose network:

| Setting | Value |
|---------|--------|
| HDHR tuner | `http://tunarr:8000` |
| XMLTV guide | `http://tunarr:8000/api/xmltv.xml` |

LAN equivalents: `http://192.168.0.54:8000` and `…/api/xmltv.xml`. Connect Jellyfin as a media source in Tunarr, create channels, then Live TV **Refresh Channels / Refresh Guide**. NVIDIA GPU (`gpus: all`) is used for CUDA/NVENC; `/dev/dri` is also passed through.

**Seinfeld 24/7** is channel **53** (group `TV`) — all 171 episodes, shuffled, loops continuously.

**Sitcoms Shuffle** is channel **54** (group `TV`) — equal-weight mix of Seinfeld, Friends, and The Office (US), shuffled within each show. Re-seed: `python3 scripts/tunarr-seed-sitcoms-shuffle.py` on G5, then Jellyfin Live TV → Refresh Channels / Guide.

**GPU health:** Docker GPU attach can go stale (`CUDA_ERROR_NO_DEVICE` inside the container while the host GPU is fine). Tunarr has a compose `healthcheck` (`nvidia-smi`); `autoheal` (`willfarrell/autoheal`) restarts labeled unhealthy containers so the GPU rebinds.

### First-run checklist

**Done on server:** Jellyfin admin + Movies/Music/TV libraries; Radarr root `/movies` + qBittorrent; **Prowlarr** synced to Radarr with public indexers (YTS, TPB, Knaben, LimeTorrents).

**Your turn:**
1. Open **Jellyfin** → http://192.168.0.54:8096 — login `wmichelin` (password in secrets).
2. Open **Radarr** → http://192.168.0.54:7878 — add movies. Prefer quality profile **4K WEB preferred (1080 OK)** (grabs 1080 if needed, upgrades to WEB 2160p).
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

Do **not** publish tracker invites or API keys. Creds live in `~/code/homelab/secrets/homelab.env`.

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

- RDP / remote desktop: [`docs/lan-remote-access.md`](lan-remote-access.md)
- Proton VPN / torrent egress: [`docs/proton-vpn-g5.md`](proton-vpn-g5.md)
- Follow-ups: [`docs/lan-unraid-like-followups.md`](lan-unraid-like-followups.md)
- Inventory: [`docs/inventory.md`](inventory.md)
- Secrets: `secrets/homelab.env` (from `secrets/homelab.env.example`)
