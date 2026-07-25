# G5 LAN subdomains (`*.g5.lan`)

Pretty names for G5 apps without fighting mDNS (`.local`).

| Name | Backend |
|------|---------|
| http://g5.lan | Landing page (Caddy) |
| http://jellyfin.g5.lan | `:8096` |
| http://immich.g5.lan | `:2283` |
| http://radarr.g5.lan | `:7878` |
| http://sonarr.g5.lan | `:8989` |
| http://lidarr.g5.lan | `:8686` |
| http://prowlarr.g5.lan | `:9696` |
| http://qbittorrent.g5.lan | `:8080` |
| http://grafana.g5.lan | Pi `:3000` (proxied via G5 Caddy → `192.168.0.104`) |
| http://hubitat.g5.lan | Hubitat hub (proxied via G5 Caddy → `192.168.0.61`) |

Direct `http://g5.local:<port>` URLs still work (Prometheus/blackbox keep using ports). `http://pi:3000` still reaches Grafana too.

## Pieces (all on G5)

1. **Caddy** — `apps/media-stack/caddy/` (host `:80`)
2. **dnsmasq** — `apps/media-stack/dnsmasq/` on `192.168.0.54:53`
   - answers `*.g5.lan` → `192.168.0.54`
   - forwards all other queries to Cloudflare/Google

## Whole LAN (eero)

eero’s DNS page only chooses recursive servers — it has **no** local host rewrite. To get `*.g5.lan` on every device:

1. eero app → **Settings → DNS → Custom DNS**
2. Set:
   - **IPv4 primary:** `192.168.0.54` (G5)
   - **IPv4 secondary:** `1.1.1.1` (failover for internet if G5 is off)
   - **IPv6 primary/secondary:** leave blank if the UI allows, otherwise use `2606:4700:4700::1111` / `2606:4700:4700::1001` — but prefer blank IPv6 so clients don’t bypass G5 via Google IPv6 DNS
3. Save, then renew DHCP on phones (toggle Wi‑Fi) so they pick up the new DNS

**Tradeoff:** while G5 is down, `*.g5.lan` is gone (expected — the apps are on G5). Internet DNS should still work via the secondary after clients fail over. The Pi is not involved.

## Optional: Mac split DNS

Not required once eero Custom DNS is set. If you still want this laptop independent of DHCP:

```bash
sudo ./scripts/install-mac-g5-lan-resolver.sh   # → 192.168.0.54
```

## Deploy

```bash
./deploy-to-g5.sh media-stack
```
