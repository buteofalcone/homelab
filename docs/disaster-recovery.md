# Disaster Recovery

This runbook is being built incrementally. It does not yet claim that a complete empty-machine recovery is automated.

## Target workflow

```text
Ubuntu 26.04 -> clone at /opt/homelab -> bootstrap -> supply secrets -> restore -> verify
```

The repository recreates infrastructure. Verified backups restore mutable application state and user data. The offline secret inventory supplies credentials and enrollment access that must never enter Git.

## Safety boundary

- No recovery script may select, partition, format, or add a disk to `/etc/fstab` automatically.
- The operator must identify the disk by model, serial number, filesystem UUID, and expected contents before approving a storage change.
- Containers and restore jobs must not start until `/srv/storage` is confirmed as a separate mount.
- Existing working services are not changed merely to make the repository structure look cleaner.

## Phase 1: host preflight

After Ubuntu packages and authenticated Tailscale enrollment are provisioned, run:

```bash
cd /opt/homelab
make recovery-preflight
```

This command is read-only. It checks the operating system, architecture, required commands, Docker access, core system services, repository location, required directories, the real `/srv/storage` mount, and Docker group membership. It never reads or prints secret values.

`RECOVERY_PREFLIGHT_OK` means the host prerequisites visible to this check are ready. It does not mean application data has been restored.

## Manual steps that remain

The following work is intentionally not automated yet:

1. Install the clean-host package set from official repositories.
2. Enroll the server in Tailscale through an authenticated owner-controlled action.
3. Identify and mount the correct storage device using the future safety-gated storage runbook.
4. Recreate `/etc/homelab` secrets from the offline inventory.
5. Initialize or connect Restic and restore mutable data.
6. Import Nextcloud and Immich PostgreSQL dumps with application-aware checks.
7. Start services and run a single post-restore verification command.
8. Measure a complete clean-machine recovery drill.

Until these phases are implemented and tested, `make install` remains a deployment command for a prepared host, not a complete disaster-recovery bootstrap.

## Offline recovery-secret inventory

Keep this inventory in an encrypted password manager and in a second recovery-safe location. Record values and recovery instructions there, never in this repository.

- Git repository access and any required SSH key recovery;
- local Ubuntu administrator credentials;
- Tailscale owner access and tailnet recovery information;
- root `.env` values for every enabled Compose profile;
- Cloudflare scoped API token and zone-account access;
- Restic repository password and repository location;
- Nextcloud administrator and database credentials;
- Immich administrator and database credentials;
- Portainer administrator recovery information;
- Beszel Hub administrator access plus Agent key and token;
- Uptime Kuma administrator access and Telegram bot replacement procedure;
- RDP gateway credentials;
- separate Time Machine credentials for A1502 and A1466;
- n8n encryption key and database credentials when n8n is deployed;
- qBittorrent, Sonarr, Prowlarr, and Calibre credentials when those services are deployed.

Do not paste tokens into issue trackers, chat messages, screenshots, shell history, or Git commits. Rotate any credential that has been exposed.
