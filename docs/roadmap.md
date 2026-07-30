# Roadmap

Last updated: **2026-07-28**.

This is the execution order for planned work. It complements `docs/architecture.md`; it does not authorize removing or reconfiguring working services.

## Active now

### 1. Disaster Recovery

Build and verify the clean-machine workflow:

```text
Ubuntu -> git clone -> bootstrap -> supply secrets -> restore -> verify
```

Required work:

- idempotent host bootstrap for Docker, Restic, Tailscale, Cockpit, SMART tools, Avahi, systemd units, and required directories;
- an explicit, safety-gated storage and `/etc/fstab` step that never formats a disk automatically;
- offline recovery inventory for Restic, Cloudflare, Tailscale, RDP, Time Machine, and application administrator credentials;
- application-aware Nextcloud and Immich database restore;
- restoration of Portainer, Beszel, Uptime Kuma, Caddy, Jellyfin, agent services, and future service state;
- post-restore health checks and a measured recovery drill.

Time Machine is accepted as working after the successful A1466 test. Further A1502, encryption, and file-restore testing is intentionally paused by owner decision.

### 2. Git-native agentic workflows

n8n is intentionally excluded. Build agentic workflows as small, reviewable Python services whose prompts, tool schemas, policies, tests, and deployment configuration live in Git.

Planned architecture:

- **Open WebUI** on the HP Server as the private family AI chat and approval interface;
- an agent runtime on the HP Server, starting with one orchestrator rather than a multi-agent hierarchy;
- an OpenAI-compatible model API on SilverBrick, reachable only through Tailscale;
- small audited tools exposed as Python functions, OpenAPI endpoints, or MCP servers;
- durable workflow state under `/srv/appdata/agents`, with backups from the first deployment;
- agent credentials under `/etc/homelab/agents.env`, never Git;
- systemd timers for scheduled triggers and a small queue with bounded retries when SilverBrick is offline;
- Caddy, Cloudflare DNS-only, Uptime Kuma, and structured audit logs without sensitive prompt payloads.

Safety policy:

1. Read-only observation and reporting may run automatically.
2. Reversible writes require a preview and explicit policy.
3. Downloads, service restarts, configuration changes, and messages sent as a user require human approval.
4. Disk operations, secret access, deletion, and restore-over-live-data are never autonomous tools.

First workflows should be narrow and measurable:

- a homelab guardian that summarizes health, backup freshness, storage, and failed services;
- a Calibre librarian that proposes metadata and EPUB conversion while preserving the source file;
- a family media concierge that turns an approved request into a Sonarr/Seerr action;
- a Nextcloud assistant that searches approved family documents but cannot delete or share them autonomously.

The agent runtime must degrade safely when SilverBrick is asleep. Core monitoring, backups, DNS, and server administration must never depend on an LLM.

### 3. Full Calibre and EPUB library for iPad

Deploy the **full Calibre package**, not Calibre-Web. The primary requirement is server-side conversion to EPUB with Calibre's command-line tools. Calibre's Content server will provide browser access to the library without removing the conversion and metadata-maintenance capabilities.

Planned components and dependencies:

- `services/calibre/` with Docker Compose and a dedicated profile;
- full Calibre tooling, including `ebook-convert`, `calibredb`, metadata tools, and the Content server;
- application state under `/srv/appdata/calibre`;
- the book library under `/srv/storage/books`;
- a controlled conversion inbox under `/srv/storage/incoming/books`;
- Caddy route and Cloudflare DNS-only record for `books.butenko.online`;
- a separate password-protected administration route at `calibre.butenko.online`;
- a private administration route available only through the approved private network;
- individual family accounts;
- an iPad reading workflow using browser download into Apple Books or a compatible catalog client;
- Uptime Kuma monitoring and Restic protection for application state and metadata.

Conversion must operate on copied input files and write new EPUB output; it must never silently replace the only source copy.

### 4. Internal family chat

**Nextcloud Talk** is installed because it reuses the existing Nextcloud accounts, HTTPS, database recovery, and mobile applications. Private text chat between two family accounts was verified on 2026-07-28.

Remaining work:

- verify private conversations and a family group chat on the web, iOS, and Android clients;
- verify that Talk state is covered by the existing Nextcloud database and application-data recovery path;
- test text chat first, then voice and video calls;
- add TURN or the High Performance Backend only if call testing demonstrates a real need.

### 5. qBittorrent and Sonarr media automation

The services may be installed and tested after the initial Disaster Recovery bootstrap. One small lawful automatic-download test is allowed on the temporary disk. qBittorrent keeps a configurable free-space floor; high-volume monitoring remains deferred until the larger HDD is available.

Order and dependencies:

