# G5 LAN remote access

Host: `wmichelin-G5-5000` · IP: `192.168.0.54` · LAN only (no internet tunnel)

Credentials: `~/.config/lan-remote-password.txt` (mode 600)

## Bonjour / network browsing

This host advertises on the LAN as **`wmichelin-G5-5000.local`** plus:

- `_rfb._tcp` → Screen Sharing (“wmichelin-G5-5000 Remote Desktop (VNC)”)
- `_rdp._tcp` → Microsoft Remote Desktop
- `_workstation._tcp` → general host presence

It will **not** show up like an AirDrop/iPhone under Finder → Network unless you open Screen Sharing / Remote Desktop. Prefer connecting by name or IP.

## Prefer: live GNOME desktop (RDP)

Ubuntu’s GNOME Remote Desktop build has **no VNC**. Use RDP for the real desktop.

1. On the Mac, install **Microsoft Remote Desktop** (App Store / Microsoft).
2. Add PC → `192.168.0.54` or `wmichelin-G5-5000.local`
3. User / password from `lan-remote-password.txt` (`RDP_USER` / `RDP_PASSWORD`)
4. Connect. You should see the same GNOME session as the console.

## Alternate: macOS Screen Sharing (VNC)

TigerVNC listens on port **5900**. This is a **separate** minimal desktop (Kitty terminal), not a mirror of the console GNOME session.

1. Finder → **Go → Connect to Server** → `vnc://wmichelin-G5-5000.local` or `vnc://192.168.0.54:5900`
2. Or open **Screen Sharing** to that address
3. Password: `VNC_PASSWORD` from `lan-remote-password.txt` (VNC passwords are max 8 characters)

## Always-on notes

- Suspend/hibernate are masked; AC idle sleep is off; power profile is `performance`
- GDM auto-login + user linger keep graphical + user services after reboot
- After reboot: wait ~30s for desktop, then connect

## Firewall / IP

- UFW allows `5900/tcp` and `3389/tcp` **only** from `192.168.0.0/16`
- IP is currently DHCP (`192.168.0.54`). **Reserve that lease on the router** so the Mac always finds the same host (or set a static address on `enp3s0` later)

## Quick health check (on the G5)

```bash
systemctl --user is-active gnome-remote-desktop.service tigervnc.service
ss -ltnp | rg '3389|5900'
grdctl status   # RDP should show Username set (not empty)
```

## Display / primary monitor

RDP uses **extend** mode. While you are connected, `rdp-primary-monitor` makes the Mac’s virtual display (`Meta-*`) **primary** and puts every physical monitor (Acer ultrawide, etc.) in the **same logical monitor** so they **mirror** the RDP session.

Mutter can only mirror displays that share one resolution, so the watcher usually settles on **1920×1080** (set that in Windows App → Display for best results). On disconnect, the ultrawide returns to its normal preferred mode.
