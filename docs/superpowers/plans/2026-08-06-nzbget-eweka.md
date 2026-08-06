# NZBGet + Eweka on G5 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add NZBGet to the G5 media-stack with Eweka over SSL, `https://nzbget.g5.lan`, and *arr download-client wiring for manual NZB imports.

**Architecture:** LinuxServer NZBGet joins the existing media-stack compose network (direct egress, no Proton). Incomplete/complete downloads live under `/mnt/disks/disk-hdd22/usenet` so *arr can hardlink via remote path mapping. Caddy + Headscale expose the WebUI; NewsLazer stays on the Mac.

**Tech Stack:** Docker Compose, LinuxServer NZBGet, Eweka NNTP SSL (`news.eweka.nl:563`), Caddy, Headscale extra-records, Radarr/Sonarr/Lidarr

## Global Constraints

- Usenet egress is direct SSL to Eweka — do not put NZBGet on Proton/host-net
- Do not replace or disable qBittorrent
- Do not add NZB indexers / Prowlarr Usenet (deferred)
- Do not commit Eweka NNTP credentials; WebUI secrets only in `secrets/homelab.env`
- Prefer minimal diff matching existing media-stack patterns
- Spec: `docs/superpowers/specs/2026-08-06-nzbget-eweka-design.md`

---

## File map

| File | Role |
|------|------|
| `apps/media-stack/docker-compose.yml` | Add `nzbget` service; Caddy `depends_on` |
| `apps/media-stack/caddy/Caddyfile` | `nzbget.g5.lan` → `nzbget:6789` |
| `apps/media-stack/caddy/site/index.html` | Hub link |
| `apps/headscale/extra-records.json` | MagicDNS A record |
| `scripts/materialize-env.sh` | Pass `NZBGET_USER` / `NZBGET_PASS` into media-stack `.env` |
| `secrets/homelab.env.example` | Document WebUI secret keys |
| `docs/lan-storage.md` | NZBGet URL, paths, NewsLazer vs NZBGet workflow |
| `docs/headscale-tailscale.md` | Hostname table row |
| `docs/superpowers/specs/2026-08-06-nzbget-eweka-design.md` | Spec (already written) |

---

### Task 1: Compose — NZBGet service

**Files:**
- Modify: `apps/media-stack/docker-compose.yml`

**Interfaces:**
- Consumes: `NZBGET_USER`, `NZBGET_PASS` from media-stack `.env` (Task 3)
- Produces: container `nzbget` on compose network, host port `6789`, volumes `/config` + `/downloads`

- [ ] **Step 1: Insert `nzbget` service after `qbittorrent` (before `prowlarr`)**

```yaml
  nzbget:
    image: lscr.io/linuxserver/nzbget:latest
    container_name: nzbget
    restart: unless-stopped
    ports:
      - "6789:6789"
    volumes:
      - ./config/nzbget:/config
      # Same HDD as torrents/media so *arr hardlinks work after remote path map.
      - /mnt/disks/disk-hdd22/usenet:/downloads
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - NZBGET_USER=${NZBGET_USER:-nzbget}
      - NZBGET_PASS=${NZBGET_PASS}
```

- [ ] **Step 2: Add `nzbget` to Caddy `depends_on`**

Under the `caddy` service `depends_on` list, add `- nzbget` next to the other apps.

- [ ] **Step 3: Validate compose parses**

```bash
cd /Users/wmichelinz/Code/homelab
NZBGET_USER=nzbget NZBGET_PASS=x WEBUI_PASSWORD=x QBIT_BT_PORT=6881 \
  docker compose -f apps/media-stack/docker-compose.yml config >/dev/null
```

Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add apps/media-stack/docker-compose.yml
git commit -m "$(cat <<'EOF'
Add NZBGet to the G5 media-stack for Eweka Usenet downloads.

