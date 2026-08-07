# Headscale + Tailscale (`*.g5.lan`)

Pretty names for G5 apps over the tailnet, with private-CA HTTPS.

| Name | Backend |
|------|---------|
| https://g5.lan | Landing page (Caddy on G5) |
| https://jellyfin.g5.lan | `:8096` |
| https://immich.g5.lan | `:2283` |
| https://radarr.g5.lan | `:7878` |
| https://sonarr.g5.lan | `:8989` |
| https://lidarr.g5.lan | `:8686` |
| https://prowlarr.g5.lan | `:9696` |
| https://qbittorrent.g5.lan | `:8080` |
| https://nzbget.g5.lan | `:6789` |
| https://grafana.g5.lan | Pi `:3000` (proxied via G5 Caddy → `192.168.0.104`) |
| https://hubitat.g5.lan | Hubitat hub (proxied via G5 Caddy → `192.168.0.61`) |
| https://opencode.g5.lan | OpenCode web (host `:4096`, Cursor CLI backend) |
| https://seerr.g5.lan | Seerr (`:5055`) |

Direct `http://g5.local:<port>` / LAN IPs still work for local debugging. **`*.g5.lan` needs the Tailscale app** (MagicDNS). On the home LAN prefer **`*.g5.internal`** (Flint DNS — see below).

## LAN twin (`*.g5.internal`)

Same Caddy sites also answer on **`*.g5.internal`**, resolved by **Flint dnsmasq** to G5’s LAN IP (`192.168.0.54`). No Tailscale required; works if the internet is down (Flint + G5 up).

On Flint (SSH as root):

```bash
uci add_list dhcp.@dnsmasq[0].address='/g5.internal/192.168.0.54'
uci commit dhcp
service dnsmasq restart
```

Or LuCI: **SYSTEM → Advanced Settings → LuCI → Network → DHCP and DNS** (Addresses).

Verify: `dig jellyfin.g5.internal @192.168.0.1` → `192.168.0.54`.

DHCP clients must use Flint (`192.168.0.1`) as DNS. Headscale `extra-records.json` stays `*.g5.lan` only.

## Pieces

| Where | What |
|-------|------|
| **DO droplet** (shared with Pantry) | Headscale container + nginx vhost `hs.waltermichelin.com` (public LE) |
| **G5** | Tailscale node + Caddy `:443` (`tls internal`) for `*.g5.lan` and `*.g5.internal` |
| **Flint** | dnsmasq `address=/g5.internal/192.168.0.54` for LAN names |
| **Clients** | Tailscale app → login server `https://hs.waltermichelin.com` (for `*.g5.lan`); LAN DNS via Flint for `*.g5.internal` |

Homelab owns Headscale config/deploy (`apps/headscale/`, `scripts/deploy-headscale-to-droplet.sh`). Pantry and `waltermichelin.com` repos are untouched. Public DNS for `hs` is a **Namecheap** A record (see [`terraform/headscale/README.md`](../terraform/headscale/README.md)).

## One-time setup

### 1. DNS (Namecheap — authoritative)

Public NS for `waltermichelin.com` is Namecheap, not DigitalOcean.

In Namecheap → **Advanced DNS**, add:

| Type | Host | Value |
|------|------|-------|
| A Record | `hs` | pantry droplet IP (`45.55.214.46`) |

Confirm: `dig +short hs.waltermichelin.com` → droplet IP.

Optional mirror in the DO zone: see [`terraform/headscale/`](../terraform/headscale/) (not queried publicly today).

### 2. Deploy Headscale to the droplet

```bash
# secrets/homelab.env: DROPLET_HOST=<droplet ip>
./scripts/deploy-headscale-to-droplet.sh
```

Create user + preauth key on the droplet:

```bash
ssh root@$DROPLET_HOST 'cd /opt/headscale && docker compose exec headscale headscale users create homelab'
ssh root@$DROPLET_HOST 'cd /opt/headscale && docker compose exec headscale headscale users list'   # note ID
ssh root@$DROPLET_HOST 'cd /opt/headscale && docker compose exec headscale headscale preauthkeys create --user <ID> --reusable --expiration 24h'
```
### 3. Join G5

```bash
# On G5
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --login-server=https://hs.waltermichelin.com --authkey=tskey-... --accept-dns --hostname=g5
tailscale ip -4   # e.g. 100.64.0.1
```

Put that IPv4 into every `value` in [`apps/headscale/extra-records.json`](../apps/headscale/extra-records.json), redeploy Headscale.

### 4. G5 Caddy HTTPS

```bash
./deploy-to-g5.sh media-stack
```

Export the private CA and trust it on Mac/iOS:

```bash
./scripts/export-caddy-g5-ca.sh   # writes ./secrets/g5-caddy-root.crt (gitignored)
# macOS: sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain secrets/g5-caddy-root.crt
```

### 5. Join Mac / phone

Install Tailscale → Settings → Use alternate coordination server / login server: `https://hs.waltermichelin.com` (or open the auth URL from a preauth key).

Then open `https://jellyfin.g5.lan`.

### 6. Retire old LAN DNS (if still set)

- eero → DNS → back to Automatic / Cloudflare (remove `192.168.0.54` as LAN DNS)
- Optional: remove Mac `/etc/resolver/g5.lan` if you installed it earlier

## Ops notes

- **Public surface:** only `https://hs.waltermichelin.com` (Headscale on the droplet). Do **not** port-forward G5 `:80`/`:443` from the WAN.
- **Pantry** stays on droplet `:8080`; Headscale on `127.0.0.1:8081`.
- Update `extra-records.json` if G5’s Tailscale IP changes (rare with stable allocation).
