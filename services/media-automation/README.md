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

The bootstrap creates a root-only password, removes qBittorrent's one-time password log by recreating the container, enables external Sonarr/Prowlarr authentication behind Caddy, and verifies that the applications are healthy. qBittorrent refuses new data when free space drops below `MEDIA_MIN_FREE_GB` (80 GiB by default).

Owner URLs:

- `https://torrent.butenko.online`
- `https://sonarr.butenko.online`
- `https://prowlarr.butenko.online`

Do not forward TCP/UDP 6881 on the router until the download policy is deliberately reviewed. On the temporary disk, use only a small lawful test series and keep high-volume monitoring disabled. After the 8–16 TB migration, adjust the free-space floor and policy without changing container paths.
