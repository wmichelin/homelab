# qBittorrent Proton-only egress (host net + `proton0` bind)

Date: 2026-08-03  
Host: G5 (`wmichelin-G5-5000` / `g5.local` / `192.168.0.54`)  
Status: design approved in chat; awaiting implementation plan

## Goal

If Proton VPN is down or `proton0` is absent, qBittorrent must have **no BitTorrent peer connectivity**. LAN WebUI and *arr → qBit control plane may remain up.

## Non-goals

- Moving torrents into Gluetun / a separate VPN container
- Putting Prowlarr / indexers on the VPN
- Changing Headscale / `*.g5.lan` DNS

## Current state

- Host Proton VPN CLI (WireGuard) + NAT-PMP port forward via `scripts/proton-qbit-port-forward.sh`
- qBittorrent: LinuxServer image, **bridge** network, published `8080` + `QBIT_BT_PORT`
- Port-forward script **clears** `current_network_interface` / `current_interface_address` and recreates the container when the forwarded port changes so Docker publishes match

## Design

### Networking

1. Set qBittorrent to `network_mode: host`.
2. Remove compose `ports:` for WebUI and BT (redundant under host net).
3. In qBittorrent preferences (enforced by the port-forward script):
   - `current_network_interface` = `proton0`
   - `current_interface_address` = `""` (let qBit pick on that iface)
   - `upnp` = `false`
   - `listen_port` = Proton NAT-PMP mapped port (unchanged behavior)
4. WebUI remains on host `:8080` (LAN / Caddy). WebUI traffic is **not** required to use Proton; only torrent sockets bind to `proton0`.

### Reachability from other containers

Host-networked qBit is **not** on the compose bridge DNS name `qbittorrent`.

| Consumer | Target after change |
|----------|---------------------|
| Caddy | `host.docker.internal:8080` (Caddy already has `extra_hosts: host.docker.internal:host-gateway`) |
| Radarr / Sonarr / Lidarr download clients | `host.docker.internal` (or `192.168.0.54`), port `8080` |
| `proton-qbit-port-forward.sh` | keep `http://127.0.0.1:8080` |

`https://qbittorrent.g5.lan` is unchanged for browsers (Caddy hostname); only the upstream proxy target changes.

### Port-forward script

- On renew / preference sync: **set** `current_network_interface` to `proton0` (do not clear).
- Stop requiring Docker port republication for BT: with host net, changing `listen_port` inside qBit is enough; remove or no-op `recreate_qbittorrent_if_needed` port-publish logic (may still write `QBIT_BT_PORT` to env for documentation / other tools).
- If `proton0` is missing: leave bind configured; qBit fails closed for peers (desired).

### Docs

Update `docs/proton-vpn-g5.md` (and a one-liner in `docs/lan-storage.md` if needed): host network + `proton0` bind is the torrent kill switch.

## Failure / success checks

1. Proton connected → torrents get peers; forwarded port matches WebUI listen port.
2. `protonvpn disconnect` (or `proton0` gone) → no new peers; transfers stall.
3. `https://qbittorrent.g5.lan` still loads.
4. Radarr can still add/query the download client after host update.

## Risks

| Risk | Mitigation |
|------|------------|
| *arr still pointed at `qbittorrent` hostname | Update download client host after cutover; verify in UI |
| Caddy still proxies to `qbittorrent:8080` | Change Caddyfile before or with compose recreate |
| Someone resets qBit prefs to “Any” interface | Script re-applies `proton0` on each renew |
| Host net + future accidental second bind on 8080 | Only one qBit instance; keep WEBUI_PORT=8080 |

## Out of scope for this change

- Auto-fixing *arr download-client settings via API (manual once is fine unless we choose to automate)
- UFW rules specific to BT (interface bind is the primary control)
