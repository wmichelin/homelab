# FinTV Jellyfin Wiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install FinTV 0.0.1.3 on G5 Jellyfin 10.11.11 and wire Live TV (M3U + XMLTV) so channels can be added later in the FinTV UI.

**Architecture:** Pin the FinTV plugin zip into Jellyfin’s `plugins/FinTV/` config volume on G5, restart the container, set Public Base URL to the LAN HTTP address, then register FinTV’s loopback M3U/XMLTV endpoints as Jellyfin Live TV sources. Document the pin and URLs in `docs/lan-storage.md`.

**Tech Stack:** Jellyfin 10.11.11 (Docker), FinTV 0.0.1.3, SSH to G5 (`ssh g5`), curl, `docs/lan-storage.md`

## Global Constraints

- Stay on Jellyfin **10.11.11** — do not upgrade to 12.x
- Install FinTV **0.0.1.3** only (`targetAbi` 10.11) — do not install 0.0.2.x
- Public Base URL: `http://192.168.0.54:8096`
- Tuner URL: `http://127.0.0.1:8096/FinTV/iptv/channels.m3u`
- Guide URL: `http://127.0.0.1:8096/FinTV/iptv/epg.xml`
- No Docker socket / WeatherStar / channels / commercials
- No compose image changes
- Do not commit unless the user asks
- Spec: `docs/superpowers/specs/2026-08-04-fintv-jellyfin-design.md`

---

## File map

| File / path | Role |
|-------------|------|
| G5: `~/code/homelab/apps/media-stack/config/jellyfin/plugins/FinTV/` | Extracted FinTV 0.0.1.3 plugin (runtime; not committed) |
| G5 Jellyfin Live TV settings | M3U tuner + XMLTV provider (in Jellyfin DB/config) |
| `docs/lan-storage.md` | Operator note: version pin + Live TV URLs |
| `docs/superpowers/specs/2026-08-04-fintv-jellyfin-design.md` | Spec (already written) |

Plugin binaries live under the G5 config volume (often root-owned). They are **not** committed to git.

---

### Task 1: Install FinTV 0.0.1.3 on G5

**Files:**
- Create on G5: `~/code/homelab/apps/media-stack/config/jellyfin/plugins/FinTV/` (extracted zip contents)

**Interfaces:**
- Consumes: running `jellyfin` container; SSH host `g5`
- Produces: FinTV plugin loaded after restart; endpoints under `/FinTV/iptv/`

- [x] **Step 1: Confirm Jellyfin version is still 10.11.x**

Run:

```bash
ssh g5 'curl -s http://127.0.0.1:8096/System/Info/Public'
```

Expected: JSON with `"Version":"10.11.11"` (or another `10.11.x`). If version is `12.x`, **stop** and re-read the spec — do not install 0.0.1.3 blindly.

- [x] **Step 2: Download and extract the pinned zip on G5**

Run:

```bash
ssh g5 'bash -s' <<'EOF'
set -euo pipefail
PLUGINS="$HOME/code/homelab/apps/media-stack/config/jellyfin/plugins"
ZIP_URL="https://github.com/binarygeek119/FinTV/releases/download/v0.0.1.3/fintv_0.0.1.3.zip"
TMP="$(mktemp -d)"
cd "$TMP"
curl -fsSL -o fintv_0.0.1.3.zip "$ZIP_URL"
# plugins dir is typically root-owned; use sudo for write
sudo mkdir -p "$PLUGINS/FinTV"
sudo rm -rf "$PLUGINS/FinTV"/*
sudo unzip -o fintv_0.0.1.3.zip -d "$PLUGINS/FinTV"
# Some zips nest a single top-level folder — flatten if needed
if [ "$(sudo find "$PLUGINS/FinTV" -maxdepth 1 -type f | wc -l)" -eq 0 ] \
   && [ "$(sudo find "$PLUGINS/FinTV" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1 ]; then
  INNER="$(sudo find "$PLUGINS/FinTV" -mindepth 1 -maxdepth 1 -type d)"
  sudo sh -c "shopt -s dotglob && mv \"$INNER\"/* \"$PLUGINS/FinTV\"/ && rmdir \"$INNER\""
fi
sudo find "$PLUGINS/FinTV" -maxdepth 2 -type f | head -20
rm -rf "$TMP"
EOF
```

