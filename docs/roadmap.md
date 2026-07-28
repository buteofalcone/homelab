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
- restoration of Portainer, Beszel, Uptime Kuma, Caddy, Jellyfin, n8n, and future service state;
- post-restore health checks and a measured recovery drill.

Time Machine is accepted as working after the successful A1466 test. Further A1502, encryption, and file-restore testing is intentionally paused by owner decision.

### 2. n8n

Deploy after the first Disaster Recovery bootstrap milestone so its state is protected from the beginning.

Planned components and dependencies:

- `services/n8n/` with Docker Compose and a dedicated profile;
- n8n application state under `/srv/appdata/n8n`;
- a dedicated PostgreSQL database under `/srv/appdata/n8n-postgres`;
- persistent n8n encryption key in `/etc/homelab`, never Git;
- Caddy route and Cloudflare DNS-only record for `n8n.butenko.online`;
- Uptime Kuma monitor and Restic database dump/restore support;
- LLM API hosted on SilverBrick, reached only through Tailscale.

The SilverBrick LLM runtime is not yet selected. Ollama or another OpenAI-compatible local API may be used. Before enabling workflows, define:

- a stable Tailscale hostname or address;
- the API port and protocol;
- whether the runtime supports authentication;
- a Tailscale ACL that allows only the HP Server to reach the LLM API;
- an n8n timeout/retry policy for times when SilverBrick is asleep or offline.

Core n8n workflows must not make server administration depend on SilverBrick being online.

### 3. Full Calibre and EPUB library for iPad

Deploy the **full Calibre package**, not Calibre-Web. The primary requirement is server-side conversion to EPUB with Calibre's command-line tools. Calibre's Content server will provide browser access to the library without removing the conversion and metadata-maintenance capabilities.

Planned components and dependencies:

- `services/calibre/` with Docker Compose and a dedicated profile;
- full Calibre tooling, including `ebook-convert`, `calibredb`, metadata tools, and the Content server;
- application state under `/srv/appdata/calibre`;
- the book library under `/srv/storage/books`;
- a controlled conversion inbox under `/srv/storage/incoming/books`;
- Caddy route and Cloudflare DNS-only record for `books.butenko.online`;
- a private administration route available only through the approved private network;
- individual family accounts;
- an iPad reading workflow using browser download into Apple Books or a compatible catalog client;
- Uptime Kuma monitoring and Restic protection for application state and metadata.

Conversion must operate on copied input files and write new EPUB output; it must never silently replace the only source copy.

### 4. Internal family chat

Use **Nextcloud Talk** first because Nextcloud and its accounts already exist. The current server audit confirms that the Talk app (`spreed`) is not installed yet.

Planned work:

- add a tracked, repeatable helper for installing and enabling the Talk app;
- verify private conversations and a family group chat on the web, iOS, and Android clients;
- verify that Talk state is covered by the existing Nextcloud database and application-data recovery path;
- test text chat first, then voice and video calls;
- add TURN or the High Performance Backend only if call testing demonstrates a real need.

### 5. qBittorrent and Sonarr media automation

The services may be installed and tested after the initial Disaster Recovery bootstrap. Automatic or high-volume downloading remains disabled until the larger HDD is available, because the temporary disk has no hard application quota.

Order and dependencies:

1. Create `/srv/storage/downloads/torrents` and retain `/srv/storage/media/TV`.
2. Deploy qBittorrent with config under `/srv/appdata/qbittorrent`.
3. Mount `/srv/storage` into qBittorrent as `/data`; download to `/data/downloads/torrents`.
4. Deploy Sonarr with config under `/srv/appdata/sonarr` and the same `/data` mount.
5. Configure Sonarr's TV root as `/data/media/TV` so imports can use hardlinks on the same ext4 filesystem.
6. Add **Prowlarr** if centralized indexer management is required; Sonarr still needs lawful indexer or feed configuration to discover releases.
7. Connect Sonarr to qBittorrent with a dedicated category and credentials stored outside Git.
8. Verify Jellyfin sees imported episodes through its existing read-only `/srv/storage/media` mount.
9. Add Caddy DNS-only admin routes, individual authentication, Uptime Kuma monitors, and backup coverage for service configuration.

If a commercial VPN is later required for qBittorrent, use a dedicated network container and route only qBittorrent through it. Do not change the default network route for the entire server.

## Deferred until September 2026

### 6. Replace the storage HDD

- install and SMART-test an 8-16 TB HDD;
- migrate or clone the current `/srv/storage` data;
- preserve the `/srv/storage` mount contract;
- verify ownership, containers, Restic, and Time Machine;
- increase Time Machine limits only after the new disk is verified.

### 7. External or off-site backup

Select an external USB disk, another trusted machine, or object storage. Protect Nextcloud files, Immich photos, important media, Time Machine data where appropriate, and recovery secrets. The current local Restic repository remains on the same HDD and is not protection against loss of that disk.

### 8. AdGuard Home

Deploy only after router access is available. It will provide local DNS through router DHCP and complement, not replace, Cloudflare DNS, `butenko.online`, Caddy, Let's Encrypt, or Tailscale.

## Later maintenance

- review Tailscale ACLs for family and service-to-service access;
- review direct ports currently bound to all interfaces;
- confirm the router has no unintended public forwarding;
- define the final Watchtower/update policy;
- verify Jellyfin Intel VA-API hardware transcoding;
- merge the feature branch after the recovery workflow and new-service plan are stable.

## Interesting application candidates

These are recommendations, not approved installation tasks:

- **Audiobookshelf** for audiobooks and podcasts, complementary to Calibre and Jellyfin;
- **Mealie** for family recipes, meal planning, and shopping lists;
- **FreshRSS** or **Readeck** for a private reading queue and RSS feeds;
- **Actual Budget** for household budgeting, after a separate backup and security review;
- **Vaultwarden** for family passwords, but only after external backups and a dedicated recovery drill because losing its database or master passwords is high impact;
- **Home Assistant** if home automation hardware is added later;
- **Stirling-PDF** for local PDF conversion and utility tasks.
