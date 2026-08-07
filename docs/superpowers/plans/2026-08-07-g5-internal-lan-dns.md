# `*.g5.internal` LAN DNS + Caddy Dual Hostnames Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Serve every existing Caddy site as `https://*.g5.internal` on the LAN (Flint DNS → G5) while keeping `https://*.g5.lan` for Tailscale.

**Architecture:** Flint dnsmasq maps `g5.internal` / `*.g5.internal` to `192.168.0.54`. Caddy site blocks list both hostnames with the same upstreams and `tls internal`. OpenCode CORS and the hub page accept both name suffixes. Headscale records stay `.lan` only.

**Tech Stack:** Caddy 2, Docker Compose, Flint/OpenWrt dnsmasq (`uci`), OpenCode CORS config, static hub HTML

## Global Constraints

- Do not add `*.g5.internal` to Headscale `extra-records.json`
- Do not change Grafana `GF_SERVER_ROOT_URL` (stays `https://grafana.g5.lan`)
- Do not automate Flint config in-repo — document + operator runs UCI
- Do not port-forward G5 `:80`/`:443` from WAN
- Do not introduce Avahi / `*.g5.local` aliases
- Prefer minimal diffs matching existing media-stack patterns
- Spec: `docs/superpowers/specs/2026-08-07-g5-internal-lan-dns-design.md`

---

## File map

| File | Role |
|------|------|
| `apps/media-stack/caddy/Caddyfile` | Dual hostnames per site |
| `apps/media-stack/caddy/site/index.html` | Hub links match opened suffix |
| `apps/media-stack/docker-compose.yml` | Comment: `.lan` + `.internal` |
| `apps/opencode/opencode.json` | CORS allow `.internal` |
| `apps/opencode/docker-compose.yml` | `--cors` for `.internal` |
| `docs/headscale-tailscale.md` | LAN twin names + Flint DNS section |
| `docs/lan-storage.md` | Prefer `.internal` on LAN; keep `.lan` / ports |
| `docs/inventory.md` | Note dual naming |
| `README.md` | Point at `.internal` / `.lan` |
| `docs/superpowers/specs/2026-08-07-g5-internal-lan-dns-design.md` | Spec (already committed) |

---

### Task 1: Caddy — dual hostnames

**Files:**
- Modify: `apps/media-stack/caddy/Caddyfile`
- Modify: `apps/media-stack/docker-compose.yml` (caddy comment only)

**Interfaces:**
- Consumes: existing upstreams (`jellyfin:8096`, `host.docker.internal:8080`, etc.)
- Produces: each site answers for both `*.g5.lan` and `*.g5.internal`

- [ ] **Step 1: Replace the Caddyfile header + every site address line**

Write the full file as:

```caddy
# Reverse proxy for G5 apps.
# - *.g5.lan     → Headscale MagicDNS (Tailscale IP)
# - *.g5.internal → Flint dnsmasq → LAN IP 192.168.0.54
# TLS: Caddy internal CA (docs/headscale-tailscale.md).
#
# Do not port-forward host :80/:443 from the WAN to G5. Public HTTPS for Headscale
# lives on the pantry droplet (hs.waltermichelin.com) only.

g5.lan, g5.internal {
	tls internal
	root * /srv
	file_server
	encode gzip
}

jellyfin.g5.lan, jellyfin.g5.internal {
	tls internal
	reverse_proxy jellyfin:8096
}

tunarr.g5.lan, tunarr.g5.internal {
	tls internal
	reverse_proxy tunarr:8000
}

radarr.g5.lan, radarr.g5.internal {
	tls internal
	reverse_proxy radarr:7878
}

sonarr.g5.lan, sonarr.g5.internal {
	tls internal
	reverse_proxy sonarr:8989
}

lidarr.g5.lan, lidarr.g5.internal {
	tls internal
	reverse_proxy lidarr:8686
}

qbittorrent.g5.lan, qbittorrent.g5.internal {
	tls internal
	# Preserve Host; tell qBit the real client + HTTPS scheme (CSRF / auth subnet).
	reverse_proxy host.docker.internal:8080 {
		header_up X-Real-IP {remote_host}
		header_up X-Forwarded-For {remote_host}
		header_up X-Forwarded-Proto {scheme}
		header_up X-Forwarded-Host {host}
	}
}

prowlarr.g5.lan, prowlarr.g5.internal {
	tls internal
	reverse_proxy prowlarr:9696
}

nzbget.g5.lan, nzbget.g5.internal {
	tls internal
	reverse_proxy nzbget:6789
}

seerr.g5.lan, seerr.g5.internal {
	tls internal
	reverse_proxy seerr:5055
}

immich.g5.lan, immich.g5.internal {
	tls internal
	# Immich runs in a separate compose project; reach via host-published port.
	reverse_proxy host.docker.internal:2283
}

grafana.g5.lan, grafana.g5.internal {
	tls internal
	# Grafana runs on the Pi; DNS lands on G5, then we proxy across the LAN.
	reverse_proxy 192.168.0.104:3000
}

hubitat.g5.lan, hubitat.g5.internal {
	tls internal
	# Hubitat Elevation hub (separate LAN box).
	reverse_proxy 192.168.0.61:80
}

opencode.g5.lan, opencode.g5.internal {
	tls internal
	# No basic_auth. EventSource cannot send Authorization; Caddy (or OpenCode)
	# basic auth leaves the Web UI blank. Access via Tailscale (*.g5.lan) or LAN (*.g5.internal).
	header -Alt-Svc
	reverse_proxy host.docker.internal:4096 {
		# Force HTTP/1.1 + unbuffered flush so /global/event SSE stays alive.
		transport http {
			versions 1.1
			read_timeout 0
			write_timeout 0
		}
		flush_interval -1
		header_up Host {host}
		header_down X-Accel-Buffering "no"
	}
}
```