EOF
)"
```

---

### Task 2: Caddy, hub, Headscale DNS

**Files:**
- Modify: `apps/media-stack/caddy/Caddyfile`
- Modify: `apps/media-stack/caddy/site/index.html`
- Modify: `apps/headscale/extra-records.json`
- Modify: `docs/headscale-tailscale.md`

**Interfaces:**
- Consumes: compose service name `nzbget` on port `6789`; G5 Tailscale IPv4 `100.64.0.1` (same as sibling records)
- Produces: `https://nzbget.g5.lan` route + MagicDNS name

- [ ] **Step 1: Add Caddy site block after `prowlarr.g5.lan`**

```caddy
nzbget.g5.lan {
	tls internal
	reverse_proxy nzbget:6789
}
```

- [ ] **Step 2: Add hub link after qBittorrent**

In `apps/media-stack/caddy/site/index.html`, after the qBittorrent `<li>`:

```html
      <li><a href="https://nzbget.g5.lan">NZBGet <span>usenet</span></a></li>
```

- [ ] **Step 3: Add Headscale extra-record (same value as siblings)**

Insert in `apps/headscale/extra-records.json` (keep valid JSON array; place near other download apps):

```json
  {
    "name": "nzbget.g5.lan",
    "type": "A",
    "value": "100.64.0.1"
  },
```

- [ ] **Step 4: Document in Headscale table**

In `docs/headscale-tailscale.md` hostname table, add:

```markdown
| https://nzbget.g5.lan | `:6789` |
```

- [ ] **Step 5: Commit**

```bash
git add apps/media-stack/caddy/Caddyfile apps/media-stack/caddy/site/index.html \
  apps/headscale/extra-records.json docs/headscale-tailscale.md
git commit -m "$(cat <<'EOF'
Expose NZBGet on nzbget.g5.lan via Caddy and Headscale.

EOF
)"
```

---

### Task 3: Secrets + materialize-env

**Files:**
- Modify: `secrets/homelab.env.example`
- Modify: `scripts/materialize-env.sh`

**Interfaces:**
- Consumes: keys in `secrets/homelab.env`
- Produces: `NZBGET_USER` / `NZBGET_PASS` in `apps/media-stack/.env`

- [ ] **Step 1: Extend example secrets under media-stack section**

After the qBittorrent / Radarr block in `secrets/homelab.env.example`, add:

```bash
# NZBGet WebUI (Usenet client on G5). Eweka NNTP creds go in NZBGet UI, not here.
NZBGET_USER=nzbget
NZBGET_PASS=change_me
```

- [ ] **Step 2: Materialize keys into media-stack `.env`**

Change `materialize_g5` render line to:

```bash
  envfile_render "$SRC" "${ROOT}/apps/media-stack/.env" \
    WEBUI_PASSWORD QBIT_BT_PORT NZBGET_USER NZBGET_PASS
```

- [ ] **Step 3: Commit**

```bash
git add secrets/homelab.env.example scripts/materialize-env.sh
git commit -m "$(cat <<'EOF'
Materialize NZBGet WebUI credentials into the media-stack env.

EOF
)"
```

---

### Task 4: Docs — lan-storage workflow

**Files:**
- Modify: `docs/lan-storage.md`

**Interfaces:**
- Consumes: design workflow (NewsLazer on Mac vs NZBGet NZB upload)
- Produces: operator runbook rows for URL, paths, Eweka note

- [ ] **Step 1: Add NZBGet to the services table**

Near the qBittorrent / Prowlarr rows:

```markdown
| NZBGet | https://nzbget.g5.lan | http://192.168.0.54:6789 |
```

- [ ] **Step 2: Document download paths + workflow**

After the torrents downloads bullet list, add:

```markdown
- **Usenet (NZBGet):** `/mnt/disks/disk-hdd22/usenet/{incomplete,complete}` → `/downloads/{incomplete,complete}`. Direct SSL to Eweka (`news.eweka.nl:563`) — not via Proton. NewsLazer (Mac) is a separate desktop client; it does not feed NZBGet. Upload NZBs in the NZBGet WebUI (or add a Newznab indexer later).
```

- [ ] **Step 3: Commit**

```bash
git add docs/lan-storage.md
git commit -m "$(cat <<'EOF'
Document NZBGet Usenet paths and NewsLazer vs NZBGet workflow.

EOF
)"
```

