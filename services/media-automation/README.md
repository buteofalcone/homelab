# Media automation

This module provides owner-only qBittorrent and Sonarr services. It intentionally does not configure indexers, series monitoring, or automatic downloads while the temporary 500 GB HDD is in use.

Both containers mount `/srv/storage` as `/data`:

- downloads: `/data/downloads/torrents`
- incomplete downloads: `/data/downloads/incomplete`
- TV library: `/data/media/TV`

This single mount preserves hardlinks and atomic moves. Jellyfin sees the same TV directory as `/media/TV`.

## Provisioning

```bash
make media-automation-bootstrap
```

The bootstrap creates a root-only password, removes qBittorrent's one-time password log by recreating the container, enables external Sonarr authentication behind Caddy, and verifies that both applications are empty and idle.

Owner URLs:

- `https://torrent.butenko.online`
- `https://sonarr.butenko.online`

Do not forward TCP/UDP 6881 on the router until the download policy is deliberately reviewed. Automatic downloads remain deferred until the final 8–16 TB HDD is installed.
