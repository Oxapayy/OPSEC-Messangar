# OPSEC-Messangar — full VPS setup

Copy-paste guide to go from a **freshly reinstalled Ubuntu 24.04 LTS** VPS
to a hardened server running the OPSEC backend behind a Tor v3 hidden
service.

Assumptions:

- Fresh Ubuntu 24.04 (Debian 12 works too; steps almost identical).
- You have a public IPv4/IPv6 and can SSH in as `root`.
- You have an SSH keypair on your **laptop** (the machine you'll admin from).
  If not: on your laptop run `ssh-keygen -t ed25519 -C "opsec-admin"`.

Everywhere you see `REPLACE_...` you need to substitute your own value.

Run the commands in order. Sections marked **(on your laptop)** are local;
everything else is on the VPS.

---

## 0. Get the SSH key onto the server (on your laptop)

```bash
# Print your public key. Copy the whole line.
cat ~/.ssh/id_ed25519.pub

# Push it to the server (uses password auth once, then never again).
ssh-copy-id root@REPLACE_SERVER_IP
```

If `ssh-copy-id` is unavailable, do the equivalent manually:
`ssh root@IP "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"`
and paste the key when it waits for input.

Confirm key auth works: `ssh root@REPLACE_SERVER_IP` should let you in
without a password.

---

## 1. First login + full system update

```bash
ssh root@REPLACE_SERVER_IP

# Kill any interactive prompts that new packages may throw.
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y full-upgrade
apt-get -y autoremove
apt-get -y install \
    curl wget git ca-certificates gnupg lsb-release \
    ufw fail2ban unattended-upgrades apt-listchanges \
    vim htop tmux jq

# Reboot if the kernel or systemd got updated.
[ -f /var/run/reboot-required ] && reboot
# (SSH back in after ~30s if you rebooted.)
```

## 2. Create a non-root admin user

```bash
adduser --disabled-password --gecos "" oxapayy      # your admin username
usermod -aG sudo oxapayy

# Passwordless sudo for that user (SSH-key auth already gates access).
echo 'oxapayy ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-oxapayy
chmod 440 /etc/sudoers.d/90-oxapayy

# Give the new user your SSH key.
mkdir -p /home/oxapayy/.ssh
cp /root/.ssh/authorized_keys /home/oxapayy/.ssh/
chown -R oxapayy:oxapayy /home/oxapayy/.ssh
chmod 700 /home/oxapayy/.ssh
chmod 600 /home/oxapayy/.ssh/authorized_keys
```

From another terminal on your laptop, confirm you can log in as the new
user before touching root:

```bash
ssh oxapayy@REPLACE_SERVER_IP    # should succeed
```

## 3. Harden SSH

Still logged in as root on the server:

```bash
cat > /etc/ssh/sshd_config.d/99-opsec.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
MaxAuthTries 3
LoginGraceTime 20
ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers oxapayy
EOF

systemctl reload ssh
```

Test in a **new** terminal:

```bash
ssh oxapayy@REPLACE_SERVER_IP    # still works
ssh root@REPLACE_SERVER_IP       # must now fail with "Permission denied"
```

If either result is wrong, fix it before you close your original root
session — otherwise you can lock yourself out.

## 4. Firewall (ufw) + Fail2ban

```bash
# Default: deny inbound, allow outbound.
ufw default deny incoming
ufw default allow outgoing

# SSH only. Nothing else needs to be public — Tor exposes the backend.
ufw allow 22/tcp
ufw --force enable
ufw status verbose

# Fail2ban with sensible SSH defaults.
cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled  = true
port     = ssh
backend  = systemd
maxretry = 4
findtime = 10m
bantime  = 1h
EOF

systemctl enable --now fail2ban
fail2ban-client status
```

## 5. Unattended security updates

```bash
dpkg-reconfigure -f noninteractive unattended-upgrades

cat > /etc/apt/apt.conf.d/51opsec-unattended <<'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:00";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

systemctl enable --now unattended-upgrades
systemctl status unattended-upgrades --no-pager | head
```

## 6. Install Tor

The Debian repo ships Tor but often lags. Use the official Tor Project
repo for current builds.

```bash
install -m 0755 -d /etc/apt/keyrings

# Import Tor Project signing key.
curl -fsSL https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc \
  | gpg --dearmor -o /etc/apt/keyrings/tor-archive-keyring.gpg

CODENAME=$(lsb_release -cs)
cat > /etc/apt/sources.list.d/tor.list <<EOF
deb [signed-by=/etc/apt/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org $CODENAME main
deb-src [signed-by=/etc/apt/keyrings/tor-archive-keyring.gpg] https://deb.torproject.org/torproject.org $CODENAME main
EOF

apt-get update
apt-get -y install tor deb.torproject.org-keyring

systemctl enable --now tor
systemctl status tor --no-pager | head
```

## 7. Install Go (for building the backend)

```bash
GO_VERSION=1.22.7
cd /tmp
wget -q "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz"
rm -rf /usr/local/go
tar -C /usr/local -xzf "go${GO_VERSION}.linux-amd64.tar.gz"

# Make `go` available in every shell.
echo 'export PATH=$PATH:/usr/local/go/bin' > /etc/profile.d/go.sh
export PATH=$PATH:/usr/local/go/bin
go version
```

## 8. Deploy the backend

Create a dedicated user and directories:

```bash
adduser --system --group --home /var/lib/opsec-backend --shell /usr/sbin/nologin opsec
install -d -o opsec -g opsec -m 0750 /var/lib/opsec-backend
install -d -o opsec -g opsec -m 0750 /var/lib/opsec-backend/uploads
install -d -o root  -g root  -m 0755 /opt/opsec-backend
```

Fetch the source and build:

```bash
cd /opt
git clone https://github.com/oxapayy/OPSEC-Messangar.git src
cd src/backend
go mod tidy
CGO_ENABLED=0 go build -trimpath -ldflags '-s -w' -o /opt/opsec-backend/opsec-backend .

# Install the systemd unit.
cp systemd/opsec-backend.service /etc/systemd/system/opsec-backend.service
systemctl daemon-reload
systemctl enable --now opsec-backend
systemctl status opsec-backend --no-pager | head -20
```

Health check locally:

```bash
curl -s http://127.0.0.1:8080/healthz
# → ok
```

## 9. Wire up the Tor hidden service

```bash
# Append (or copy) the OPSEC snippet into torrc.
cat /opt/src/backend/systemd/torrc.opsec >> /etc/tor/torrc

# Restart Tor so it creates the hidden service dir + keypair.
systemctl restart tor

# The .onion hostname lives here:
sleep 2
cat /var/lib/tor/opsec/hostname
```

**Copy that .onion hostname.** It is your backend's public address. Save
it — you'll paste it into the iOS app's
`ios/OPSECMessenger/Config/BackendConfig.swift`:

```swift
static let onionHost = "your-hostname.onion"
static let apiPort   = 80
static let wsPort    = 80
```

The hidden service maps `HiddenServicePort 80 → 127.0.0.1:8080`, so
requests to `http://<hostname>.onion/` land on the Go backend.

## 10. End-to-end verification

From your laptop, using the Tor Browser or `torsocks`:

```bash
# Install torsocks locally: apt install torsocks   (or brew install torsocks)
torsocks curl -s http://REPLACE_ONION_HOSTNAME.onion/healthz
# → ok

# Register a test account.
torsocks curl -s -X POST -H "Content-Type: application/json" \
  -d '{"auth_key":"aabb...(64 hex chars)","numeric_id":123456789012345678}' \
  http://REPLACE_ONION_HOSTNAME.onion/v1/register
# → {"session_token":"..."}
```

Then in the iOS app: fill `onionHost` in `BackendConfig.swift`, set
`OPSEC_ENABLE_TOR=1` in the scheme's environment (after adding
`Tor.framework` via SwiftPM), and register a real account. The username
you pick will be visible for friends to add.

