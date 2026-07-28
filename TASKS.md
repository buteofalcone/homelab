# Homelab Backlog

This backlog reflects the server audit and roadmap updated on 2026-07-28. A checked item means only that the stated prerequisite was observed; it does not imply that the entire feature is configured or tested.

## Milestone 2A — Repository consistency

- [x] Push the existing local commits to `origin/feature/base-management-stack`
- [x] Update architecture and current-state documentation for the working domain, services, monitoring, and remote management
- [x] Compare declared Compose services with running containers
- [x] Verify Homepage runtime configuration against Git
- [x] Verify tracked Cockpit, RDP, and health systemd configuration against runtime
- [x] Capture the installed backup unit and schedule in Git
- [x] Document the boundary between Git-managed configuration, secrets, and mutable application state
- [x] Audit bootstrap and restore gaps without changing running services
- [x] Validate the Milestone 2A audit
- [x] Commit and push the Milestone 2A audit

## Remote management

- [x] Install Tailscale on HP Server
- [x] Confirm `tailscaled` is active
- [x] Verify the HP Server and SilverBrick are enrolled in the same tailnet
- [x] Enable and verify MagicDNS from SilverBrick
- [x] Verify standard OpenSSH over the Tailscale address and MagicDNS name
- [x] Install Tailscale on SilverBrick
- [ ] Install Tailscale on both MacBooks as needed
- [ ] Review and restrict Tailscale ACLs
- [x] Install Cockpit
- [x] Restrict Cockpit to the HP Server Tailscale address
- [x] Configure GNOME Remote Login / RDP
- [x] Restrict RDP to `tailscale0` with a dedicated nftables rule
- [ ] Test remote recovery access without router port forwarding

## Monitoring

- [x] Create the HP Server system in Beszel Hub
- [x] Store valid Beszel agent credentials without exposing them
- [x] Start and verify the Beszel agent
- [x] Configure Uptime Kuma monitors for Homepage, Portainer, Beszel, Nextcloud, Immich, Jellyfin, Cockpit, and internet connectivity
- [x] Add a storage-mount push monitor
- [x] Add a backup heartbeat monitor
- [x] Configure Telegram notifications in Uptime Kuma
- [x] Configure private family HTTPS with butenko.online, Cloudflare DNS, and public certificates
- [x] Install `smartmontools` (`smartctl` is present)
- [x] Inventory disks with `smartctl --scan`
- [x] Record baseline SMART health without destructive tests
- [x] Add SMART, temperature, and disk-usage alerts

## Backup and recovery

External/off-site backup and physical HDD migration are deferred until September 2026 when another disk is available. The current same-HDD Restic limitation remains accepted and documented in the meantime.

- [x] Confirm `homelab-backup.timer` is installed and active
- [x] Review the latest backup service result and logs without exposing secrets
- [x] Confirm the latest scheduled Restic job exited successfully
- [x] Independently verify that the Restic repository is initialized and readable
- [x] Verify recent snapshots and PostgreSQL dumps without relying only on the timer exit status
- [x] Perform a targeted test restore into `/srv/storage/restores`
- [x] Document the targeted restore result
- [ ] Measure and document a complete application recovery time
- [ ] Store the Restic password securely off-server
- [ ] Add an external or off-site backup target (deferred until September 2026)
- [ ] Add backup failure and stale-snapshot alerts

## Time Machine

Further Time Machine verification is intentionally paused after the successful A1466 backup. A1502, encryption, and file-restore checks are deferred by owner decision, not reported as completed.

- [x] Keep `/srv/storage` as the stable path across the future 500 GB to 8–16 TB migration
- [x] Create `services/timemachine/` with Compose, `smb.conf`, README, and bootstrap helper
- [x] Define separate per-Mac shares and conservative test limits for the temporary disk
- [x] Provision and verify Docker-based Samba and Avahi integration on the server
- [x] Configure SMB with `vfs_fruit`; do not use AFP
- [x] Create a separate A1502 Time Machine share and account
- [x] Create a separate A1466 Time Machine share and account
- [ ] Verify that each Mac can see and mount only its intended share
- [ ] Enable backup encryption on each Mac
- [x] Complete a small first backup from MacBook A1466
- [ ] Test a complete backup from MacBook A1502
- [ ] Test restoration of one file

## Disaster Recovery — active

- [x] Add a read-only host prerequisite check
- [x] Create an offline recovery-secret inventory template without secret values
- [x] Implement an idempotent clean-Ubuntu host package bootstrap
- [ ] Orchestrate Tailscale enrollment handoff, storage verification, secrets, restore, and service verification from one entry point
- [x] Add a safety-gated storage and `/etc/fstab` runbook without automatic formatting
- [x] Verify disposable Nextcloud PostgreSQL import and control tables
- [x] Verify disposable Immich PostgreSQL import and control tables
- [x] Restore and verify management-service state into an isolated audit directory
- [x] Add a single post-restore verification command
- [ ] Complete a measured clean-machine recovery drill

