# Optional Unraid-like follow-ups (Ubuntu stays)

Out of scope for the LAN remote-desktop pass. Add later if you want NAS/app/VM features without reinstalling.

| Goal | Free approach on this Ubuntu box |
|------|----------------------------------|
| Docker apps / “Community Apps” feel | Docker Engine + Portainer (or Compose stacks) |
| File shares (SMB for Mac) | Samba export of `/run/media/wmichelin/DATA` (or remount stably under `/mnt/data`) |
| VMs | KVM/QEMU + virt-manager or Cockpit (`/dev/kvm` already present) |
| Full NAS OS | TrueNAS SCALE / OpenMediaVault — would **replace** Ubuntu |
| Hypervisor-first | Proxmox VE — would **replace** Ubuntu |

Unraid itself is paid after trial. Prefer Docker + Samba + KVM on Ubuntu unless you want a dedicated NAS/hypervisor OS.

Suggested next installs when ready:

```bash
# Docker + Portainer (example)
# sudo apt install docker.io docker-compose-v2
# sudo usermod -aG docker "$USER"
# then run Portainer CE container

# Samba share of DATA disk (after stable mount point)
# sudo apt install samba
# configure /etc/samba/smb.conf + smbpasswd

# KVM desktop tooling
# sudo apt install qemu-kvm libvirt-daemon-system virt-manager
```
