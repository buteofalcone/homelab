# Backup policy

Before each Restic snapshot, the backup job creates logical PostgreSQL dumps for running Nextcloud and Immich database containers and a consistent SQLite copy for Open WebUI when it is running.

The local Restic job backs up:

- `/srv/appdata`, excluding live PostgreSQL data directories
- `/opt/homelab`, excluding `.git` and `.env`
- `/etc/homelab`

This includes Calibre GUI and built-in Content Server configuration under `/srv/appdata/calibre` and the root-only GUI password under `/etc/homelab`.

After the private SMB Inbox is provisioned, the dedicated root-only Samba password under `/etc/homelab/fileshare` is included as well. `make verify-backup` checks for it when the Samba container is running. Staged files under `/srv/storage/incoming` are HDD-resident user data and require an external copy if they must survive disk loss.

Retention:

- 7 daily snapshots
- 5 weekly snapshots
- 12 monthly snapshots

## Verification

Run the read-only repository and dump audit:

```bash
make verify-backup
```

It lists recent snapshots, runs `restic check`, validates the compressed Nextcloud and Immich PostgreSQL dumps, and runs SQLite `integrity_check` against the Open WebUI copy when that service is running.

This audit completed successfully on 2026-07-28. The scheduled backup job also completed successfully that morning.

HDD-resident Nextcloud files, Immich photos, Jellyfin media and the Calibre library under `/srv/storage/books` are not copied into the Restic repository on the same HDD. Such a copy would not protect against HDD loss. Back these directories up to an external disk, another machine or cloud object storage.

Nextcloud Talk is covered by the Nextcloud PostgreSQL dump and `/srv/appdata/nextcloud`. `make verify-database-restore` checks Talk control tables in an isolated PostgreSQL instance, while `make verify-management-restore` restores the Nextcloud application tree without touching live state. Talk file attachments remain Nextcloud user data under `/srv/storage/files/nextcloud` and share the external-backup requirement above.
