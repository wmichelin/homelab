# G5 LAN subdomains (`*.g5.lan`)

> **Moved:** hostname resolution is Tailscale/Headscale MagicDNS with private-CA HTTPS.
> See **[headscale-tailscale.md](./headscale-tailscale.md)**.

dnsmasq / eero Custom DNS are no longer used for `*.g5.lan`. Install the Tailscale
app and point it at `https://hs.waltermichelin.com`.
