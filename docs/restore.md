# Restore procedure

Restore first into a temporary directory:

```bash
sudo /opt/homelab/scripts/restore.sh latest /srv/storage/restores/latest
```

Stop the affected container before replacing live application data. Preserve file ownership and permissions when copying restored data back into `/srv/appdata`.
