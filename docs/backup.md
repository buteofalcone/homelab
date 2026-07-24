# Backup policy

Before each Restic snapshot, the backup job creates logical PostgreSQL dumps for running Nextcloud and Immich database containers.

The local Restic job backs up:

- `/srv/appdata`, excluding live PostgreSQL data directories
- `/opt/homelab`, excluding `.git` and `.env`
- `/etc/homelab`

Retention:

- 7 daily snapshots
- 5 weekly snapshots
- 12 monthly snapshots

HDD-resident Nextcloud files, Immich photos and Jellyfin media are not copied into the Restic repository on the same HDD. Such a copy would not protect against HDD loss. Back these directories up to an external disk, another machine or cloud object storage.