- [ ] **Step 2: Update the caddy comment in compose**

In `apps/media-stack/docker-compose.yml`, change the comment above the `caddy:` service from Tailscale-only to:

```yaml
  # Reverse proxy: https://*.g5.lan (Tailscale) and https://*.g5.internal (Flint LAN DNS).
  # TLS: Caddy internal CA — docs/headscale-tailscale.md
```

- [ ] **Step 3: Verify every required `.internal` name is present**

```bash
cd /Users/wmichelinz/Code/homelab
for n in g5 jellyfin tunarr radarr sonarr lidarr qbittorrent prowlarr nzbget seerr immich grafana hubitat opencode; do
  if [[ "$n" == "g5" ]]; then
    rg -q '^g5\.lan, g5\.internal \{' apps/media-stack/caddy/Caddyfile || { echo "MISSING $n"; exit 1; }
  else
    rg -q "^${n}\\.g5\\.lan, ${n}\\.g5\\.internal \\{" apps/media-stack/caddy/Caddyfile || { echo "MISSING $n"; exit 1; }
  fi
done
echo "OK all sites dual-homed"
```

Expected: `OK all sites dual-homed`

- [ ] **Step 4: Commit**

```bash
git add apps/media-stack/caddy/Caddyfile apps/media-stack/docker-compose.yml
git commit -m "$(cat <<'EOF'
Serve Caddy sites on *.g5.internal alongside *.g5.lan.

EOF
)"
```

---

### Task 2: Hub — suffix-aware links

**Files:**
- Modify: `apps/media-stack/caddy/site/index.html`

**Interfaces:**
- Consumes: browser `location.hostname` (`g5.lan` or `g5.internal`)
- Produces: app links on matching suffix (`jellyfin.g5.internal` when hub opened as `g5.internal`)

- [ ] **Step 1: Replace the hub body so links are filled from the current host suffix**

