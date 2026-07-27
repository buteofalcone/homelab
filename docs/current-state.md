# Current State

Last verified: **2026-07-27** through SSH from SilverBrick.

This document records observed runtime state. Target architecture and future work are documented separately in `docs/architecture.md` and `TASKS.md`.

## Host and storage

| Item | Observed value |
| --- | --- |
| Hardware | HP Compaq Elite 8300 SFF, Intel Core i5-3570, 16 GB RAM |
| Operating system | Ubuntu 26.04 LTS |
| Kernel | `7.0.0-28-generic` |
| Hostname | `hp-server` |
| Administrative user | `butenko` |
| LAN address | `192.168.1.130` |
| Tailscale address | `100.65.83.35` |
| System SSD | `/dev/sda2`, 234 GB, 30 GB used |
| Data HDD | `/dev/sdb2`, ext4, mounted read-write at `/srv/storage`, 458 GB, 1.1 GB used |

Application state and databases are under `/srv/appdata`. User files are under `/srv/storage`. Deployment must stop if `findmnt /srv/storage` does not confirm the dedicated mount.

## Repository

| Item | Observed value |
| --- | --- |
| Path | `/opt/homelab` |
| Remote | `git@github.com:buteofalcone/homelab.git` |
| Branch | `feature/base-management-stack` |
| Audit baseline | `dea5af8` (`Add trusted HTTPS for private family services`) |
| Worktree | Clean and synchronized with `origin/feature/base-management-stack` |

## Running services

The following Compose services were running:

- Management and routing: `homepage`, `homepage-docker-proxy`, `portainer`, `beszel`, `beszel-agent`, `uptime-kuma`, `caddy`.
- Nextcloud: `nextcloud`, `nextcloud-cron`, `nextcloud-db`, `nextcloud-redis`.
- Immich: `immich-server`, `immich-machine-learning`, `immich-database`, `immich-redis`.
- Media: `jellyfin`.
- Backup target: `timemachine`, with separate `TimeMachine-A1502` and `TimeMachine-A1466` shares.

`watchtower` is declared but intentionally not running. Stateful application updates remain manual.

Host services are also active: Docker, Tailscale, OpenSSH, Cockpit, GNOME Remote Desktop, the RDP nftables filter, the backup timer, and the health timer.

## Access and TLS

`butenko.online` is the production domain. Cloudflare DNS-only records point the service names at `100.65.83.35`. Caddy uses the Cloudflare DNS challenge and Let's Encrypt certificates. Clients need access to the same Tailscale network, but do not need custom DNS or a private CA certificate.

Working service names:

```text
home.butenko.online
portainer.butenko.online
beszel.butenko.online
uptime.butenko.online
nextcloud.butenko.online
immich.butenko.online
jellyfin.butenko.online
```

Cockpit listens only on `100.65.83.35:9090`. RDP listens on TCP 3389, with the repository-managed nftables rule allowing it only through `tailscale0`. SSH over Tailscale is working. No router port forwarding is required or intended.

Direct application ports currently listen on all host interfaces for trusted-LAN setup and recovery. This exposure is documented but still requires a deliberate security review.

Time Machine SMB listens on TCP 445 for trusted-LAN and Tailscale clients. Connectivity through the server's Tailscale address was verified from SilverBrick. Avahi publishes `hp-server Time Machine` through Bonjour for local-LAN discovery.

## Monitoring

- Beszel Hub and Agent are running.
- Uptime Kuma has application, internet, storage, SMART, and backup monitoring configured.
- Telegram notifications are configured in Uptime Kuma runtime state.
- `homelab-health.timer` runs every 15 minutes; its most recent run completed successfully on 2026-07-27.
- Both disks passed the recorded SMART baseline. The temporary 500 GB HDD has high power-on hours and must not become the only copy of important data.
- Docker-based Samba Time Machine is running with separate accounts, directories, and 100 GB test limits for A1502 and A1466. MacBook A1466 completed its first small test backup on 2026-07-27, using approximately 4.6 GB. A1502 remains untested.

## Backup

`homelab-backup.timer` is active and the most recent job completed successfully on 2026-07-27. The installed schedule is 03:30 with up to 10 minutes of randomized delay; this version has now been captured in Git.

The job creates logical PostgreSQL dumps and stores a local Restic snapshot on the same HDD. This protects SSD application state from an SSD failure, but does not protect against failure, loss, or corruption of the HDD itself.

Snapshot readability and a complete application restore have not yet been independently tested. Until that test succeeds and an external/off-site copy exists, disaster recovery is **not complete**.

## Runtime state that does not belong in Git

The following are deliberately excluded from Git:

- passwords, tokens, RDP credentials, and the Restic password;
- application databases and user accounts;
- Nextcloud files, Immich photos, and Jellyfin media;
- Uptime Kuma monitors, history, and Telegram settings;
- Portainer, Beszel, Nextcloud, Immich, Jellyfin, and Caddy runtime state;
- Tailscale device identity and enrollment state.

Git must define how these items are provisioned or restored. Backup and restore, rather than source control, preserve their values.

## Validation results

On 2026-07-27:

- `make validate` passed.
- `make doctor` passed before this audit.
- all expected containers except intentionally stopped Watchtower were running;
- Homepage runtime configuration matched the repository byte-for-byte;
- health, RDP, Cockpit, and GNOME Remote Desktop systemd configuration matched Git;
- backup systemd drift was found and captured in Git without changing the running server.

No container, firewall rule, package, mount, database, application data, or secret was changed during this audit.
