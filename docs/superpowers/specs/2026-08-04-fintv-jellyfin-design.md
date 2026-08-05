# FinTV on Jellyfin (plugin + Live TV wiring)

Date: 2026-08-04  
Host: G5 (`wmichelin-G5-5000` / `g5.local` / `192.168.0.54`)  
Status: design approved in chat; awaiting implementation plan

## Goal

Install [FinTV](https://github.com/binarygeek119/FinTV) on the existing G5 Jellyfin so Live TV can consume FinTV’s M3U + XMLTV endpoints. Operator can create virtual channels later in the FinTV admin UI.

## Non-goals

- Upgrading Jellyfin to 12.x (stay on **10.11.11**)
- Creating channels, lineups, commercials, or WeatherStar
- Mounting the Docker socket / Playwright sidecar (weather-only)
- Switching to FinTV’s custom Jellyfin image
- Automating install via deploy hooks

## Current state

- Jellyfin: `jellyfin/jellyfin:latest` → **10.11.11**, compose at `apps/media-stack/docker-compose.yml`
- Config volume: `apps/media-stack/config/jellyfin` → `/config`
- Plugins dir empty of third-party plugins (only stock `configurations/`)
- Reachable at `https://jellyfin.g5.lan` (Caddy) and `http://192.168.0.54:8096`
- Libraries: Movies / Music / TV under `/media`

## Version pin

| Component | Version | Reason |
|-----------|---------|--------|
| Jellyfin | 10.11.11 (keep `latest` until 12 final) | Stable production server |
| FinTV | **0.0.1.3** | `targetAbi` 10.11; newer FinTV targets Jellyfin 12 |

Artifact: `https://github.com/binarygeek119/FinTV/releases/download/v0.0.1.3/fintv_0.0.1.3.zip`

Do **not** install the newest catalog entry from the FinTV manifest without checking ABI — master line is 0.0.2.x for Jellyfin 12.

## Design

### 1. Plugin install (pinned zip on G5)

1. On G5, download `fintv_0.0.1.3.zip`.
2. Extract into `{jellyfin config}/plugins/FinTV/` so the plugin DLL and meta live under that folder (Jellyfin convention: one directory per plugin under `plugins/`).
3. `docker restart jellyfin` (or compose restart) and confirm FinTV appears under **Dashboard → Plugins → Installed**.

Path on G5: `~/code/homelab/apps/media-stack/config/jellyfin/plugins/FinTV/`

### 2. FinTV Public Base URL

In **Dashboard → Plugins → FinTV → Live TV Setup**, set:

- **Public Base URL:** `http://192.168.0.54:8096`

Rationale: Jellyfin fetches FinTV M3U/stream URLs server-side inside the container. Direct LAN HTTP avoids Caddy TLS / internal CA issues. Clients still use `https://jellyfin.g5.lan` for the normal web UI; Live TV playback goes through Jellyfin.

### 3. Jellyfin Live TV wiring

| Device | Type | URL |
|--------|------|-----|
| Tuner | M3U Tuner | `http://127.0.0.1:8096/FinTV/iptv/channels.m3u` |
| Guide | XMLTV | `http://127.0.0.1:8096/FinTV/iptv/epg.xml` |

`127.0.0.1` is correct from inside the Jellyfin container (FinTV listens on the same process).

Then run scheduled tasks in order:

1. **Refresh Channels**
2. **Refresh Guide**

With zero FinTV channels configured, the playlist/guide may be empty — that is expected for this scope. Wiring is validated when the tuner/guide sources save without error and FinTV plugin pages load.

### 4. Docs

Add a short subsection to `docs/lan-storage.md` (Media apps area):

- FinTV 0.0.1.3 on Jellyfin 10.11.11
- Public Base URL + M3U/XMLTV URLs above
- Note: channels/lineups are configured later in Dashboard → Plugins → FinTV
- Note: Jellyfin 12 + FinTV 0.0.2.x is a future optional upgrade

## Out of scope follow-ups (not this plan)

- Starter TV/movie channels and lineups
- Commercial library / Open-Commercial-Pack
- WeatherStar (`docker.sock`, Playwright sidecar, ws4kp)
- Pinning `jellyfin/jellyfin:10.11.11` explicitly when `latest` moves to 12

## Failure / success checks

1. After restart, FinTV shows as installed (version 0.0.1.3); Jellyfin remains 10.11.11.
2. `curl -sf http://127.0.0.1:8096/FinTV/iptv/channels.m3u` from inside the container (or via host-mapped 8096) returns HTTP 200 (body may be minimal/empty).
3. Same for `/FinTV/iptv/epg.xml`.
4. Live TV tuner + XMLTV provider exist in Dashboard and Refresh Channels / Refresh Guide complete without hard failure.
5. Normal library playback (Movies/TV) still works after restart.

## Rollback

1. Remove `plugins/FinTV/` (and FinTV config under `plugins/configurations/` if present).
2. Remove the FinTV M3U tuner and XMLTV provider from Live TV.
3. Restart Jellyfin.
