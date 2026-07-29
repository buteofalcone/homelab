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

SilverBrick is the planned remote machine-learning host for its RTX 4060. The CUDA ML container must match the HP Server Immich version exactly, remain reachable only from the HP Server over Tailscale, and keep its model cache persistent. Start with the SilverBrick URL first and the local ML container second as fallback. The remote service has no authentication, so TCP 3003 must never be exposed publicly.