## 11. Backups

At minimum, back up:

- `/var/lib/opsec-backend/opsec.db` — accounts, sessions, envelopes.
- `/var/lib/tor/opsec/` — the hidden service keypair. **Lose this and
  your .onion hostname changes.** Every existing client would then be
  unable to reach the backend.

Simple nightly rsync to another host:

```bash
# On the VPS, as root:
cat > /etc/systemd/system/opsec-backup.service <<'EOF'
[Unit]
Description=OPSEC nightly backup
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/bin/rsync -aH --delete \
    /var/lib/opsec-backend/ /var/lib/tor/opsec/ \
    REPLACE_BACKUP_USER@REPLACE_BACKUP_HOST:/backups/opsec/
EOF

cat > /etc/systemd/system/opsec-backup.timer <<'EOF'
[Unit]
Description=Nightly OPSEC backup

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl enable --now opsec-backup.timer
```

## 12. Common operations

| task                            | command                                            |
| ------------------------------- | -------------------------------------------------- |
| Tail backend logs               | `journalctl -u opsec-backend -f`                   |
| Tail Tor logs                   | `journalctl -u tor@default -f`                     |
| Restart backend                 | `sudo systemctl restart opsec-backend`             |
| Reload firewall                 | `sudo ufw reload`                                  |
| Update the backend from git     | `cd /opt/src && sudo git pull && cd backend && sudo -u opsec CGO_ENABLED=0 go build -o /opt/opsec-backend/opsec-backend . && sudo systemctl restart opsec-backend` |
| List Fail2ban bans              | `sudo fail2ban-client status sshd`                 |
| Rotate .onion (destructive!)    | `sudo systemctl stop tor && sudo rm -rf /var/lib/tor/opsec && sudo systemctl start tor && cat /var/lib/tor/opsec/hostname` |

## 13. What still needs configuration outside this guide

- **APNs push credentials** — to actually wake iPhones over Apple Push,
  you need an APNs auth key (`.p8`) from your Apple Developer account.
  The backend stores the tokens; hooking up delivery is a `TODO(backend)`
  in `handlers.go`.
- **TURN server for calls** — WebRTC needs a TURN server for peers behind
  NATs. `coturn` on the same VPS works; expose only on the loopback and
  proxy through the same hidden service (adds another `HiddenServicePort`).
- **Real end-to-end encryption** — the client currently uses a
  placeholder symmetric key; swap in the Signal Protocol / libsignal
  before you tell anyone this is secure.

You are done. Backend is running, only SSH is exposed on the public
internet, and every client hits you through Tor.
