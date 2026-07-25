# SSH access (G5)

Persistent OpenSSH on this host. LAN only via UFW.

| | |
|--|--|
| Host | `192.168.0.54` or `wmichelin-G5-5000.local` |
| Port | `22` |
| User | `wmichelin` |
| Auth | password (for now) or SSH key |

Password is your Ubuntu login password for `wmichelin`.

---

## Mac / Linux client — first login (password)

```bash
ssh wmichelin@192.168.0.54
```

Or with Bonjour:

```bash
ssh wmichelin@wmichelin-G5-5000.local
```

Accept the host key fingerprint when prompted (compare with the server’s ed25519 fingerprint if you want to be careful).

---

## Recommended: key-based login (no password each time)

**On the Mac** (Terminal):

```bash
# Create a key if you don't have one yet
ssh-keygen -t ed25519 -C "mac-to-g5" -f ~/.ssh/id_ed25519_g5

# Install public key on the G5 (asks for Ubuntu password once)
ssh-copy-id -i ~/.ssh/id_ed25519_g5.pub wmichelin@192.168.0.54
```

Optional `~/.ssh/config` on the Mac:

```
Host g5
  HostName 192.168.0.54
  User wmichelin
  IdentityFile ~/.ssh/id_ed25519_g5
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
