# NZBGet + Eweka on G5 (manual Usenet)

Date: 2026-08-06  
Host: G5 (`wmichelin-G5-5000` / `g5.local` / `192.168.0.54`)  
Status: design approved in chat; awaiting implementation plan

## Goal

Host **NZBGet** on G5 as a Usenet download client pointed at **Eweka** over SSL. Wire it into Radarr / Sonarr / Lidarr for category-based import on the same disk as torrents. Keep **NewsLazer on the Mac** for browsing/search until a Newznab indexer is added later.

## Non-goals

- Hosting NewsLazer on G5 (desktop GUI; not a Docker/server app)
- Adding a paid/free NZB indexer or Prowlarr Usenet indexers (deferred)
- Routing Usenet through Proton VPN (torrents only)
- Replacing or disabling qBittorrent
- Auto-push from NewsLazer → NZBGet (not supported; separate clients)

## Current state

- Media stack: Jellyfin, Tunarr, Radarr, Sonarr, Lidarr, qBittorrent (host net + `proton0`), Prowlarr, Caddy, FlareSolverr
- Downloads: `/mnt/disks/disk-hdd22/torrents/{incomplete,complete}` for torrents; *arr mount `disk-hdd22` as `/data` for hardlinks
- Access: `https://*.g5.lan` via Headscale MagicDNS + Caddy; secrets in `secrets/homelab.env`
- Eweka account ready; NewsLazer included as desktop newsreader (not a Newznab API)

## Design

### Architecture

```
NewsLazer (Mac)          optional NZB file
        │                        │
        │ (SMB copy if no NZB)   │ upload / watch folder
        ▼                        ▼
┌──────────────────────────────────────────────┐
│ G5 media-stack                               │
│ NZBGet (:6789) ──SSL :563──► news.eweka.nl   │
│      │                                       │
│      ▼ usenet/complete/<category>            │
│ Radarr / Sonarr / Lidarr (hardlink import)   │
│ Caddy → https://nzbget.g5.lan                │
└──────────────────────────────────────────────┘
qBittorrent + Proton unchanged
```

### Compose service

Add to `apps/media-stack/docker-compose.yml`:

- Image: `lscr.io/linuxserver/nzbget:latest`
- Container: `nzbget`
- Bridge network (default compose network) — **not** host/Proton
- Port: `6789:6789`
- Env: `PUID=1000`, `PGID=1000`, `TZ=America/New_York`, `NZBGET_USER` / `NZBGET_PASS` from materialized `.env`
- Volumes:
  - `./config/nzbget:/config`
  - `/mnt/disks/disk-hdd22/usenet:/downloads`
- Caddy `depends_on` includes `nzbget`

### Storage

| Role | Host path | Container |
|------|-----------|-----------|
| Incomplete | `/mnt/disks/disk-hdd22/usenet/incomplete` | `/downloads/incomplete` |
| Complete | `/mnt/disks/disk-hdd22/usenet/complete` | `/downloads/complete` |
| *arr media (existing) | `/mnt/disks/disk-hdd22/media/...` | `/data/media/...` |

Create `usenet/{incomplete,complete}` on G5 (and category subdirs under `complete` as needed: `movies`, `tv`, `music`). Same physical disk as torrents/media so *arr hardlinks work.

Torrent paths under `…/torrents/` are unchanged.

### Eweka (NZBGet server settings)

Configured in NZBGet UI after first deploy (credentials not committed):

| Setting | Value |
|---------|--------|
| Host | `news.eweka.nl` |
| Port | `563` |
| Encryption / SSL | yes |
| Username / Password | Eweka account |
| Connections | within Eweka plan limit (typically ≤20–50; start conservative e.g. 20) |

Direct egress from the container; no Proton tunnel.

### Access / DNS / hub

- Caddy: `nzbget.g5.lan` → `nzbget:6789`
- Headscale: add record in `apps/headscale/extra-records.json` (same G5 Tailscale IPv4 as siblings)
- Landing page: link on `apps/media-stack/caddy/site/index.html`
- Docs: `docs/lan-storage.md`, `docs/headscale-tailscale.md` table rows; optional one-liner that Usenet is direct SSL (not Proton)

Redeploy Headscale after `extra-records.json` change (`./scripts/deploy-headscale-to-droplet.sh`).

### Secrets

Add to `secrets/homelab.env.example` (and real `homelab.env` on deploy hosts):

- `NZBGET_USER`
- `NZBGET_PASS`

Eweka NNTP password stays in NZBGet config on disk (`apps/media-stack/config/nzbget/`, gitignored if not already) or operator notes — do not commit. Optional later: document keys `EWEKA_USER` / `EWEKA_PASS` in secrets for operator reference only (not required for compose).

Materialize into media-stack `.env` via `scripts/materialize-env.sh` (extend the g5 `envfile_render` key list alongside `WEBUI_PASSWORD`).

### *arr download clients

In Radarr / Sonarr / Lidarr → Settings → Download Clients → NZBGet:

| Setting | Value |
|---------|--------|
| Host | `nzbget` |
| Port | `6789` |
| Username / Password | from secrets |
| Category | `movies` / `tv` / `music` respectively |

Keep existing qBittorrent clients. Both Usenet and torrents remain available.

NZBGet reports paths under `/downloads/...`; *arr see the same host tree as `/data/usenet/...` (because `disk-hdd22` is already mounted at `/data`). Configure NZBGet so completed jobs land at `/downloads/complete/<category>`. Add **Remote Path Mapping** in each *arr app:

- Host: `nzbget`
- Remote path: `/downloads/`
- Local path: `/data/usenet/`

### Day-to-day workflows

1. **NZB available:** Upload at `https://nzbget.g5.lan` (or watch folder) → Eweka download → *arr import.
2. **NewsLazer only (no NZB):** Download on Mac → copy finished files to G5 via SMB → Jellyfin libraries and/or *arr Manual Import.
3. **Later (out of scope):** Newznab indexer in Prowlarr → sync to *arr → NZBGet.

### Failure / success checks

1. `https://nzbget.g5.lan` loads after deploy + Headscale record.
2. NZBGet server test to Eweka SSL succeeds.
3. Radarr/Sonarr/Lidarr download-client Test succeeds.
4. One sample NZB downloads, unpacks under `usenet/complete/<category>`, and *arr imports (hardlink preferred).
5. qBittorrent / Proton behavior unchanged.

## Risks

| Risk | Mitigation |
|------|------------|
| Expecting NewsLazer to feed NZBGet | Document: separate clients; NZB upload or future indexer |
| Path mismatch breaks *arr import | Remote path mapping `/downloads/` → `/data/usenet/` |
| Committing Eweka credentials | Config under gitignored config dir; secrets example only for WebUI |
| Too many NNTP connections | Start at ~20; raise only if Eweka allows |
| Headscale record forgotten | Checklist includes droplet redeploy |

## Out of scope for this change

- Prowlarr Usenet indexer setup
- NewsLazer install/automation on G5
- Gluetun / VPN for NZBGet
- Removing public torrent indexers
