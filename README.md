# Homelab

Single-server Docker Compose homelab for an HP EliteDesk running Ubuntu.

## Base services

| Service | URL |
|---|---|
| Homepage | `http://SERVER_IP:3000` |
| Portainer CE | `https://SERVER_IP:9443` |
| Beszel Hub | `http://SERVER_IP:8090` |
| Uptime Kuma | `http://SERVER_IP:3001` |

Watchtower uses an opt-in policy. Only containers carrying the explicit update label are updated automatically.

## Server paths

```text
/opt/homelab                 Git repository
/srv/appdata                 Persistent application state on SSD
/srv/storage/files           User files on HDD
/srv/storage/backups         Backups on HDD
/srv/storage/downloads       Downloads on HDD
/etc/homelab                 Host-only secrets
```

## First installation

```bash
cd /opt/homelab
git pull
cp .env.example .env
nano .env
sudo ./scripts/install.sh
```

Then open the services in a browser and create their administrator accounts.

## Beszel local agent

1. Open Beszel Hub.
2. Create a token under **Settings → Tokens**.
3. Add a new system and copy the displayed public key.
4. Put the key and token into `/opt/homelab/.env`.
5. Start the agent:

```bash
cd /opt/homelab
docker compose --profile beszel-agent up -d
```

Use this host in the Beszel UI:

```text
/beszel_socket/beszel.sock
```

## Common commands

```bash
cd /opt/homelab

docker compose ps
docker compose logs -f
docker compose pull
docker compose up -d
docker compose down

./scripts/doctor.sh
./scripts/update.sh
```

## Restic backup

Initialize once:

```bash
sudo ./scripts/restic-init.sh
```

Run manually:

```bash
sudo ./scripts/backup.sh
```

Inspect snapshots:

```bash
sudo ./scripts/restic.sh snapshots
```

Restore into a temporary directory:

```bash
sudo ./scripts/restore.sh latest /srv/storage/restores/latest
```

Install the nightly systemd timer:

```bash
sudo ./scripts/install-backup-timer.sh
systemctl list-timers homelab-backup.timer
```

The local Restic repository protects against failure of the system SSD. It does not protect against theft, fire, accidental loss of both disks, or total server failure. Add an external/off-site repository later.

## Updating

The controlled manual path is:

```bash
cd /opt/homelab
./scripts/update.sh
```

Watchtower updates only explicitly labeled low-risk containers at 04:00 each day. Stateful management services remain manual by default.

## Recovery outline

1. Install Ubuntu and Docker.
2. Mount the HDD at `/srv/storage`.
3. Clone this repository to `/opt/homelab`.
4. Restore `/srv/appdata` from Restic.
5. Copy `.env.example` to `.env` and adjust host-specific values.
6. Run `sudo ./scripts/install.sh`.
