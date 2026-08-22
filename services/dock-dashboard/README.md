# HPServer Dock Dashboard

Local FastAPI dashboard for the Realme GT Neo 3 dock panel. It exposes read-only
host status to trusted LAN/Tailscale clients and permits only explicitly
allowlisted actions after an authenticated HTTPS session.

## Security boundary

- `hp-dashboard` is an unprivileged system user and is not in the Docker group.
- A root collector writes a read-only JSON snapshot under `/run/hp-dashboard`.
- The web process can invoke only `/usr/local/libexec/hp-dashboard-action` through
  a dedicated sudoers entry. The helper accepts fixed action and target names.
- Login and actions require the Caddy-injected proxy token, a valid session and
  CSRF token. Direct LAN HTTP remains status-only.
- ADB automation accepts a single pinned USB serial and rejects network-style
  serials containing a colon.

## Install

```bash
cd /opt/homelab
make validate
sudo ./services/dock-dashboard/scripts/install.sh
sudo ./services/dock-dashboard/scripts/set-password.sh
./services/dock-dashboard/scripts/verify.sh
```

The installer creates a one-time password at
`/root/hp-dashboard-initial-password` without printing it. Setting a new
password removes that file.

## Phone setup

Install Fully Kiosk Browser, enable USB debugging, connect the phone, accept the
server RSA key and verify that `adb devices` reports `device`. Then run:

```bash
sudo ./services/dock-dashboard/scripts/setup-phone.sh
```

In Fully Kiosk configure the dashboard as Start URL, enable Keep Screen On,
portrait orientation, Launch on Boot and reload on network reconnect. Keep
Wireless Debugging and Fully Cloud Remote Admin disabled.
