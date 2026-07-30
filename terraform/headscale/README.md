# Headscale DNS (`hs.waltermichelin.com`)

Public nameservers for `waltermichelin.com` are **Namecheap** (`dns1/dns2.registrar-servers.com`), not DigitalOcean — even though Pantry Terraform also keeps a DO domain zone.

## Required: Namecheap A record

In Namecheap → Domain List → `waltermichelin.com` → **Advanced DNS**:

| Type | Host | Value | TTL |
|------|------|-------|-----|
| A Record | `hs` | `45.55.214.46` (pantry droplet) | Automatic |

Optional: enable **Dynamic DNS** on that host so `DDNS_PASSWORD` can update it later.

After the record exists and resolves:

```bash
# From Mac, once dig +short hs.waltermichelin.com returns the droplet IP:
ssh root@45.55.214.46 'certbot --nginx -d hs.waltermichelin.com --non-interactive --agree-tos -m wmichelin@gmail.com --redirect'
```

Or re-run `./scripts/deploy-headscale-to-droplet.sh` (skips certbot overwrite once the cert exists; if cert is still missing it will retry).

## Optional: DigitalOcean record

[`main.tf`](./main.tf) creates the same A record in the DO zone. That is **not** what the public internet queries today. Keep it so the DO zone stays in sync if nameservers are ever moved to DigitalOcean.
