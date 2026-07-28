# Restore procedure

Restore into a temporary directory first:

```bash
sudo /opt/homelab/scripts/restore.sh latest /srv/storage/restores/latest
```

For application recovery:

1. Stop the affected profile.
2. Restore its application directory from the temporary restore.
3. Start its database container.
4. Import the matching SQL dump from `_backup-dumps`.
5. Start the full profile.
6. Run application-specific integrity checks.

Never overwrite live data directly from Restic without inspecting the restored tree.

## Safe verification restore

```bash
make verify-restore
```

This restores only `README.md` and the Nextcloud and Immich SQL dumps into a new timestamped directory under `/srv/storage/restores`. It verifies that all three files are non-empty and that both compressed dumps pass `gzip -t`. It does not stop services or write into live application paths.

The first smoke restore completed successfully on 2026-07-28 at:

```text
/srv/storage/restores/restic-smoke-20260728-115000
```

The directory is intentionally retained for inspection. Removing it later is a separate cleanup action.

This proves targeted Restic recovery and dump readability. It does not yet prove a complete application-aware restore with database import and application integrity checks.

## Disposable database import verification

```bash
make verify-database-restore
```

This command restores the two latest compressed database dumps into a new timestamped directory and imports each dump into a temporary PostgreSQL container. The containers use isolated networking and memory-backed database storage; they never mount or modify the live PostgreSQL directories.

The verifier checks a minimum table count and representative control tables for both applications. Temporary databases are removed automatically. The restored compressed dumps are retained under `/srv/storage/restores/database-verify-*` for audit.

`DATABASE_RESTORE_VERIFY_OK` proves that the latest dumps are readable by the currently declared database images. It still does not authorize replacing a live database.

The first disposable database-import verification completed successfully on 2026-07-28 using Restic snapshot `fcf80144`:

```text
DATABASE_RESTORE_VERIFY_OK /srv/storage/restores/database-verify-20260728-132121
Nextcloud: 126 public tables
Immich: 66 public tables
```

Both temporary databases were removed automatically. The restored compressed dumps remain for audit.

## Post-restore verification

After an application-aware recovery, run:

```bash
make post-restore-check
```

The command checks the host prerequisites, Compose configuration, backup and health timers, Nextcloud and Immich databases, application health endpoints, trusted HTTPS routes, and Time Machine health when enabled. A complete pass ends with `POST_RESTORE_CHECK_OK`.
