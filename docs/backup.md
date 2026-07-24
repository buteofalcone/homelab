# Backup policy

The nightly Restic job backs up:

- `/srv/appdata`
- `/opt/homelab`
- `/etc/homelab`

Retention:

- 7 daily snapshots
- 5 weekly snapshots
- 12 monthly snapshots

The Git working tree's `.env` file is excluded because it may contain secrets. Host-only secrets are stored under `/etc/homelab` and are included in the encrypted Restic repository.
