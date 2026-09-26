# Monitoring

## Uptime Kuma

Uptime Kuma runs at `https://uptime.butenko.online`. The recommended HTTP monitors use Docker service DNS names so checks stay inside the Compose network:

| Monitor | URL |
| --- | --- |
| Homepage | `http://homepage:3000` |
| Portainer | `https://portainer:9443` (ignore TLS errors) |
| Beszel | `http://beszel:8090` |
| Nextcloud | `http://nextcloud/status.php` |
| Immich | `http://immich-server:2283/api/server/ping` |
| Jellyfin | `http://jellyfin:8096/health` |
| qBittorrent | TCP connection to `qbittorrent:8080` |
| Sonarr | `http://sonarr:8989/ping` |
| Prowlarr | `http://prowlarr:9696/ping` |
| Radarr | `http://radarr:7878/ping` |
| Seerr | `http://seerr:5055/api/v1/status` |
| Cockpit | `https://100.65.83.35:9090` (ignore TLS errors) |
| Internet connectivity | `https://1.1.1.1/cdn-cgi/trace` |

Backup, storage, and SMART use push monitors. Their private push endpoints belong in `/etc/homelab/monitoring.env`, never in Git:

```bash
UPTIME_KUMA_BACKUP_PUSH_URL=http://127.0.0.1:3001/api/push/REPLACE_ME
UPTIME_KUMA_STORAGE_PUSH_URL=http://127.0.0.1:3001/api/push/REPLACE_ME
UPTIME_KUMA_SMART_PUSH_URL=http://127.0.0.1:3001/api/push/REPLACE_ME
```

The backup script sends `up` only after Restic backup, retention, pruning, and repository checks all complete. An early failure sends `down` while preserving the original exit status.

## Notifications

Uptime Kuma sends Telegram notifications through the HP Server alerts integration. It is enabled by default for new monitors and was applied to all existing monitors. A test notification was delivered successfully on 2026-07-26. Bot tokens and chat IDs must never be committed to Git.

## Host health timer

Install the timer once:

```bash
make install-monitoring-timer
```

`homelab-health.timer` runs every 15 minutes. It verifies that `/srv/storage` is a mount point, checks disk usage, checks SMART overall health for `/dev/sda` and `/dev/sdb`, and alerts on non-zero critical attributes 5, 197, 198, or 199. Default limits are 90% disk usage and 55 C temperature.

Useful commands:

```bash
make health
systemctl list-timers homelab-health.timer
journalctl -u homelab-health.service
```

The checks are read-only. They do not start SMART self-tests, repair filesystems, or modify disks.

## SMART baseline (2026-07-26)

Both drives reported `PASSED`, no logged SMART errors, zero reallocated sectors, zero pending sectors, zero offline-uncorrectable sectors, and zero UDMA CRC errors.

| Device | Model | Type | Power-on hours | Temperature | Note |
| --- | --- | --- | ---: | ---: | --- |
| `/dev/sda` | SanDisk SD9TB8W256G1001 | SSD | 28,638 | 34 C | Media wear indicator normalized value 97 |
| `/dev/sdb` | Seagate ST500DM002-1BD142 | HDD | 50,677 | 35 C | Healthy but high operating age; retain verified backups and monitor closely |

The baseline intentionally used `smartctl -a` only; no destructive or extended tests were started.