## Git-native agentic workflows — after initial DR bootstrap

- [x] Exclude n8n by owner decision
- [x] Select LM Studio with `qwen/qwen3.5-9b` as the initial SilverBrick runtime and model
- [x] Enable LM Studio authentication and bind the API to the SilverBrick Tailscale address
- [x] Store the dedicated API token in `/etc/homelab/agents.env`
- [x] Verify `LM_STUDIO_API_OK` from the HP Server
- [x] Restrict LM Studio TCP 1234 in Windows Firewall to the HP Server Tailscale address
- [x] Restrict the SilverBrick model API to the HP Server through Tailscale
- [x] Create `services/open-webui/` as the private family AI interface
- [ ] Create a minimal Python agent runtime with prompts, tools, policies, and tests in Git
- [ ] Implement read-only homelab health tools first
- [ ] Add explicit approval gates before every external or state-changing action
- [ ] Persist workflow state under `/srv/appdata/agents` and add backup/restore coverage
- [ ] Add bounded retries and clear offline behavior for SilverBrick
- [x] Add Caddy and Cloudflare DNS-only access for `ai.butenko.online`
- [x] Remove one-time Open WebUI administrator bootstrap credentials from the runtime environment and current container log
- [x] Add an Uptime Kuma health monitor for Open WebUI
- [ ] Build the Calibre librarian workflow
- [ ] Build the approved family media-request workflow

## Full Calibre and EPUB library — after initial DR bootstrap

- [x] Create `services/calibre/` with the full Calibre package
- [x] Include `ebook-convert`, `calibredb`, metadata tools, and the Content server
- [x] Store application state under `/srv/appdata/calibre`
- [x] Store books under `/srv/storage/books`
- [x] Add a controlled `/srv/storage/incoming/books` conversion workflow
- [x] Add Calibre administration and `books.butenko.online` routes, DNS, and monitoring
- [x] Verify conversion of a sample source book to EPUB
- [ ] Verify browser-to-Apple Books or catalog-client workflow on iPad

## Internal family chat — after initial DR bootstrap

- [x] Confirm Nextcloud Talk is not currently installed
- [x] Add a tracked helper to install and enable the `spreed` app
- [ ] Verify private and family group text chat
- [ ] Verify Nextcloud Talk clients on iOS and Android
- [ ] Confirm Nextcloud backup and restore coverage includes Talk state
- [ ] Test calls before deciding whether TURN or the High Performance Backend is needed

## September 2026 storage work

- [ ] Install and SMART-test the new 8-16 TB HDD
- [ ] Migrate data while preserving the `/srv/storage` mount path
- [ ] Verify containers, Restic, Time Machine, ownership, and free space
- [ ] Increase Time Machine limits only after the new disk is verified

## Media automation — after initial DR bootstrap

Installation and connection testing may proceed before September. Automatic or high-volume downloading stays disabled until the larger HDD is installed.

- [ ] Deploy qBittorrent with `/srv/storage` mounted consistently as `/data`
- [ ] Deploy Sonarr with the same `/data` path for hardlink imports
- [ ] Configure `/data/downloads/torrents` and `/data/media/TV`
- [ ] Add Prowlarr if centralized indexer management is required
- [ ] Connect Sonarr to qBittorrent with a dedicated category
- [ ] Verify Jellyfin discovers imported episodes
- [ ] Add monitoring, backup coverage, private HTTPS, and access controls
- [ ] Enable automatic downloading only after the larger HDD is verified

## Jellyfin

- [x] Confirm `/dev/dri/renderD128` exists
- [ ] Install `vainfo`
- [ ] Verify Intel VA-API support on the host
- [ ] Determine the required `video` and `render` group IDs
- [ ] Add the minimal `/dev/dri` device mapping to Compose
- [ ] Verify hardware transcoding from Jellyfin logs and dashboard
- [ ] Confirm direct play still works

## Security and housekeeping

- [ ] Review the purpose and age of ignored `.env.before-restructure` without exposing its contents
- [ ] After a verified secrets backup, decide whether `.env.before-restructure` should be securely removed
- [ ] Investigate why Watchtower is defined but not running; do not start it automatically
- [ ] Review services bound to `0.0.0.0` and document the intended LAN/Tailscale exposure
- [ ] Confirm no public router forwarding exists for SSH, RDP, Cockpit, or application ports
- [ ] Review automatic-update policy for each stateful service

## Documentation

- [x] Create `AGENTS.md`
- [x] Create `TASKS.md`
- [x] Create `docs/current-state.md`
- [x] Document Tailscale, Cockpit, and RDP remote management
- [x] Separate target architecture from observed current state
- [x] Document reproducibility gaps and Milestone 2C acceptance criteria
- [ ] Implement and document a new-server bootstrap procedure
- [ ] Implement and test disaster recovery from Git, database dumps, and Restic
- [ ] Document Time Machine setup and restore
- [ ] Document remote access and loss-of-Tailscale recovery
