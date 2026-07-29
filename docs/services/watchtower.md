# Watchtower

Watchtower is currently **intentionally stopped**. Its rolling-restart validation rejects the `homepage` dependency on `homepage-docker-proxy`, so it must not be started automatically.

Therefore no application container is automatically updated today. The labels below describe the future opt-in policy only; they do not cause updates while Watchtower is stopped.

If the compatibility issue is deliberately resolved, Watchtower must run in label-enable mode and update only containers carrying:

```yaml
com.centurylinklabs.watchtower.enable: "true"
```

The current opt-in labels are limited to Homepage and Beszel hub/agent. All stateful or family-facing services remain manual: Caddy, Uptime Kuma, Jellyfin, Nextcloud, Immich, Portainer, Open WebUI, Calibre, Time Machine, qBittorrent, Sonarr, and Prowlarr.

## Manual update policy

1. Check available image updates during routine maintenance.
2. Run the repository backup/audit first.
3. Update one stack at a time with its Compose file, then verify its health and the public Caddy route.
4. For databases or data-bearing services, keep the prior Restic snapshot until the post-update verification succeeds.

This favors a recoverable home server over unattended major-version upgrades.