1. Create `/srv/storage/downloads/torrents` and retain `/srv/storage/media/TV`.
2. Deploy qBittorrent with config under `/srv/appdata/qbittorrent`.
3. Mount `/srv/storage` into qBittorrent as `/data`; download to `/data/downloads/torrents`.
4. Deploy Sonarr with config under `/srv/appdata/sonarr` and the same `/data` mount.
5. Configure Sonarr's TV root as `/data/media/TV` so imports can use hardlinks on the same ext4 filesystem.
6. Deploy **Prowlarr** for centralized indexer management; only lawful indexers or feeds may be configured.
7. Connect Sonarr to qBittorrent with a dedicated category and credentials stored outside Git.
8. Verify Jellyfin sees imported episodes through its existing read-only `/srv/storage/media` mount.
9. Add Caddy DNS-only admin routes, individual authentication, Uptime Kuma monitors, and backup coverage for service configuration.
10. Run one small test and confirm that the download is imported with a hardlink and discovered by Jellyfin.

If a commercial VPN is later required for qBittorrent, use a dedicated network container and route only qBittorrent through it. Do not change the default network route for the entire server.

### 6. Google Photos Takeout migration and SilverBrick Immich ML

This milestone targets the existing final Immich instance on the HP Server. It has two independently reversible tracks: importing Google Photos data with `immich-go`, and moving normal machine-learning work to the SilverBrick RTX 4060 through Immich remote ML.

Takeout import order and gates:

1. Inventory the archives and preserve an immutable copy outside Immich. Never make `/srv/storage/photos` the only copy.
2. Capture the current Immich version and asset, album, job, database, and storage baselines; verify the database dump and photo-file backup before upload.
3. Pin the `immich-go` binary and checksum. Keep the scoped API key in a root-only runtime secret, never Git or an import log.
4. Create a small representative sample with images, video, Google JSON sidecars, albums, time zones, an edited item, and a known duplicate.
5. Run a dry-run, then import only the sample. Verify capture dates, descriptions, GPS data, album membership, duplicate behavior, counts, and an idempotent rerun.
6. Commit reproducible import and verification scripts before the full run. The full import requires enough free space plus an independent photo backup and retains a sanitized report for retry and reconciliation.

Remote ML order and gates:

1. SilverBrick host prerequisites verified on 2026-07-30: Windows build 22631, WSL 2.2.4, NVIDIA driver 610.62, RTX 4060 8 GB, BIOS virtualization, and Tailscale `100.91.171.26`. Docker Desktop 4.84.0 is installed; enabling Windows Virtual Machine Platform plus a restart, Docker GPU access, and the isolated CUDA smoke test remain gates.
2. Deploy the CUDA `immich-machine-learning` image at exactly the same Immich version as the HP Server and persist its model cache.
3. Bind TCP 3003 only to the private Tailscale path and restrict Windows Firewall to `100.65.83.35`; the ML service has no application authentication and must never be public.
4. Add `http://100.91.171.26:3003` as the first ML URL while retaining `http://immich-machine-learning:3003` as fallback during validation.
5. Process only the sample, confirm Smart Search and Face Detection, inspect logs for `CUDAExecutionProvider`, and observe RTX 4060 use.
6. Keep synchronized HP Server and SilverBrick image upgrades in Git. Choose remote-only mode only after explicit acceptance of failed ML jobs whenever SilverBrick is offline; remote-first with local fallback is the safer default.

## Deferred until September 2026

### 7. Replace the storage HDD

- install and SMART-test an 8-16 TB HDD;
- migrate or clone the current `/srv/storage` data;
- preserve the `/srv/storage` mount contract;
- verify ownership, containers, Restic, and Time Machine;
- increase Time Machine limits only after the new disk is verified.

### 8. External or off-site backup

Select an external USB disk, another trusted machine, or object storage. Protect Nextcloud files, Immich photos, important media, Time Machine data where appropriate, and recovery secrets. The current local Restic repository remains on the same HDD and is not protection against loss of that disk.

### 9. AdGuard Home

Deploy only after router access is available. It will provide local DNS through router DHCP and complement, not replace, Cloudflare DNS, `butenko.online`, Caddy, Let's Encrypt, or Tailscale.

## Later maintenance

- review Tailscale ACLs for family and service-to-service access;
- review direct ports currently bound to all interfaces;
- confirm the router has no unintended public forwarding;
- define the final Watchtower/update policy;
- verify Jellyfin Intel VA-API hardware transcoding;
- merge the feature branch after the recovery workflow and new-service plan are stable.

## Application candidates tailored to this homelab

These are recommendations, not approved installation tasks:

- **Open WebUI** as the family-facing AI chat, model selector, knowledge interface, and approval surface for agentic workflows;
- **Seerr** as the simple family request interface in front of Jellyfin and Sonarr, avoiding direct Sonarr access for family members;
- **Bazarr** after Sonarr, for automatic Ukrainian and other preferred subtitles;
- **Paperless-ngx** only if a searchable family archive of scanned documents, invoices, manuals, and warranties is desired;
- **Navidrome** only if music is important enough to justify a dedicated low-resource, multi-user music server and iOS/Android clients instead of Jellyfin's music interface.

These are candidates, not approved installations. Do not deploy them until the owner selects a concrete use case.
