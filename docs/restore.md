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
