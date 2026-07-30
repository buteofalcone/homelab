# Current State

Last verified: **2026-07-29** through SSH from SilverBrick.

This document records observed runtime state. Target architecture and future work are documented separately in `docs/architecture.md` and `TASKS.md`.

## Host and storage

| Item | Observed value |
| --- | --- |
| Hardware | HP Compaq Elite 8300 SFF, Intel Core i5-3570, 16 GB RAM |
| Operating system | Ubuntu 26.04 LTS |
| Kernel | `7.0.0-28-generic` |
| Hostname | `hp-server` |
| Administrative user | `butenko` |
| LAN address | `192.168.1.130` |
| Tailscale address | `100.65.83.35` |
| System SSD | `/dev/sda2`, 234 GB, 30 GB used |
| Data HDD | `/dev/sdb2`, ext4, mounted read-write at `/srv/storage`, 458 GB, 1.1 GB used |

Application state and databases are under `/srv/appdata`. User files are under `/srv/storage`. Deployment must stop if `findmnt /srv/storage` does not confirm the dedicated mount.

## Repository

| Item | Observed value |
| --- | --- |
| Path | `/opt/homelab` |
| Remote | `git@github.com:buteofalcone/homelab.git` |
| Branch | `feature/base-management-stack` |
| Repository state | Calibre and media automation implemented and validated; Git history is authoritative |

## Running services

The following Compose services were running:

- Management and routing: `homepage`, `homepage-docker-proxy`, `portainer`, `beszel`, `beszel-agent`, `uptime-kuma`, `caddy`.
- Nextcloud: `nextcloud`, `nextcloud-cron`, `nextcloud-db`, `nextcloud-redis`, with Talk 23.0.9 enabled inside Nextcloud.
- Immich: `immich-server`, `immich-machine-learning`, `immich-database`, `immich-redis`. Immich `v3.0.3` uses the pinned CUDA ML container on SilverBrick (`100.91.171.26:3003`, RTX 4060) first and the local ML container as fallback; Windows Firewall permits the unauthenticated ML port only from the HP Server Tailscale address.
- Media: `jellyfin`, `qbittorrent`, `sonarr`, `prowlarr`, `radarr`, and `seerr`.
- Books: full Calibre 9.11 desktop application and its built-in Content server, both provided by the single `calibre` container.
- Backup target: `timemachine`, with separate `TimeMachine-A1502` and `TimeMachine-A1466` shares.
- Private AI: `open-webui`, connected through Tailscale to authenticated LM Studio on SilverBrick.

`watchtower` is declared but intentionally not running. Its logs show that rolling restart validation rejects the `homepage` dependency on `homepage-docker-proxy`; stateful application updates remain manual.

Host services are also active: Docker, Tailscale, OpenSSH, Cockpit, GNOME Remote Desktop, the RDP nftables filter, the backup timer, and the health timer.

## Access and TLS

`butenko.online` is the production domain. Cloudflare DNS-only records point the service names at `100.65.83.35`. Caddy uses the Cloudflare DNS challenge and Let's Encrypt certificates. Clients need access to the same Tailscale network, but do not need custom DNS or a private CA certificate.

Working service names:

```text
home.butenko.online
portainer.butenko.online
beszel.butenko.online
uptime.butenko.online
nextcloud.butenko.online
immich.butenko.online
jellyfin.butenko.online
ai.butenko.online
calibre.butenko.online
books.butenko.online
torrent.butenko.online
sonarr.butenko.online
prowlarr.butenko.online
```

Cockpit listens only on `100.65.83.35:9090`. RDP listens on TCP 3389, with the repository-managed nftables rule allowing it only through `tailscale0`. SSH over Tailscale is working. No router port forwarding is required or intended.

## Network exposure policy

The normal family-facing path is **Tailscale + the `https://*.butenko.online` URLs through Caddy**. Family devices do not need to use container ports directly.

The July 2026 audit found that several older application ports still listen on all host interfaces. They are currently retained only as trusted-LAN/recovery access, not as an Internet-facing design:

| Exposure | Intended role | Policy |
| --- | --- | --- |
| Caddy TCP 80/443 and UDP 443 | HTTPS for the named services | Primary access path; no router forwarding. |
| Samba TCP 445 | Time Machine on trusted LAN or Tailscale | Kept published for SMB clients. |
| qBittorrent TCP/UDP 6881 | BitTorrent peer traffic | Kept published; UPnP is disabled and no router forwarding is configured. |
| Jellyfin UDP 7359 | LAN client discovery | Kept published for local discovery. |
| Homepage, Uptime Kuma, Beszel, Nextcloud, Immich, Jellyfin TCP UI ports and Portainer 9443 | Legacy trusted-LAN/recovery access | Not a family-facing route; a future staged change may bind these to loopback after a recovery-access test. |

Open WebUI is already restricted to loopback (`127.0.0.1:3002`) and Calibre publishes no host ports; both are reached through Caddy. No public router forwarding is required or intended. Do not remove or rebind the remaining recovery ports until the router and LAN recovery path have been reviewed.

Time Machine SMB listens on TCP 445 for trusted-LAN and Tailscale clients. Connectivity through the server's Tailscale address was verified from SilverBrick. Avahi publishes `hp-server Time Machine` through Bonjour for local-LAN discovery.

## Monitoring

