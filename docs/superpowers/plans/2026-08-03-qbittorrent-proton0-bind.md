# qBittorrent Proton0 Bind Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make qBittorrent BitTorrent traffic fail closed when `proton0` is absent by switching to host networking and binding the listen socket to `proton0`.

**Architecture:** qBittorrent runs with `network_mode: host` so it can see the Proton WireGuard interface. Preferences force `current_network_interface=proton0`. Caddy and *arr apps reach the WebUI via `host.docker.internal:8080`. The existing NAT-PMP loop keeps setting listen port + interface bind and no longer republishes Docker ports.

**Tech Stack:** Docker Compose, LinuxServer qBittorrent, Proton VPN CLI (WireGuard `proton0`), bash (`scripts/proton-qbit-port-forward.sh`), Caddy

## Global Constraints

- Keep LAN WebUI on host `:8080` and `https://qbittorrent.g5.lan` working
- Do not put Prowlarr/indexers on the VPN
- Do not clear `current_network_interface` anymore — always set `proton0`
- Prefer minimal diff: compose + Caddyfile + port-forward script + docs
- Do not commit unless the user asks

---

## File map

| File | Role |
|------|------|
| `apps/media-stack/docker-compose.yml` | Host-network qBittorrent; drop published ports |
| `apps/media-stack/caddy/Caddyfile` | Proxy WebUI via `host.docker.internal:8080` |
| `scripts/proton-qbit-port-forward.sh` | Set `proton0` bind; stop Docker BT port recreate |
| `docs/proton-vpn-g5.md` | Document kill-switch model |
| `docs/lan-storage.md` | One-line note on host net / download client host |
| `docs/superpowers/specs/2026-08-03-qbittorrent-proton0-bind-design.md` | Spec (already written) |

---

### Task 1: Compose — host network for qBittorrent

**Files:**
- Modify: `apps/media-stack/docker-compose.yml` (qbittorrent service)

**Interfaces:**
- Consumes: existing `WEBUI_PASSWORD`, volumes, `PUID`/`PGID`/`TZ`/`WEBUI_PORT`
- Produces: qBittorrent process on host net listening on `:8080` and BT `listen_port` (no Docker port maps)

- [ ] **Step 1: Replace the qbittorrent service networking block**

Change the `qbittorrent` service so it looks like this (keep image/volumes/env; remove `ports:`; add `network_mode: host`):

```yaml
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    restart: unless-stopped
    # Host net so BitTorrent can bind to proton0 (VPN kill switch).
    # WebUI is on host :8080; Caddy reaches it via host.docker.internal.
    # BT listen port is set by proton-qbit-port-forward.sh (no Docker publish).
    network_mode: host
    volumes:
      - ./config/qbittorrent:/config
      - /mnt/disks/disk-hdd22/torrents:/downloads
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=America/New_York
      - WEBUI_PORT=8080
      - WEBUI_PASSWORD=${WEBUI_PASSWORD}
```

- [ ] **Step 2: Sanity-check compose on the Mac (no deploy yet)**

Run:

```bash
docker compose -f apps/media-stack/docker-compose.yml config >/dev/null
```

Expected: exit 0 (may warn about missing `.env`; that is fine if config still parses). If `.env` is required locally, run from a checkout that has `apps/media-stack/.env` or pass dummy `WEBUI_PASSWORD=x QBIT_BT_PORT=6881`.

- [ ] **Step 3: Commit (only if user asked to commit)**

```bash
git add apps/media-stack/docker-compose.yml
git commit -m "$(cat <<'EOF'
Use host networking for qBittorrent so it can bind to proton0.

EOF
)"
```

---

### Task 2: Caddy — proxy to host WebUI

**Files:**
- Modify: `apps/media-stack/caddy/Caddyfile` (qbittorrent.g5.lan block)

**Interfaces:**
- Consumes: Caddy `extra_hosts: host.docker.internal:host-gateway` already on the `caddy` service in compose
- Produces: `https://qbittorrent.g5.lan` → host `:8080`

- [ ] **Step 1: Update reverse_proxy target**

Replace:

```caddy
	reverse_proxy qbittorrent:8080 {
```

with:

```caddy
	reverse_proxy host.docker.internal:8080 {
```

Keep the existing `header_up` lines unchanged.

- [ ] **Step 2: Commit (only if user asked)**