---

### Task 5: Deploy on G5 + Headscale + operator config

**Files:**
- No further repo edits required (runtime config on G5 / UI)

**Interfaces:**
- Consumes: Tasks 1–4 committed and synced
- Produces: running NZBGet; Eweka server configured; *arr clients + path maps

- [ ] **Step 1: Set real WebUI password in secrets (on Mac / G5 source of truth)**

Edit `secrets/homelab.env` (not committed): set strong `NZBGET_USER` / `NZBGET_PASS`. Do **not** put Eweka NNTP password here unless you want an operator note key — NNTP goes into NZBGet UI.

- [ ] **Step 2: Create usenet dirs on G5**

```bash
ssh wmichelin@g5.local 'mkdir -p /mnt/disks/disk-hdd22/usenet/{incomplete,complete/{movies,tv,music}} && ls -la /mnt/disks/disk-hdd22/usenet'
```

Expected: directories owned by a user NZBGet can write as (PUID 1000); fix with `chown -R 1000:1000 …/usenet` if needed.

- [ ] **Step 3: Deploy media-stack**

```bash
cd /Users/wmichelinz/Code/homelab
./deploy-to-g5.sh media-stack
```

Expected: `nzbget` container up; port 6789 listening.

- [ ] **Step 4: Redeploy Headscale extra-records**

```bash
./scripts/deploy-headscale-to-droplet.sh
```

Expected: script completes; `nzbget.g5.lan` resolves on Tailscale clients.

- [ ] **Step 5: Configure Eweka in NZBGet UI**

Open `https://nzbget.g5.lan` (or `http://192.168.0.54:6789`):

| Setting | Value |
|---------|--------|
| Server host | `news.eweka.nl` |
| Port | `563` |
| Encryption | yes |
| Username / Password | Eweka account |
| Connections | start at `20` |
| MainDir / paths | InterDir=`/downloads/incomplete`, DestDir=`/downloads/complete` (or linuxserver defaults under `/downloads` — align categories to `movies`/`tv`/`music` under complete) |

Save and use NZBGet’s server test / connection check if available.

- [ ] **Step 6: Wire Radarr / Sonarr / Lidarr**

For each app → Settings → Download Clients → NZBGet:

| Field | Value |
|-------|--------|
| Host | `nzbget` |
| Port | `6789` |
| Username / Password | same as WebUI secrets |
| Category | `movies` / `tv` / `music` |

Settings → Download Clients → Remote Path Mappings → Add:

| Field | Value |
|-------|--------|
| Host | `nzbget` |
| Remote Path | `/downloads/` |
| Local Path | `/data/usenet/` |

Click Test → Save. Keep qBittorrent clients.

- [ ] **Step 7: Verify**

```bash
# From Mac on tailnet / LAN:
curl -fsS -o /dev/null -w '%{http_code}\n' -k https://nzbget.g5.lan/
# From G5:
ssh wmichelin@g5.local 'docker ps --filter name=nzbget --format "{{.Status}}"'
```

Expected: HTTP 200 (or 401 if auth challenge); container healthy/up. Upload a tiny sample NZB if available; confirm unpack under `usenet/complete/<category>` and *arr sees it.

- [ ] **Step 8: Commit only if Step 1–7 required extra repo fixes**

No commit if only runtime UI/secrets changed. If compose/docs needed hotfixes, commit those with a clear message.

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| NZBGet compose service, bridge net, port 6789 | 1 |
| Volumes usenet → `/downloads` | 1 + 5.2 |
| Caddy `nzbget.g5.lan` | 2 |
| Headscale extra-record + redeploy | 2 + 5.4 |
| Hub link | 2 |
| Secrets + materialize | 3 |
| Docs lan-storage + headscale | 2 + 4 |
| Eweka SSL server config | 5.5 |
| *arr clients + remote path map | 5.6 |
| NewsLazer remains Mac-side (documented) | 4 |
| No Proton for Usenet | 1 (bridge) + 4 |
| qBittorrent unchanged | (no task touches it) |
