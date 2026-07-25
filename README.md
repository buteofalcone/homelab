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

## Local HTTPS

The default local domain is `home.arpa`. Configure local DNS or client hosts files so these names resolve to `SERVER_IP`:

```text
home.home.arpa
portainer.home.arpa
beszel.home.arpa
uptime.home.arpa
nextcloud.home.arpa
immich.home.arpa
jellyfin.home.arpa
```

Caddy uses its internal certificate authority. Export the root certificate:

```bash
make caddy-root
```

Then import `/srv/storage/files/homelab-caddy-root.crt` into each client operating system or browser trust store.

Direct ports remain available for initial setup and troubleshooting.

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

See `docs/` for architecture, storage, backup and restore details.

Remote access through Tailscale, Cockpit, and GNOME Remote Login is documented in `docs/remote-management.md`.
