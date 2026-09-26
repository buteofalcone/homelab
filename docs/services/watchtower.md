# Watchtower

Watchtower runs in global **monitor-only** mode. It checks only explicitly labelled containers and never replaces or restarts them.

No application container is automatically updated. Renovate proposes tracked Compose changes as reviewable GitHub pull requests; deployment remains an explicit `sudo make update` operation.

Watchtower uses label-enable mode and checks only containers carrying:

```yaml
com.centurylinklabs.watchtower.enable: "true"
```

The current labels are limited to Homepage and Beszel hub/agent. Even those containers are monitor-only. All stateful or family-facing service updates remain reviewable Git changes: Caddy, Uptime Kuma, Jellyfin, Nextcloud, Immich, Portainer, Open WebUI, Calibre, Time Machine, qBittorrent, Sonarr, Prowlarr, Radarr, and Seerr.

## Manual update policy

1. Review Renovate's Dependency Dashboard and pull requests.
2. Read release notes for stateful services.
3. Merge the accepted pull request.
4. Run `sudo make update`; it backs up the server and updates only services that were already running.
5. Keep the prior Restic snapshot until post-update verification succeeds.

This favors a recoverable home server over unattended major-version upgrades.
