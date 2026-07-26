# Homelab

A maintainable single-server homelab for an HP EliteDesk running Ubuntu, Docker Engine and Docker Compose.

## Stack

**Always-on management layer**

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

Paperless-ngx is intentionally not included.

## Repository layout

```text
compose/                 One Compose file per service or application stack
config/                  Static application configuration
scripts/                 Bootstrap, operations, backup and restore scripts
systemd/                 Nightly backup unit and timer
docs/services/           Service-specific runbooks
```

Runtime data never lives in Git:

```text
/opt/homelab             Repository
/srv/appdata             Application state and databases on SSD
/srv/storage             User files, media and local backups on HDD
/etc/homelab             Host-only secrets
```

## First deployment

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
```

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

Caddy uses the Cloudflare DNS challenge to obtain publicly trusted certificates without exposing ports 80 or 443 on the router. The scoped API token lives only in `/etc/homelab/caddy.env` with root-only permissions.

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
```

The local Restic repository protects application state on the SSD. It does not protect HDD-resident files or photos from failure of the HDD itself. Add an external or off-site backup before treating Nextcloud or Immich as the only copy of important data.

See `docs/` for architecture, storage, backup, restore, remote management, and monitoring details.

Remote access through Tailscale, Cockpit, and GNOME Remote Login is documented in `docs/remote-management.md`.
Family application access is documented in `docs/family-access.md`.
