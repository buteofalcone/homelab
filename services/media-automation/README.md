# Media automation

This module provides owner-only qBittorrent, Sonarr, and Prowlarr services. Prowlarr centralizes indexers and syncs them to Sonarr. Indexer credentials and application API keys remain runtime secrets and are never committed to Git.

Both containers mount `/srv/storage` as `/data`:

- downloads: `/data/downloads/torrents`
- incomplete downloads: `/data/downloads/incomplete`
- TV library: `/data/media/TV`

This single mount preserves hardlinks and atomic moves. Jellyfin sees the same TV directory as `/media/TV`.

## Provisioning

```bash
make media-automation-bootstrap
```

The bootstrap creates a root-only password, removes qBittorrent's one-time password log by recreating the container, enables external Sonarr/Prowlarr authentication behind Caddy, connects the applications, adds Internet Archive, and verifies the complete pipeline. qBittorrent refuses new data when free space drops below `MEDIA_MIN_FREE_GB` (80 GiB by default).

Connect the applications and add the lawful Internet Archive indexer:

```bash
make media-automation-connect
```

This idempotently creates the `/data/media/TV` root, the `tv-sonarr` qBittorrent download client, a full-sync Prowlarr application, and the public Internet Archive indexer. The qBittorrent password and Arr API keys are read only from runtime secret/config files.

## Small public-domain test

`make media-automation-test` adds *The Adventures of Ozzie & Harriet*, leaves every episode unmonitored except S01E01 “The Rivals”, and pushes the exact 286 MB Internet Archive torrent through Sonarr. The direct push avoids ambiguous indexer parsing while preserving Sonarr tracking and automatic import. The helper refuses to run below the configured free-space floor and never selects the 221 GB complete-series pack. Festival Films lists “The Rivals” in its public-domain television catalog.

The helper validates the torrent's five exact files, keeps only one 136 MB MP4, gives it a parseable `S01E01` name, and adds a direct HTTPS Archive webseed. After the import completes, verify qBittorrent completion, Sonarr state, the shared hardlink inode, and Jellyfin visibility:

```bash
make media-automation-test-verify
```

Owner URLs:

- `https://torrent.butenko.online`
- `https://sonarr.butenko.online`
- `https://prowlarr.butenko.online`

Do not forward TCP/UDP 6881 on the router until the download policy is deliberately reviewed. On the temporary disk, use only a small lawful test series and keep high-volume monitoring disabled. After the 8–16 TB migration, adjust the free-space floor and policy without changing container paths.

## Backup boundary

The normal Restic job protects qBittorrent, Sonarr, and Prowlarr configuration under `/srv/appdata`, plus the root-only media password and Caddy hash under `/etc/homelab`. `make verify-backup` checks these files in the latest snapshot. Downloaded media under `/srv/storage` is intentionally outside this same-disk Restic repository and requires the planned external backup.