```bash
git add apps/media-stack/caddy/Caddyfile
git commit -m "$(cat <<'EOF'
Point qbittorrent.g5.lan at host WebUI after host-network cutover.

EOF
)"
```

---

### Task 3: Port-forward script — bind `proton0`, stop Docker republish

**Files:**
- Modify: `scripts/proton-qbit-port-forward.sh`

**Interfaces:**
- Consumes: qBittorrent WebUI API at `QBIT_WEBUI_URL` (default `http://127.0.0.1:8080`)
- Produces: preferences JSON always includes `"current_network_interface":"proton0"`; `QBIT_BT_PORT` still written to env; no `docker compose up` solely to republish BT ports

- [ ] **Step 1: Change `qbit_set_listen_port` to force `proton0`**

Replace the function body so the preferences payload sets the interface:

```bash
qbit_set_listen_port() {
  local port="$1"
  # Bind BitTorrent to Proton WireGuard only — no peers if proton0 is down.
  curl -fsS -b "${COOKIE_JAR}" -c "${COOKIE_JAR}" \
    --data-urlencode "json={\"listen_port\":${port},\"current_network_interface\":\"proton0\",\"current_interface_address\":\"\",\"upnp\":false}" \
    "${QBIT_URL}/api/v2/app/setPreferences" >/dev/null
}
```

- [ ] **Step 2: Replace Docker port republication with env-only sync**

Replace `recreate_qbittorrent_if_needed` with:

```bash
sync_env_bt_port() {
  local port="$1"
  local published
  published="$(read_env_bt_port)"
  if [[ "${published}" == "${port}" ]]; then
    return 0
  fi
  log "Recording QBIT_BT_PORT ${published:-?} -> ${port} (host net; no compose recreate)"
  write_env_bt_port "${port}"
}
```

In `renew_once`, replace the call:

```bash
  recreate_qbittorrent_if_needed "${port}"
```

with:

```bash
  sync_env_bt_port "${port}"
```

- [ ] **Step 3: Always re-apply listen port + `proton0` bind each successful renew**

In `renew_once`, after login, always call `qbit_set_listen_port` (not only when the port differs), so a manual WebUI reset to “Any” cannot stick:

```bash
  local current
  current="$(curl -fsS -b "${COOKIE_JAR}" "${QBIT_URL}/api/v2/app/preferences" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("listen_port",""))')"
  local iface
  iface="$(curl -fsS -b "${COOKIE_JAR}" "${QBIT_URL}/api/v2/app/preferences" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("current_network_interface",""))')"
  if [[ "${current}" != "${port}" || "${iface}" != "proton0" ]]; then
    log "Updating qBittorrent listen_port/iface ${current:-?}/${iface:-?} -> ${port}/proton0"
  else
    log "Renewed NAT-PMP mapping for port ${port} (re-applying proton0 bind)"
  fi
  qbit_set_listen_port "${port}"
  qbit_cap_upload_lightly
```

(Optional cleanup: fetch preferences once into a temp file and parse both fields to avoid two HTTP GETs.)

- [ ] **Step 4: Update file header comment**

Change the top comment from bridge-mode Docker port republish to host-net + `proton0` bind.

- [ ] **Step 5: Static verification on Mac**

Run:

```bash
grep -n 'current_network_interface\":\"proton0\"' scripts/proton-qbit-port-forward.sh
grep -n 'sync_env_bt_port' scripts/proton-qbit-port-forward.sh
! grep -n 'recreate_qbittorrent_if_needed' scripts/proton-qbit-port-forward.sh
bash -n scripts/proton-qbit-port-forward.sh
```

Expected: first two greps match; third grep exits 1 (no matches); `bash -n` exits 0.

- [ ] **Step 6: Commit (only if user asked)**

```bash
git add scripts/proton-qbit-port-forward.sh
git commit -m "$(cat <<'EOF'
Bind qBittorrent to proton0 and drop Docker BT port republish.

EOF
)"
```

---

### Task 4: Docs

**Files:**
- Modify: `docs/proton-vpn-g5.md`
- Modify: `docs/lan-storage.md` (short note near qBittorrent row)

**Interfaces:**
- Produces: operators know host net + `proton0` is the torrent kill switch; *arr must use `host.docker.internal`

- [ ] **Step 1: Add a “qBittorrent kill switch” section to `docs/proton-vpn-g5.md`**

