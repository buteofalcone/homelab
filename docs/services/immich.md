# Immich

## Start

```bash
make immich
```

Direct URL: `http://SERVER_IP:2283`  
HTTPS URL: `https://immich.BASE_DOMAIN`

The first user created in the web interface becomes the administrator.

## Storage

Immich-managed assets are stored under `/srv/storage/photos`. PostgreSQL data and the machine-learning model cache are stored on SSD under `/srv/appdata/immich`.

Do not manually copy an existing photo archive into Immich's managed `/data` directory. Mount existing archives separately and add them through Immich External Libraries, preferably read-only until the library has been verified.

## Backup

A complete backup requires both:

- the PostgreSQL database;
- all files under `/srv/storage/photos`.

The homelab backup script creates an Immich PostgreSQL dump before Restic runs. Immich should never be the only copy of important photos and videos.

## Resources and updates

Immich is resource-intensive and evolves quickly. On this server, the initial machine-learning indexing may cause sustained CPU load. Read release notes before upgrades and keep automatic Watchtower updates disabled for the Immich stack.

## Planned Google Photos migration and remote ML

Google Photos Takeout will be imported with a pinned `immich-go` release because it can pair media with Google JSON sidecars and reconstruct albums and capture metadata. The first run must use a small representative sample and a dry-run; the complete archives remain immutable until asset counts, dates, albums, duplicates, and backup coverage are verified.

The current compatibility baseline is Immich `v3.0.3` with `immich-go v0.32.0`. Bootstrap creates private SMB staging at `/srv/storage/incoming/google-photos-takeout/{sample,full}` and verifies the official Linux archive checksum before installing the tool.

SilverBrick is the planned remote machine-learning host for its RTX 4060. The CUDA ML container must match the HP Server Immich version exactly, remain reachable only from the HP Server over Tailscale, and keep its model cache persistent. Start with the SilverBrick URL first and the local ML container second as fallback. The remote service has no authentication, so TCP 3003 must never be exposed publicly.

The reproducible SilverBrick configuration and PowerShell runbook live in `services/immich-remote-ml/`. The verified baseline is Windows 11 build 22631, WSL 2.2.4, NVIDIA driver 610.62, RTX 4060 8 GB, SilverBrick `100.91.171.26`, and HP Server `100.65.83.35`. Docker Desktop stores its WSL data disk on `E:\DockerData\DockerDesktopWSL`. Immich `v3.0.3` is configured remote-first with the local ML container as fallback; the authenticated configuration workflow preserves a root-only rollback copy under `/etc/homelab/immich-system-config/`.
