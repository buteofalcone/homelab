# Homelab

A maintainable single-server homelab for an HP EliteDesk running Ubuntu, Docker Engine and Docker Compose.

## Stack

**Always-on Compose management layer**

- Homepage
- Portainer CE
- Beszel
- Uptime Kuma
- Caddy
- Watchtower in opt-in mode

**Optional application profiles**

- Nextcloud
- Immich
- Jellyfin
- Beszel agent
- Time Machine for the two family Macs

**Host services**

- Tailscale and OpenSSH
- Cockpit, restricted to the Tailscale address
- GNOME Remote Desktop / RDP, restricted to `tailscale0`
- Restic backup and host-health systemd timers

Paperless-ngx is intentionally not included.

## Repository layout

```text
compose/                 One Compose file per existing service or application stack
services/                New self-contained services, beginning with Time Machine
config/                  Static application configuration
scripts/                 Bootstrap, operations, backup and restore scripts
systemd/                 Host services and timers installed from tracked sources
docs/services/           Service-specific runbooks
```

Mutable runtime data and secrets never live in Git:

```text
/opt/homelab             Repository
/srv/appdata             Application state and databases on SSD
/srv/storage             User files, media and local backups on HDD
/etc/homelab             Host-only secrets
```

Git is the source of truth for infrastructure definitions and recovery logic. Application databases, user files, monitor history, credentials, and enrollment state are restored from backups or supplied interactively; they are not source-controlled.

## Deployment on a prepared host

```bash
cd /opt/homelab
git pull --ff-only
make bootstrap
nano .env
make validate
make install
```

`make install` starts only the management layer and Caddy. Start optional applications independently:

```bash
make nextcloud
make immich
make jellyfin
make timemachine-bootstrap
```

The current workflow assumes Ubuntu, Docker, Git, the `/srv/storage` mount, and required host packages already exist. A complete empty-machine `clone -> bootstrap -> restore` workflow is the Milestone 2C target and is not yet complete. See `docs/reproducibility-audit.md` for the audited gaps.

## Private HTTPS over Tailscale

The production domain is `butenko.online`. Cloudflare DNS-only records resolve these names to the server's Tailscale IP:

```text
home.butenko.online
portainer.butenko.online
beszel.butenko.online
uptime.butenko.online
nextcloud.butenko.online
immich.butenko.online
jellyfin.butenko.online
```

Caddy uses the Cloudflare DNS challenge to obtain Let's Encrypt certificates without exposing ports 80 or 443 on the router. The scoped API token lives only in `/etc/homelab/caddy.env` with root-only permissions.

Clients must be connected to the tailnet, but do not need custom DNS entries or a private CA certificate. Direct ports remain available for initial setup and troubleshooting on trusted networks.

## Daily operation

```bash
make help
make ps
make doctor
make logs
SERVICE=immich-server make logs
make update
```

Stateful applications do not receive automatic Watchtower updates. Review release notes and run `make update-all` deliberately.

## Backup

```bash
sudo ./scripts/restic-init.sh
sudo ./scripts/install-backup-timer.sh
make backup
make snapshots
make verify-backup
make verify-restore
```

The local Restic repository protects application state on the SSD. It does not protect HDD-resident files or photos from failure of the HDD itself. Add an external or off-site backup before treating Nextcloud or Immich as the only copy of important data.

`make verify-restore` restores only the repository README and the two PostgreSQL dumps into a new timestamped directory under `/srv/storage/restores`. It never overwrites live paths and intentionally retains the result for review.

## Disaster recovery

The clean-machine recovery workflow is being implemented incrementally. Start with the read-only host check:

```bash
make recovery-preflight
```

See [`docs/disaster-recovery.md`](docs/disaster-recovery.md) for the current safety boundaries, remaining manual steps, and offline secret inventory.

See `docs/` for the observed state, target architecture, current roadmap, reproducibility audit, storage, backup, restore, remote management, and monitoring details.

Remote access through Tailscale, Cockpit, and GNOME Remote Login is documented in `docs/remote-management.md`.
Family application access is documented in `docs/family-access.md`.