Expected: listing includes a `.dll` (e.g. `Jellyfin.Plugin.FinTV.dll` or similar) and `meta.json` / manifest files under `plugins/FinTV/`.

- [x] **Step 3: Restart Jellyfin and wait until it answers**

Run:

```bash
ssh g5 'docker restart jellyfin && for i in $(seq 1 60); do curl -sf http://127.0.0.1:8096/System/Info/Public >/dev/null && echo UP && break; sleep 2; done'
```

Expected: `UP` within ~2 minutes. First start after plugin install may take longer than a normal restart.

- [x] **Step 4: Verify FinTV endpoints respond**

Run:

```bash
ssh g5 'curl -sS -o /tmp/fintv-m3u -w "m3u:%{http_code}\n" http://127.0.0.1:8096/FinTV/iptv/channels.m3u; curl -sS -o /tmp/fintv-epg -w "epg:%{http_code}\n" http://127.0.0.1:8096/FinTV/iptv/epg.xml; head -c 200 /tmp/fintv-m3u; echo; head -c 200 /tmp/fintv-epg; echo'
```

Expected: `m3u:200` and `epg:200`. Bodies may be empty/minimal (no channels yet) — that is OK.

If HTTP 404: check `docker logs jellyfin --tail 80` for plugin load errors (wrong ABI, bad extract path).

- [x] **Step 5: Confirm plugin in Jellyfin (optional UI check)**

Open `https://jellyfin.g5.lan` (or `http://192.168.0.54:8096`) → Dashboard → Plugins → Installed → FinTV shows **0.0.1.3**.

No git commit for this task (runtime files on G5 only).

---

### Task 2: Wire Public Base URL + Live TV tuner/guide

**Files:**
- Jellyfin FinTV plugin configuration (via Dashboard)
- Jellyfin Live TV tuner + listing provider (via Dashboard)

**Interfaces:**
- Consumes: FinTV endpoints from Task 1
- Produces: Live TV M3U tuner + XMLTV provider pointing at FinTV

- [x] **Step 1: Set FinTV Public Base URL**

In Jellyfin Dashboard → **Plugins → FinTV** → **Live TV Setup** (or equivalent Settings tab):

- Set **Public Base URL** to exactly: `http://192.168.0.54:8096`
- Save

If the UI only shows setup helper URLs and no editable field, set whatever “Base URL” / “Public URL” field FinTV 0.0.1.3 exposes to that value, then Save.

- [x] **Step 2: Add M3U tuner**

Dashboard → **Live TV** → Tuner Devices → **+** / Add:

| Field | Value |
|-------|--------|
| Type | M3U Tuner |
| URL | `http://127.0.0.1:8096/FinTV/iptv/channels.m3u` |

Leave other options at defaults unless the form requires a name — use `FinTV` if needed. Save.

- [x] **Step 3: Add XMLTV guide provider**

Dashboard → **Live TV** → TV Guide Data Providers → **+** / Add:

| Field | Value |
|-------|--------|
| Type | XMLTV |
| URL | `http://127.0.0.1:8096/FinTV/iptv/epg.xml` |

Save. If the UI asks to enable/associate with a tuner, enable it for the FinTV M3U tuner.

- [x] **Step 4: Refresh Channels then Guide**

Dashboard → **Scheduled Tasks** (or Live TV actions):

1. Run **Refresh Guide Data** / **Refresh Channels** for Live TV (name may be **Refresh Channels**).
2. After it completes, run **Refresh Guide**.

Expected: both tasks complete without error. With zero FinTV channels, channel count may be 0 — still success for this scope.

- [x] **Step 5: API sanity (auth)**

From the Mac, using credentials in `secrets/homelab.env` (`JELLYFIN_URL`, `JELLYFIN_USER`, `JELLYFIN_PASSWORD`):

