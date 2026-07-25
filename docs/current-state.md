# Current State

Last verified: **2026-07-25** through SSH from SilverBrick.

This file records observed state. It is not a declaration that every installed component is fully configured, secure, backed up, or tested.

## Host

| Item | Observed value |
| --- | --- |
| Hostname | `hp-server` |
| Hardware | HP Compaq Elite 8300 SFF |
| Operating system | Ubuntu 26.04 LTS |
| Kernel | `7.0.0-28-generic` |
| Architecture | `x86-64` |
| Administrative user | `butenko` |
| LAN address | `192.168.1.130` |

The hardware-reported chassis is **SFF**, which differs from earlier notes describing a CMT chassis.

## Repository

| Item | Observed value |
| --- | --- |
| Path | `/opt/homelab` |
| Remote | `git@github.com:buteofalcone/homelab.git` |
| Branch | `feature/base-management-stack` |
| Audit commit | `136fa8c` (`Expand Immich deployment and backup documentation`) |
| Worktree at start of audit | Clean |

`git pull --ff-only` reported that the branch was already up to date.

## Storage

| Path | Device / purpose | Observed state |
| --- | --- | --- |
| `/` | `/dev/sda2`, Ubuntu and SSD application state | 234 GB total, 27 GB used, 196 GB available |
| `/srv/appdata` | Service state, caches, and databases | Exists, owned by `butenko:butenko` |
| `/srv/storage` | `/dev/sdb2`, ext4 persistent data mount | Mounted read-write; 458 GB total, 365 MB used, 434 GB available |
| `/srv/storage/files` | User and Nextcloud files | Exists |
| `/srv/storage/photos` | Immich-managed photos | Exists |
| `/srv/storage/media` | Jellyfin media | Exists |
| `/srv/storage/backups` | Local backup repository | Exists |
| `/srv/storage/restores` | Restore targets | Exists, owned by `root:root` |

Deployment must stop if `findmnt /srv/storage` does not confirm the dedicated mount.

## Running Compose services

The following containers were running during the audit:

- Management and routing: `homepage`, `homepage-docker-proxy`, `portainer`, `beszel`, `uptime-kuma`, `caddy`.
- Nextcloud: `nextcloud`, `nextcloud-cron`, `nextcloud-db`, `nextcloud-redis`.
- Immich: `immich-server`, `immich-machine-learning`, `immich-database`, `immich-redis` (Valkey image).
- Media: `jellyfin`.

Containers reporting Docker health checks were healthy. `make doctor` also confirmed HTTP/HTTPS reachability for Homepage, Beszel, Uptime Kuma, Portainer, Caddy, Nextcloud, Immich, and Jellyfin.

Watchtower is included in `compose.yaml`, but no Watchtower container was running. This discrepancy should be investigated without automatically starting or updating services.

The optional Beszel agent was not observed as a running container; the Beszel hub itself was running.

## Service access

Primary local HTTPS endpoints use Caddy's local certificate authority:

```text
https://home.home.arpa
https://portainer.home.arpa
https://beszel.home.arpa
https://uptime.home.arpa
https://nextcloud.home.arpa
https://immich.home.arpa
https://jellyfin.home.arpa
```

Direct recovery/setup ports were bound on all host interfaces during the audit: Homepage `3000`, Portainer `9443`, Beszel `8090`, Uptime Kuma `3001`, Nextcloud `8080`, Immich `2283`, Jellyfin TCP `8096`, and Jellyfin UDP `7359`. Caddy exposed TCP `80` and TCP/UDP `443`.

These bindings are currently suitable only for a trusted LAN unless host and upstream firewall policy provides additional restrictions. No router configuration was audited.

## Remote management

- Tailscale is installed and `tailscaled` is active.
- Tailnet enrollment, MagicDNS, ACLs, and SSH through Tailscale were not verified during this audit.
- Cockpit is not installed and `cockpit.socket` is inactive.
- GNOME Remote Desktop / RDP state was not audited.
- Current Codex access from SilverBrick uses the LAN SSH alias `hp-server` and a dedicated ED25519 key.

No public port forwarding should be introduced for SSH, Cockpit, RDP, or application services.

## Hardware acceleration and disk health

- `smartctl` is installed; SMART device inventory, baselines, scheduled tests, and alerts remain to be configured.
- `/dev/dri/card1` and `/dev/dri/renderD128` exist.
- `vainfo` is not installed.
- Jellyfin VA-API device mapping and hardware transcoding remain unverified and must not be enabled blindly.

## Backup

`homelab-backup.timer` is installed and active. During the audit it showed a previous activation on 2026-07-25 and a next scheduled run on 2026-07-26.

This differs from the earlier project summary that described Restic setup as deferred. The audit did **not** read the Restic password, inspect `.env`, run a backup, list snapshots, or test a restore. Backup repository health and recoverability therefore remain unverified.

## Sensitive and ignored files

- `.env` is ignored and was not read.
- An ignored file named `.env.before-restructure` exists with mode `664`; its contents were not read.
- Treat both files as sensitive. Review or removal of the older file requires explicit approval and a verified recovery path.

## Validation results

The following checks passed on 2026-07-25:

```text
make validate: Shell and Docker Compose validation passed.
make doctor: all reported checks OK.
findmnt /srv/storage: /dev/sdb2 mounted as ext4 read-write.
docker compose ps: deployed application containers running; health-checked containers healthy.
```

No containers were restarted, no packages were installed, no firewall or SSH server settings were changed, and no disks, mounts, databases, application data, or secrets were modified during the audit.
