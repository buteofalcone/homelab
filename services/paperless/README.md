# Paperless-ngx

Paperless-ngx is the private searchable archive for scanned documents, invoices, contracts, manuals and warranties.

## Storage

- PostgreSQL, Valkey and the search index: `/srv/appdata/paperless` on the SSD.
- Original and archived documents: `/srv/storage/documents/paperless/media` on the storage HDD.
- Manual exports: `/srv/storage/documents/paperless/export`.
- SMB intake folder: `Inbox/documents`, mapped to `/srv/storage/incoming/documents`.
- Root-only credentials: `/etc/homelab/paperless.env`.

Files copied to `Inbox/documents` are consumed recursively. The source folder name becomes a tag. Keep an independent copy of irreplaceable documents until external/off-site backup is configured.

## Deployment

```bash
sudo make paperless-bootstrap
sudo make paperless-verify
```

Web access: `https://paperless.butenko.online`. LAN fallback: `http://SERVER_IP:8010`.

The regular backup creates `/srv/appdata/_backup-dumps/paperless.sql.gz` and protects Paperless application state and secrets with Restic. The document media resides on the storage disk and still needs the planned external/off-site backup for protection against disk loss.
