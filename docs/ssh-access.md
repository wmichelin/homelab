# SSH access (G5)

Persistent OpenSSH on this host. LAN only via UFW.

| | |
|--|--|
| Host | `g5.local` (preferred) · `192.168.0.54` · legacy `wmichelin-G5-5000.local` until renamed |
| Port | `22` |
| User | `wmichelin` |
| Auth | SSH key (`~/.ssh/id_ed25519_g5`) |

Set / refresh the short name on the G5:

```bash
sudo ~/code/homelab/scripts/set-g5-hostname.sh
# → static hostname g5, Avahi publishes g5.local
```

---

## Mac / Linux client — first login (password)

```bash
ssh wmichelin@192.168.0.54
```

Or with Bonjour (after hostname script):

```bash
ssh wmichelin@g5.local
```

Accept the host key fingerprint when prompted (compare with the server’s ed25519 fingerprint if you want to be careful).

---

## Recommended: key-based login (no password each time)

**On the Mac** (Terminal):

```bash
# Create a key if you don't have one yet
ssh-keygen -t ed25519 -C "mac-to-g5" -f ~/.ssh/id_ed25519_g5

# Install public key on the G5 (asks for Ubuntu password once)
ssh-copy-id -i ~/.ssh/id_ed25519_g5.pub wmichelin@g5.local
```

Optional `~/.ssh/config` on the Mac:

```
Host g5 g5.local
  HostName g5.local
  User wmichelin
  IdentityFile ~/.ssh/id_ed25519_g5
  AddressFamily inet
```

Then:

```bash
ssh g5
```

---

## After keys work (optional hardening)

On the G5, edit `/etc/ssh/sshd_config.d/99-g5-lan.conf` and set:

```
PasswordAuthentication no
```

Then:

```bash
sudo systemctl reload ssh
```

---

## Windows client

Install [Windows OpenSSH Client](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse) or use PuTTY / Windows Terminal:

```text
ssh wmichelin@192.168.0.54
```

---

## Server ops

```bash
sudo systemctl status ssh.socket
sudo ufw status | grep 22
```

Config drop-in: `/etc/ssh/sshd_config.d/99-g5-lan.conf`
