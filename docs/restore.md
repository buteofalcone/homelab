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
