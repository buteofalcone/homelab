# Media automation

This module provides qBittorrent, Sonarr, Prowlarr, Radarr, and Seerr. Prowlarr centralizes indexers and syncs them to Sonarr and Radarr. Seerr provides the family-facing search/request interface backed by Jellyfin accounts. Indexer credentials and application API keys remain runtime secrets and are never committed to Git.

The Toloka indexer preserves Cyrillic release titles. Removing Cyrillic text can leave only quality and year fragments, preventing Radarr and Sonarr from matching a release to the requested media.

Both containers mount `/srv/storage` as `/data`:

- downloads: `/data/downloads/torrents`
- incomplete downloads: `/data/downloads/incomplete`
- TV library: `/data/media/TV`
- movie library: `/data/media/Movies`

This single mount preserves hardlinks and atomic moves. Jellyfin sees the same TV directory as `/media/TV`.

## Provisioning

```bash
make media-automation-bootstrap
```

The bootstrap creates a root-only password, removes qBittorrent's one-time password log by recreating the container, enables external Sonarr/Prowlarr/Radarr authentication behind Caddy, connects the applications, adds Internet Archive, starts Seerr, and verifies the complete pipeline. qBittorrent refuses new data when free space drops below `MEDIA_MIN_FREE_GB` (80 GiB by default).

Connect the applications and add the lawful Internet Archive indexer:

```bash
make media-automation-connect
```

This idempotently creates the `/data/media/TV` and `/data/media/Movies` roots, the `tv-sonarr` and `movies-radarr` qBittorrent download clients, full-sync Prowlarr applications, and the public Internet Archive indexer. The qBittorrent password and Arr API keys are read only from runtime secret/config files.

## Toloka.to

Run:

```bash
make media-automation-toloka
```

The command securely prompts for Toloka credentials, stores them base64-encoded in root-only `/etc/homelab/toloka.env`, validates the built-in Toloka.to Prowlarr definition, and syncs the indexer to Radarr and Sonarr. Base64 is only a safe serialization format, not encryption; protection comes from root-only permissions and the encrypted/controlled backup repository. Never commit the credentials file.

Use Toloka and every other indexer only for material you are legally allowed to download and retain. Respect the tracker's ratio and seeding rules.

## Seerr onboarding

Open `https://requests.butenko.online` after bootstrap and complete the one-time setup:

1. Select Jellyfin and connect to internal URL `http://jellyfin:8096`; set the external URL to `https://jellyfin.butenko.online`.
2. Sign in with the Jellyfin administrator once, then import the allowed Jellyfin users.
3. Add Sonarr at `http://sonarr:8989` with root `/data/media/TV` and Radarr at `http://radarr:7878` with root `/data/media/Movies`.
4. Keep the default family permission limited to submitting non-4K requests and enable automatic approval. A submitted request is sent to Radarr or Sonarr immediately; the qBittorrent free-space floor remains the disk-safety control.

The current server uses the `HD-720p` profile for both applications, starts an automatic search immediately after each request, and enables Jellyfin scans. Jellyfin libraries are `Серіали` at `/media/TV` and `Фільми` at `/media/Movies`.

Seerr data is persisted under `/srv/appdata/seerr` and included in the normal Restic snapshot.

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
- `https://radarr.butenko.online`
- `https://requests.butenko.online`

Do not forward TCP/UDP 6881 on the router until the download policy is deliberately reviewed. On the temporary disk, use only a small lawful test series and keep high-volume monitoring disabled. After the 8–16 TB migration, adjust the free-space floor and policy without changing container paths.

## Backup boundary

The normal Restic job protects qBittorrent, Sonarr, and Prowlarr configuration under `/srv/appdata`, plus the root-only media password and Caddy hash under `/etc/homelab`. `make verify-backup` checks these files in the latest snapshot. Downloaded media under `/srv/storage` is intentionally outside this same-disk Restic repository and requires the planned external backup.