- Beszel Hub and Agent are running.
- Uptime Kuma has application, internet, storage, SMART, and backup monitoring configured.
- Telegram notifications are configured in Uptime Kuma runtime state.
- Calibre's internal Content server is monitored as `Books`; its Telegram notification is attached.
- `homelab-health.timer` runs every 15 minutes; its most recent run completed successfully on 2026-07-27.
- Both disks passed the recorded SMART baseline. The temporary 500 GB HDD has high power-on hours and must not become the only copy of important data.
- Docker-based Samba Time Machine is running with separate accounts, directories, and 100 GB test limits for A1502 and A1466. MacBook A1466 completed its first small test backup on 2026-07-27, using approximately 4.6 GB. A1502 remains untested.

## Backup

`homelab-backup.timer` is active and the most recent job completed successfully on 2026-07-28. The installed schedule is 03:30 with up to 10 minutes of randomized delay; this version is captured in Git.

The job creates logical PostgreSQL dumps and stores a local Restic snapshot on the same HDD. This protects SSD application state from an SSD failure, but does not protect against failure, loss, or corruption of the HDD itself.

Repository integrity, recent snapshots, PostgreSQL dumps, and a targeted restore were independently verified on 2026-07-28. Restic successfully restored the repository README and both compressed database dumps into `/srv/storage/restores/restic-smoke-20260728-115000`; both dumps passed `gzip -t`.

After installing Nextcloud Talk, a fresh snapshot was created and verified. The Nextcloud dump imported into a temporary PostgreSQL instance with the Talk control tables present, and `/srv/appdata/nextcloud` restored into an isolated management audit tree. This confirms recovery coverage for Talk application code, configuration, and conversation database state. Files shared through Talk remain part of Nextcloud user data on the HDD and still require the planned external copy.

The latest verified Restic snapshot contains qBittorrent, Sonarr, and Prowlarr configuration plus the root-only media automation password and Caddy credentials. Downloaded media remains outside the same-disk Restic repository by design.

A complete application-aware restore and an external/off-site copy are still missing. Disaster recovery is therefore **not complete**.

## Runtime state that does not belong in Git

The following are deliberately excluded from Git:

- passwords, tokens, RDP credentials, and the Restic password;
- application databases and user accounts;
- Nextcloud files, Immich photos, and Jellyfin media;
- Uptime Kuma monitors, history, and Telegram settings;
- Portainer, Beszel, Nextcloud and Talk, Immich, Jellyfin, Open WebUI, Calibre, and Caddy runtime state;
- Tailscale device identity and enrollment state.

Git must define how these items are provisioned or restored. Backup and restore, rather than source control, preserve their values.

## Validation results

On 2026-07-28:

- `make validate` passed.
- `make doctor` passed before this audit.
- all expected containers except intentionally stopped Watchtower were running;
- Homepage runtime configuration matched the repository byte-for-byte;
- health, RDP, Cockpit, and GNOME Remote Desktop systemd configuration matched Git;
- backup systemd drift was found and captured in Git without changing the running server.
- Open WebUI reported healthy, contained one administrator account, reached `qwen/qwen3.5-9b` through the authenticated LM Studio API, and served a trusted HTTPS health response at `ai.butenko.online`.
- Calibre 9.11 reported healthy, its administration route required authentication, its Content server returned HTTP 200 at `books.butenko.online`, and a generated source document was converted to EPUB and added to the library.
- Nextcloud Talk 23.0.9 was enabled on Nextcloud 33.0.7; its app integrity, OCC commands, and private HTTPS route passed the tracked verification helper.

On 2026-07-29, the bounded media test downloaded one public-domain episode of *The Adventures of Ozzie & Harriet*. Sonarr imported S01E01 automatically, the qBittorrent and library paths shared one inode with link count 2, and Jellyfin could read the imported file through `/media/TV`. A Jellyfin `Серіали` library was created for `/media/TV`; it discovered the show and S1:E1. `make media-automation-test-verify` reported `MEDIA_PUBLIC_DOMAIN_TEST_VERIFY_OK`. Uptime Kuma monitors qBittorrent, Sonarr, and Prowlarr internally with the existing Telegram alert channel; all three reported `up`.

Radarr, Seerr, and the built-in Toloka.to Prowlarr indexer were deployed and verified on 2026-07-29. Toloka credentials remain only in root-readable runtime state. Prowlarr supplies Toloka searches to both Sonarr and Radarr, and both applications send requested downloads to qBittorrent with separate categories. Seerr uses Jellyfin accounts, internal Docker service addresses, the `HD-720p` default profile, and roots `/data/media/TV` and `/data/media/Movies`. New family accounts may submit non-4K requests with automatic approval; 4K requests remain disabled. Jellyfin now has `Серіали` and `Фільми` libraries mapped to `/media/TV` and `/media/Movies`.

Uptime Kuma monitors Radarr and Seerr through their internal Docker endpoints with the existing Telegram notification channel; both reported `up`. A fresh Restic snapshot and the full backup verification completed successfully after the Seerr onboarding, covering the Radarr configuration, Seerr database, and root-only Toloka recovery file.

Jellyfin VA-API is enabled on the Intel Ivy Bridge iGPU. The container receives only `/dev/dri/renderD128` and the host `render` GID 990. A real low-bitrate playback used `-hwaccel vaapi`, `h264_vaapi`, and `scale_vaapi`; FFmpeg exited successfully. The preceding normal-quality playback used direct play.

The 514-byte `.env.before-restructure` legacy environment file dated 2026-07-24 had mode `664` and variable names that were a subset of the current `.env`. After owner confirmation, it was removed on 2026-07-29. The current `.env` was not changed.

No container, firewall rule, package, mount, database, application data, or secret was changed during this audit.