Insert after the Day-to-day table (or near Related):

```markdown
## qBittorrent kill switch

qBittorrent uses **host networking** and binds BitTorrent to **`proton0`**.

- Proton up + `proton0` present → peers work; NAT-PMP port synced by `proton-qbit-port-forward.service`
- Proton down / no `proton0` → no torrent peers (WebUI on `:8080` / `qbittorrent.g5.lan` can still work)
- Caddy proxies to `host.docker.internal:8080` (not the old compose DNS name `qbittorrent`)
- Radarr/Sonarr/Lidarr download client host must be `host.docker.internal` (or `192.168.0.54`), port `8080`
```

- [ ] **Step 2: Update `docs/lan-storage.md` qBittorrent notes**

Where qBittorrent is listed, add that BT is bound to `proton0` (host net) and *arr should use `host.docker.internal:8080`.

- [ ] **Step 3: Commit (only if user asked)**

```bash
git add docs/proton-vpn-g5.md docs/lan-storage.md
git commit -m "$(cat <<'EOF'
Document qBittorrent host-net proton0 kill switch.

EOF
)"
```

---

### Task 5: Deploy and verify on G5

**Files:**
- No repo file changes; operate on G5 via SSH / existing deploy script

**Interfaces:**
- Consumes: Tasks 1–4 committed or at least synced to G5
- Produces: live stack matching the design; manual *arr host update

- [ ] **Step 1: Deploy media-stack (+ script) to G5**

From Mac repo root:

```bash
./deploy-to-g5.sh media-stack
```

Also ensure the updated script is on G5 (deploy rsync includes `scripts/`). If deploy scope skips scripts somehow, `scp` / full `./deploy-to-g5.sh` as needed.

Then on G5:

```bash
systemctl --user restart proton-qbit-port-forward.service
docker inspect qbittorrent --format '{{.HostConfig.NetworkMode}}'
```

Expected: `host`

- [ ] **Step 2: Confirm WebUI + Caddy**

```bash
curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8080/
# from a client with g5.lan trust:
# open https://qbittorrent.g5.lan
```

Expected: WebUI reachable; Caddy site loads.

- [ ] **Step 3: Confirm preferences**

On G5 (with WebUI password available):

```bash
# After port-forward service has logged a successful renew:
curl -fsS -b /tmp/q.cookies -c /tmp/q.cookies \
  --data-urlencode "username=admin" \
  --data-urlencode "password=$WEBUI_PASSWORD" \
  http://127.0.0.1:8080/api/v2/auth/login
curl -fsS -b /tmp/q.cookies http://127.0.0.1:8080/api/v2/app/preferences \
  | python3 -c 'import json,sys; p=json.load(sys.stdin); print(p.get("current_network_interface"), p.get("listen_port"))'
ip -br link show proton0
```

Expected: `proton0 <port>` and `proton0` link exists while VPN is connected.

- [ ] **Step 4: Update *arr download clients (manual once)**

In Radarr / Sonarr / Lidarr → Settings → Download Clients → qBittorrent:

- Host: `host.docker.internal` (or `192.168.0.54`)
- Port: `8080`

Test connection in each UI → success.

- [ ] **Step 5: Fail-closed check**

```bash
# On G5, with an active torrent:
./scripts/proton-vpn-fix.sh disconnect
# Watch torrent: peers should drop / no progress
ip -br link show proton0 || true
./scripts/proton-vpn-fix.sh connect
systemctl --user restart proton-qbit-port-forward.service
# Peers should return after tunnel + port map recover
```

Expected: no peers without `proton0`; peers return after reconnect.

- [ ] **Step 6: Commit any leftover doc/script fixes (only if user asked)**

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| `network_mode: host` | Task 1 |
| Remove compose BT/WebUI port maps | Task 1 |
| Caddy → `host.docker.internal:8080` | Task 2 |
| Script sets `proton0` bind | Task 3 |
| No Docker BT republish | Task 3 |
| Docs for kill switch + *arr host | Task 4 |
| Deploy + verify peers die without Proton | Task 5 |
| `qbittorrent.g5.lan` still works | Task 5 Step 2 |

## Plan self-review

- No TBD/placeholder steps
- `qbit_set_listen_port` / `sync_env_bt_port` names consistent across Task 3 and Task 5
- *arr automation left out of scope per spec (manual Step 4)
