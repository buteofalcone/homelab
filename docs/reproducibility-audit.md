# Reproducibility Audit

Audit date: **2026-07-27**. Baseline commit: `dea5af8`.

## Definition of "Git is the source of truth"

Git owns infrastructure definitions: Compose, static configuration, systemd units, install logic, validation, and recovery instructions. Git does not own mutable application databases, user content, credentials, tokens, certificates, or device enrollment state.

A runtime-only setting is acceptable only when it is one of the following:

1. a secret supplied from an offline record;
2. application data covered by a verified backup and restore procedure;
3. generated state that the bootstrap process can safely recreate.

## What is reproducible now

| Area | Status | Evidence |
| --- | --- | --- |
| Compose topology | Good | All running containers are declared; only intentionally stopped Watchtower differs. |
| Caddy routes and image | Good | Caddyfile, Dockerfile, entrypoint, domain, and DNS provisioning script are tracked. |
| Homepage configuration | Good | Runtime configuration matched tracked files byte-for-byte. |
| Cockpit restriction | Good | Installer and socket drop-in are tracked and match runtime. |
| RDP restriction | Good | nftables source, systemd service, and GNOME drop-in are tracked; services are active. |
| Health monitoring | Good | Script, systemd units, and secret template are tracked and runtime units match. |
| Backup schedule | Captured | Runtime-only unit differences were found and copied into Git. |
| Secret locations | Documented | `.env` and `/etc/homelab` stay outside Git; required variable names are represented by examples. |

## Recovery gaps

### P0 — required before claiming full disaster recovery

- There is no single bootstrap command for an empty Ubuntu installation. Docker, Git, Tailscale, Cockpit, GNOME Remote Desktop dependencies, SMART tools, Restic, mounts, groups, and timers are not provisioned as one workflow.
- Storage discovery and `/etc/fstab` creation are intentionally manual and are not yet covered by a safe recovery runbook.
- `restore.sh` only extracts a Restic snapshot. It does not stop services, restore live paths, import Nextcloud and Immich SQL dumps, repair ownership, start profiles, or run application integrity checks.
- Restic repository integrity and a targeted file/dump restore are verified. A complete application-aware restore with database import remains untested.
- The Restic repository is on the same temporary HDD as user data. There is no external or off-site copy.
- HDD-resident Nextcloud files, Immich photos, and Jellyfin media are not protected by the local Restic job.
- The Restic password and other recovery secrets need a verified offline inventory. Their values must never be committed.

### P1 — required for unattended service reconstruction

- Tailscale installation can be automated, but tailnet enrollment must remain an explicit authenticated step.
- Cloudflare DNS can be recreated by the tracked script, but the scoped token must be supplied separately.
- Beszel Agent credentials require a Hub-generated key and token. The safe update helper is tracked, but the recovery handoff is manual.
- Cockpit and RDP have tracked configuration scripts, but they are not called by a top-level bootstrap. RDP gateway credentials must remain interactive.
- Uptime Kuma monitors and Telegram notification configuration live in its application database. Recovery currently depends on restoring `/srv/appdata/uptime-kuma`.
- Portainer, Beszel, Nextcloud, Immich, and Jellyfin settings similarly depend on restored application state.
- Homepage configuration is copied during install rather than mounted read-only. A drift check should be added to routine validation.
- Direct application ports are bound to all interfaces. The July 2026 exposure audit records their trusted-LAN recovery role in `docs/current-state.md`; future restriction to loopback must be staged only after a LAN recovery-access test.

### P2 — maintainability improvements

- Pin or deliberately manage mutable image tags such as `latest`, `release`, and `lts`.
- Define a documented Watchtower policy; the service is declared but intentionally stopped.
- Add a machine-readable post-restore verification command covering HTTPS endpoints, timers, mounts, and application health.
- Record backup recovery time and the result of periodic restore drills.

## Milestone 2A acceptance criteria

Milestone 2A is complete when:

- repository documentation matches observed runtime;
- every installed static homelab configuration has a tracked source or an explicit documented exception;
- bootstrap and restore gaps are recorded without claiming capabilities that do not exist;
- validation passes, the server remains healthy, and the audit changes are pushed.

This milestone does **not** claim that a clean-machine recovery is complete. That claim belongs to Milestone 2C and requires a successful destructive-environment or spare-disk restore drill.

## Milestone 2C acceptance test

On a clean Ubuntu installation:

1. clone the repository;
2. run one documented bootstrap entry point;
3. supply only explicitly listed secrets and authenticated enrollments;
4. restore application state and user data from verified backups;
5. validate mounts, containers, HTTPS, SSH, Cockpit, RDP, monitoring, databases, and representative user files;
6. record recovery time and any manual intervention.

Only a successful test permits the statement: "The repository and backups can rebuild the complete server."
