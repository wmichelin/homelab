# G5 LAN names via `*.g5.internal`

Date: 2026-08-07  
Host: G5 (`g5` / `g5.local` / `192.168.0.54`)  
Status: implemented (Caddy + docs deployed; Flint DNS is operator step)

## Goal

Expose every current Caddy site under **`*.g5.internal`** on the home LAN (Flint DNS → G5), while keeping **`*.g5.lan`** for Tailscale/Headscale MagicDNS. LAN HTTPS works without Tailscale and without internet (as long as Flint + G5 are up).

## Non-goals

- Avahi / mDNS aliases (`jellyfin.g5.local` or other multi-label `.local`)
- Replacing or renaming `*.g5.lan`
- Adding `*.g5.internal` to Headscale `extra-records.json`
- Changing Grafana’s canonical `GF_SERVER_ROOT_URL` (stays `https://grafana.g5.lan`)
- WAN port-forward of G5 `:80`/`:443`
- Automating Flint config from this repo (manual router step; documented only)

## Current state

- Caddy on G5 serves hub + apps as `https://*.g5.lan` with `tls internal`
- Headscale MagicDNS (`apps/headscale/extra-records.json`) maps `*.g5.lan` → G5 Tailscale IP (`100.64.0.1`)
- Clients trust Caddy’s internal CA for `*.g5.lan`
- Flint 2 is LAN gateway/DNS at `192.168.0.1`; G5 is `192.168.0.54`
- `g5.local` remains Avahi hostname only (SSH / raw ports)

## Design

### Architecture

```text
LAN client                     Tailscale client
    │                                │
    ▼                                ▼
Flint DNS                     Headscale MagicDNS
*.g5.internal → 192.168.0.54  *.g5.lan → 100.64.0.1
    │                                │
    └────────────┬───────────────────┘
                 ▼
         Caddy on G5 (:443, tls internal)
         same upstreams for both hostnames
```

### Names (both sides)

| Role | LAN | Tailnet |
|------|-----|---------|
| Hub | `https://g5.internal` | `https://g5.lan` |
| Jellyfin | `https://jellyfin.g5.internal` | `https://jellyfin.g5.lan` |
| Tunarr | `https://tunarr.g5.internal` | `https://tunarr.g5.lan` |
| Immich | `https://immich.g5.internal` | `https://immich.g5.lan` |
| Radarr | `https://radarr.g5.internal` | `https://radarr.g5.lan` |
| Sonarr | `https://sonarr.g5.internal` | `https://sonarr.g5.lan` |
| Lidarr | `https://lidarr.g5.internal` | `https://lidarr.g5.lan` |
| Prowlarr | `https://prowlarr.g5.internal` | `https://prowlarr.g5.lan` |
| Seerr | `https://seerr.g5.internal` | `https://seerr.g5.lan` |
| qBittorrent | `https://qbittorrent.g5.internal` | `https://qbittorrent.g5.lan` |
| NZBGet | `https://nzbget.g5.internal` | `https://nzbget.g5.lan` |
| Grafana | `https://grafana.g5.internal` | `https://grafana.g5.lan` |
| Hubitat | `https://hubitat.g5.internal` | `https://hubitat.g5.lan` |
| OpenCode | `https://opencode.g5.internal` | `https://opencode.g5.lan` |

### Flint DNS (manual)

One dnsmasq address rule covers the apex and all subdomains:

```text
address=/g5.internal/192.168.0.54
```

Apply via SSH on Flint:

```bash
uci add_list dhcp.@dnsmasq[0].address='/g5.internal/192.168.0.54'
uci commit dhcp
service dnsmasq restart
```

Or via LuCI: **SYSTEM → Advanced Settings → LuCI → Network → DHCP and DNS** (Addresses / equivalent), if the build exposes the `address` list.

DHCP must hand out Flint (`192.168.0.1`) as DNS so clients resolve `.internal` locally. Do not rely on public resolvers alone for these names.

### Caddy

In `apps/media-stack/caddy/Caddyfile`, each site block accepts both hostnames, e.g.:

```caddy
jellyfin.g5.lan, jellyfin.g5.internal {
	tls internal
	reverse_proxy jellyfin:8096
}
```

Same pattern for hub (`g5.lan, g5.internal`) and every existing app block. Upstream targets unchanged.

TLS stays `tls internal`. Clients that already trust the G5 Caddy root continue to work; new SANs appear after Caddy reload. Re-export/trust CA only if a client rejects the new names.

### App allowlists / hub

- OpenCode CORS (`opencode.json` + compose args): add `https://opencode.g5.internal`
- Grafana root URL: leave `https://grafana.g5.lan` (canonical); `.internal` is Caddy alias only
- Hub `index.html`: links should work for whichever hostname opened the hub (relative URLs or host-relative construction — avoid hard-coding only `.lan`)

### Docs

Update operator docs so LAN preferred URLs are `https://….g5.internal` and Tailscale remains `https://….g5.lan`:

- `docs/headscale-tailscale.md` (note LAN twin names; DNS via Flint)
- `docs/lan-storage.md` / `docs/inventory.md` / `README.md` as needed
- Short “Flint DNS” snippet for the `address=/g5.internal/…` step

### Out of repo

Flint UCI change is operator-run. Headscale records stay `.lan` only.

## Rollout

1. Flint: add `address=/g5.internal/192.168.0.54`, restart dnsmasq; verify `dig jellyfin.g5.internal @192.168.0.1`
2. Repo: dual hostnames in Caddyfile; OpenCode CORS; hub links; docs
3. `./deploy-to-g5.sh media-stack` (and OpenCode bits if separate)
4. Verify HTTPS on both `.internal` and `.lan` for a sample of apps

## Success criteria

1. On LAN without Tailscale: `https://jellyfin.g5.internal` loads (and peers in the name table)
2. Tailscale: `https://jellyfin.g5.lan` unchanged
3. WAN down, Flint+G5 up: `.internal` still resolves and serves; `.lan` may fail
4. OpenCode usable at `https://opencode.g5.internal` (CORS ok)
5. Hub opened via either name links to apps on the same suffix

## Rejected alternatives

| Option | Why rejected |
|--------|----------------|
| `*.g5.local` via Avahi aliases | Multi-label mDNS is fiddly; needs helper daemons; Windows CNAME issues |
| Flint hijack of `.local` | Conflicts with Bonjour/mDNS; RFC 6762 special-use |
| Path routes only on `g5.local` | Not hostname-per-app; breaks some apps |
| Headscale-only / no LAN DNS | Fails intranet / offline resiliency goal |
