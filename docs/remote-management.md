# Remote Management

The administrative plane uses Tailscale as its private network layer. Do not expose SSH, Cockpit, or RDP through router port forwarding.

## Addresses

| Device | Tailscale address | MagicDNS name |
| --- | --- | --- |
| HP Server | `100.65.83.35` | `hp-server.tail7cb430.ts.net` |
| SilverBrick | `100.91.171.26` | `silverbrick` |

The addresses above were verified on 2026-07-25. Prefer MagicDNS names in client configuration, but retain the server's Tailscale IP in the recovery notes.

## SSH

Codex on SilverBrick uses a dedicated ED25519 key. The local Windows SSH config provides two aliases:

```sshconfig
Host hp-server
    HostName hp-server.tail7cb430.ts.net
    User butenko
    IdentityFile ~/.ssh/id_ed25519_hp_server
    IdentitiesOnly yes

Host hp-server-lan
    HostName 192.168.1.130
    User butenko
    IdentityFile ~/.ssh/id_ed25519_hp_server
    IdentitiesOnly yes
```

Use `ssh hp-server` normally. Use `ssh hp-server-lan` only as a recovery path while connected to the trusted home LAN. Tailscale SSH is not enabled; both aliases use the standard OpenSSH server and the same key-based authentication.

## Cockpit

Cockpit is installed from the Ubuntu repository and available at:

```text
https://100.65.83.35:9090
```

The socket override is installed at:

```text
/etc/systemd/system/cockpit.socket.d/listen.conf
```

It binds Cockpit only to `100.65.83.35:9090` and adds a dependency on `tailscaled.service`. A browser may show a certificate warning until Cockpit is configured with a certificate trusted by the client.

The reproducible source files are:

```text
scripts/configure-cockpit.sh
systemd/cockpit.socket.d/listen.conf
```

Install or repair the configuration from an interactive terminal:

```bash
cd /opt/homelab
./scripts/configure-cockpit.sh
```

Verification:

```bash
systemctl is-enabled cockpit.socket
systemctl is-active cockpit.socket
systemctl cat cockpit.socket
ss -ltn 'sport = :9090'
```

Expected result: HTTPS succeeds through the Tailscale address and fails through `192.168.1.130:9090`.

## GNOME Remote Login

The system GNOME Remote Desktop daemon provides an RDP login screen before a local desktop session exists. Connect from Windows with:

```powershell
mstsc.exe /v:hp-server.tail7cb430.ts.net:3389
```

Authentication has two stages:

1. Enter the dedicated RDP gateway username and password configured through `grdctl`.
2. At the Ubuntu login screen, enter the Linux account credentials for `butenko`.

Do not store either password in Git. Do not reuse the Ubuntu, Tailscale, Restic, or application passwords as the RDP gateway password.

The RDP TLS certificate and private key are runtime host state under:

```text
/var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop/
```

They must not be committed. Clients should compare and record the presented certificate fingerprint before trusting it.

## RDP network restriction

GNOME Remote Desktop listens on all host addresses and has no supported bind-address setting. The repository therefore provides a narrow nftables input chain:

```text
config/host/rdp-tailscale.nft
systemd/homelab-rdp-filter.service
systemd/gnome-remote-desktop.service.d/homelab-security.conf
```

`homelab-rdp-filter.service`:

- accepts TCP 3389 arriving on `tailscale0`;
- rejects TCP 3389 arriving on every other interface;
- does not change policy for SSH, Docker, Cockpit, or any other port;
- is required by `gnome-remote-desktop.service`, so RDP fails closed if the filter cannot start.

Install or intentionally rotate the RDP configuration from an interactive terminal:

```bash
cd /opt/homelab
./scripts/configure-rdp.sh
```

The script requires `sudo`, creates or reuses the TLS files, and prompts for dedicated RDP gateway credentials. It refuses to overwrite partial TLS state.

Verification:

```bash
systemctl is-enabled homelab-rdp-filter.service
systemctl is-active homelab-rdp-filter.service
systemctl is-enabled gnome-remote-desktop.service
systemctl is-active gnome-remote-desktop.service
sudo nft list table inet homelab_rdp
ss -ltn 'sport = :3389'
sudo grdctl --system status
```

From a Tailscale client, TCP 3389 must be reachable through the Tailscale address or MagicDNS name. The same port must be unreachable through `192.168.1.130`.

Microsoft RDP clients may automatically attach a local NTLM domain to a bare username. If the GNOME Remote Desktop journal reports `Could not find user in SAM database`, enter the dedicated gateway username as `.\\username` (for example `.\\lan`) and leave any separate domain field empty.

## Emergency disable

If RDP behavior is unexpected, disable the RDP daemon first while retaining SSH access:

```bash
sudo systemctl disable --now gnome-remote-desktop.service
```

After RDP is disabled, the dedicated filter can also be stopped if necessary:

```bash
sudo systemctl disable --now homelab-rdp-filter.service
```

Do not enable a global firewall or change SSH authentication as part of RDP troubleshooting without a separate review.
