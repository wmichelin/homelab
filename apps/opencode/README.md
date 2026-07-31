# OpenCode on G5

Self-hosted [OpenCode](https://opencode.ai) web UI at **https://opencode.g5.lan**, with **Cursor CLI** (`cursor-agent`) as the model backend via a local OpenAI-compatible proxy (`cursor-proxy.cjs`).

## Pieces

| Piece | Location |
|-------|----------|
| Config | `apps/opencode/opencode.json` |
| Compose | `apps/opencode/docker-compose.yml` (`g5-opencode` :4096, no auth) |
| Unit | `infra/systemd/user/opencode-web.service` → `docker compose up` |
| Proxy | Caddy reverse_proxy → `:4096` (HTTP/1.1, SSE flush; Tailscale-only) |
| DNS | Headscale `extra-records.json` |

> Do **not** put basic auth on OpenCode or Caddy for this site. Browser EventSource
> cannot send Authorization headers, which makes the Web UI look empty. Rely on
> Tailscale (`*.g5.lan`) as the access boundary.

## Install / update on G5

From the Mac (repo root):

```bash
./scripts/install-opencode-on-g5.sh
./deploy-to-g5.sh media-stack   # Caddy site
./scripts/deploy-headscale-to-droplet.sh   # MagicDNS for opencode.g5.lan
```

Prerequisites already on G5: `~/.local/bin/cursor-agent` logged in (`cursor-agent status`).

## Ops

```bash
ssh g5
systemctl --user status opencode-web
journalctl --user -u opencode-web -f
```

Default model: `cursor-acp/composer-2.5`. Change with `/models` in the UI.

## Opening a project

OpenCode Web’s picker only searches under the server home (`/home/wmichelin`). Fuzzy
search by short name often shows **No folders found** (upstream quirk).

**Do this:**

1. Click **Open project**
2. Type the full path: `/home/wmichelin/code/homelab` then Tab / Enter  
   (symlink also exists at `/home/wmichelin/Projects/homelab`)
3. Or paste: `https://opencode.g5.lan/?directory=/home/wmichelin/code/homelab`

Prefer **Chrome/Chromium on desktop** over Safari/iOS — OpenCode Web’s SSE stream is
flaky in Safari behind a reverse proxy.

The G5 tree is normally rsync’d from the Mac. OpenCode needs a `.git` worktree;
`git init` on G5 is enough for the Web UI to treat `/home/wmichelin/code/homelab`
as a project (or sync `.git` from the Mac checkout).