Keep existing CSS. Change `<title>`, heading, and list to:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>g5</title>
  <style>
    :root {
      --bg: #0f1419;
      --fg: #e7ecf1;
      --muted: #8b98a5;
      --line: #243040;
      --accent: #6db3f2;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: "IBM Plex Sans", "Segoe UI", sans-serif;
      background:
        radial-gradient(ellipse at top left, #1a2838 0%, transparent 55%),
        radial-gradient(ellipse at bottom right, #162032 0%, transparent 50%),
        var(--bg);
      color: var(--fg);
      display: grid;
      place-items: center;
      padding: 2rem;
    }
    main { width: min(36rem, 100%); }
    h1 {
      font-family: "IBM Plex Serif", Georgia, serif;
      font-weight: 500;
      font-size: 2.4rem;
      margin: 0 0 0.35rem;
      letter-spacing: -0.02em;
    }
    p { margin: 0 0 1.75rem; color: var(--muted); }
    ul {
      list-style: none;
      margin: 0;
      padding: 0;
      border-top: 1px solid var(--line);
    }
    li { border-bottom: 1px solid var(--line); }
    a {
      display: flex;
      justify-content: space-between;
      gap: 1rem;
      padding: 0.9rem 0.15rem;
      color: var(--fg);
      text-decoration: none;
    }
    a:hover { color: var(--accent); }
    a span { color: var(--muted); font-size: 0.9rem; }
  </style>
</head>
<body>
  <main>
    <h1 id="hub-title">g5</h1>
    <p>Homelab apps on this host.</p>
    <ul id="hub-links"></ul>
  </main>
  <script>
    (function () {
      var root = location.hostname.endsWith(".internal") ? "g5.internal" : "g5.lan";
      document.getElementById("hub-title").textContent = root;
      document.title = root;
      var apps = [
        ["jellyfin", "Jellyfin", "media"],
        ["tunarr", "Tunarr", "live TV"],
        ["immich", "Immich", "photos"],
        ["radarr", "Radarr", "movies"],
        ["sonarr", "Sonarr", "tv"],
        ["lidarr", "Lidarr", "music"],
        ["prowlarr", "Prowlarr", "indexers"],
        ["seerr", "Seerr", "requests"],
        ["qbittorrent", "qBittorrent", "downloads"],
        ["nzbget", "NZBGet", "usenet"],
        ["grafana", "Grafana", "pi / monitoring", "/d/homelab-monitoring/homelab-monitoring"],
        ["hubitat", "Hubitat", "home automation"],
        ["opencode", "OpenCode", "coding agent"]
      ];
      var ul = document.getElementById("hub-links");
      apps.forEach(function (a) {
        var href = "https://" + a[0] + "." + root + (a[3] || "");
        var li = document.createElement("li");
        li.innerHTML = '<a href="' + href + '">' + a[1] + " <span>" + a[2] + "</span></a>";
        ul.appendChild(li);
      });
    })();
  </script>
</body>
</html>
```

- [ ] **Step 2: Sanity-check the script chooses the right root**

```bash
cd /Users/wmichelinz/Code/homelab
# Extract the root ternary and evaluate mentally / with node
node -e '
const cases = [
  ["g5.internal", "g5.internal"],
  ["g5.lan", "g5.lan"],
  ["jellyfin.g5.internal", "g5.internal"],
];
for (const [hostname, want] of cases) {
  const root = hostname.endsWith(".internal") ? "g5.internal" : "g5.lan";
  if (root !== want) { console.error("FAIL", hostname, root); process.exit(1); }
}
console.log("OK hub suffix logic");
'
rg -q 'g5\.internal' apps/media-stack/caddy/site/index.html
rg -q 'hub-links' apps/media-stack/caddy/site/index.html
```

Expected: `OK hub suffix logic`

- [ ] **Step 3: Commit**

```bash
git add apps/media-stack/caddy/site/index.html
git commit -m "$(cat <<'EOF'
Make the G5 hub link apps using the opened .lan or .internal suffix.

EOF
)"
```

---

### Task 3: OpenCode CORS for `.internal`

**Files:**
- Modify: `apps/opencode/opencode.json`
- Modify: `apps/opencode/docker-compose.yml`

**Interfaces:**
- Consumes: browser origin `https://opencode.g5.internal`
- Produces: CORS allowlist includes both `.lan` and `.internal`

- [ ] **Step 1: Update `opencode.json` cors array**

```json
    "cors": ["https://opencode.g5.lan", "https://opencode.g5.internal"]
```

- [ ] **Step 2: Pass both origins on the `web` CLI**

In `apps/opencode/docker-compose.yml`, OpenCode accepts repeated `--cors` flags. Replace the single `--cors` / URL pair with:

```yaml
      - --cors
      - https://opencode.g5.lan
      - --cors
      - https://opencode.g5.internal
      - --pure
```

Also update the top comment and the “Access boundary” comment to mention LAN `*.g5.internal` in addition to Tailscale.

- [ ] **Step 3: Verify both origins appear**

```bash
cd /Users/wmichelinz/Code/homelab
rg -n 'opencode\.g5\.internal' apps/opencode/opencode.json apps/opencode/docker-compose.yml
# expect matches in both files
python3 -c 'import json; c=json.load(open("apps/opencode/opencode.json"))["server"]["cors"]; assert "https://opencode.g5.internal" in c and "https://opencode.g5.lan" in c'
```

Expected: exit 0; both files listed by `rg`.

- [ ] **Step 4: Commit**

```bash
git add apps/opencode/opencode.json apps/opencode/docker-compose.yml
git commit -m "$(cat <<'EOF'
Allow OpenCode CORS from opencode.g5.internal.

EOF
)"
```

---

### Task 4: Docs — Flint DNS + dual names

**Files:**
- Modify: `docs/headscale-tailscale.md`
- Modify: `docs/lan-storage.md`
- Modify: `docs/inventory.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: design name table + Flint UCI snippet from the spec
- Produces: operator docs that prefer `.internal` on LAN and `.lan` on Tailscale

- [ ] **Step 1: Add a “LAN twin (`*.g5.internal`)” section to `docs/headscale-tailscale.md`**

After the opening name table (or after “Pieces”), insert:

```markdown
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
```

Also soften the line that says browsers need Tailscale / there is no dnsmasq path — that now applies to **`.lan`**, while **`.internal`** is the Flint path.

- [ ] **Step 2: Update `docs/lan-storage.md` media apps table**

Change the preference blurb to prefer `*.g5.internal` on LAN, and add an Internal column (or replace “Subdomain” values to show both). Minimum: note hub `https://g5.internal` and that each app is also `https://<app>.g5.internal`, with Tailscale still `*.g5.lan`.

- [ ] **Step 3: Update `docs/inventory.md` and `README.md`**

- Inventory G5 row: Caddy for `*.g5.lan` **and** `*.g5.internal`
- README quick links: Immich / media hub mention `https://….g5.internal` (LAN) and `https://….g5.lan` (Tailscale)

- [ ] **Step 4: Commit**

```bash
git add docs/headscale-tailscale.md docs/lan-storage.md docs/inventory.md README.md
git commit -m "$(cat <<'EOF'
Document *.g5.internal LAN DNS via Flint alongside Tailscale *.g5.lan.

EOF
)"
```

---

### Task 5: Deploy and verify

**Files:**
- None in-repo (operator Flint + deploy)

**Interfaces:**
- Consumes: Tasks 1–4 committed; Flint DNS rule
- Produces: live HTTPS on both suffixes

- [ ] **Step 1: Flint DNS (operator)**

```bash
ssh root@192.168.0.1
uci add_list dhcp.@dnsmasq[0].address='/g5.internal/192.168.0.54'
uci commit dhcp
service dnsmasq restart
exit
dig +short jellyfin.g5.internal @192.168.0.1
```

Expected: `192.168.0.54`

If the address list already contains that entry, `uci add_list` may duplicate — check with `uci show dhcp | grep address` first and skip add if present.

- [ ] **Step 2: Deploy media-stack (+ OpenCode if not covered)**

```bash
cd /Users/wmichelinz/Code/homelab
./deploy-to-g5.sh media-stack
# If OpenCode is a separate compose project on G5:
ssh g5 'cd ~/code/homelab/apps/opencode && docker compose up -d --build'
```

Expected: deploy script finishes without error; `g5-caddy` recreated/reloaded.

- [ ] **Step 3: HTTPS smoke (LAN + Tailscale)**

```bash
# LAN (.internal) — use -k if CA not yet trusted for new SANs, else omit -k
curl -fsS -o /dev/null -w 'internal hub %{http_code}\n' https://g5.internal/
curl -fsS -o /dev/null -w 'internal jellyfin %{http_code}\n' https://jellyfin.g5.internal/
curl -fsS -o /dev/null -w 'internal opencode %{http_code}\n' https://opencode.g5.internal/

# Tailscale (.lan) still works
curl -fsS -o /dev/null -w 'lan jellyfin %{http_code}\n' https://jellyfin.g5.lan/
```

Expected: HTTP `200` (or app-specific redirect `302`/`401` that still proves Caddy matched the host). If TLS fails only on `.internal`, re-export CA via `./scripts/export-caddy-g5-ca.sh` and re-trust, or confirm Caddy reloaded.

- [ ] **Step 4: Hub link check**

Open `https://g5.internal` in a browser → Jellyfin link must be `https://jellyfin.g5.internal`.  
Open `https://g5.lan` → Jellyfin link must be `https://jellyfin.g5.lan`.

- [ ] **Step 5: Mark design status (optional)**

In `docs/superpowers/specs/2026-08-07-g5-internal-lan-dns-design.md`, set Status to `implemented` and commit if you want the trail updated.

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Dual Caddy hostnames for all listed apps | 1 |
| Flint `address=/g5.internal/192.168.0.54` | 4 (docs) + 5 (ops) |
| OpenCode CORS `.internal` | 3 |
| Hub suffix-aware links | 2 |
| Docs (headscale, lan-storage, inventory, README) | 4 |
| No Headscale `.internal` records | Global + Task 4 note |
| Grafana root URL unchanged | Global (no task touches it) |
| Deploy + verify both suffixes | 5 |