```bash
set -a && source "$HOME/code/homelab/secrets/homelab.env" && set +a
TOKEN=$(curl -sS -X POST "$JELLYFIN_URL/Users/AuthenticateByName" \
  -H 'Content-Type: application/json' \
  -H 'X-Emby-Authorization: MediaBrowser Client="homelab", Device="plan", DeviceId="fintv-plan", Version="1.0.0"' \
  -d "{\"Username\":\"$JELLYFIN_USER\",\"Pw\":\"$JELLYFIN_PASSWORD\"}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["AccessToken"])')
curl -sS -H "X-Emby-Authorization: MediaBrowser Client=\"homelab\", Device=\"plan\", DeviceId=\"fintv-plan\", Version=\"1.0.0\", Token=\"$TOKEN\"" \
  "$JELLYFIN_URL/LiveTv/Tuners" | python3 -m json.tool | head -80
```

Expected: JSON listing includes a tuner whose URL contains `FinTV/iptv/channels.m3u`.

No git commit for this task (server config only).

---

### Task 3: Document in lan-storage.md

**Files:**
- Modify: `docs/lan-storage.md` (Media apps section, after the app table / compose blurb)

**Interfaces:**
- Consumes: final URLs and version pin from Tasks 1–2
- Produces: operator-facing note in the LAN storage guide

- [x] **Step 1: Insert FinTV subsection**

After the Downloads bullets under Media apps (before `### First-run checklist`), add:

```markdown
### FinTV (virtual Live TV)

Pinned on G5 Jellyfin **10.11.11**: FinTV **0.0.1.3** (ABI 10.11 — do not install 0.0.2.x until Jellyfin 12).

| Setting | Value |
|---------|--------|
| Public Base URL | `http://192.168.0.54:8096` |
| M3U tuner | `http://127.0.0.1:8096/FinTV/iptv/channels.m3u` |
| XMLTV guide | `http://127.0.0.1:8096/FinTV/iptv/epg.xml` |

Create channels/lineups later in **Dashboard → Plugins → FinTV**. WeatherStar needs Docker socket + Playwright — not enabled yet.
```

- [x] **Step 2: Skim for consistency**

Confirm the Jellyfin row in the Media apps table is unchanged and still points at `https://jellyfin.g5.lan` / `http://192.168.0.54:8096`.

- [x] **Step 3: Commit (only if user asked to commit)**

```bash
git add docs/lan-storage.md
git commit -m "$(cat <<'EOF'
Document FinTV 0.0.1.3 Live TV wiring on G5 Jellyfin.

EOF
)"
```

---

### Task 4: End-to-end verification

**Files:** none (checks only)

**Interfaces:**
- Consumes: Tasks 1–3 complete
- Produces: pass/fail against spec success checks

- [x] **Step 1: Version + plugin endpoints**

```bash
ssh g5 'curl -s http://127.0.0.1:8096/System/Info/Public | python3 -c "import sys,json; print(json.load(sys.stdin)[\"Version\"])"; curl -sS -o /dev/null -w "m3u:%{http_code} epg:" http://127.0.0.1:8096/FinTV/iptv/channels.m3u; curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8096/FinTV/iptv/epg.xml'
```

Expected: `10.11.11` (or `10.11.x`) and `m3u:200 epg:200`.

- [x] **Step 2: Library still works**

Open Jellyfin → play a short clip from Movies or TV. Expected: playback starts normally after the plugin install restart.

- [x] **Step 3: Rollback note (do not run unless failing)**

If FinTV breaks Jellyfin startup:

```bash
ssh g5 'sudo mv ~/code/homelab/apps/media-stack/config/jellyfin/plugins/FinTV ~/code/homelab/apps/media-stack/config/jellyfin/plugins/FinTV.bak && docker restart jellyfin'
```

Then remove the FinTV tuner/guide from Live TV in the Dashboard.

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Install FinTV 0.0.1.3 into plugins/FinTV | Task 1 |
| Restart Jellyfin; plugin installed | Task 1 |
| Public Base URL `http://192.168.0.54:8096` | Task 2 |
| M3U + XMLTV URLs on loopback | Task 2 |
| Refresh Channels then Guide | Task 2 |
| Document in `docs/lan-storage.md` | Task 3 |
| Success checks (version, 200s, Live TV, library) | Task 4 |
| No weather / docker.sock / channels | Global Constraints |
| Rollback path | Task 4 Step 3 |
