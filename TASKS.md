# Homelab Backlog

This backlog reflects the server audit updated on 2026-07-27. A checked item means only that the stated prerequisite was observed; it does not imply that the entire feature is configured or tested.

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

- [x] Confirm `homelab-backup.timer` is installed and active
- [x] Review the latest backup service result and logs without exposing secrets
- [x] Confirm the latest scheduled Restic job exited successfully
- [ ] Independently verify that the Restic repository is initialized and readable
- [ ] Verify recent snapshots and PostgreSQL dumps without relying only on the timer exit status
- [ ] Perform a test restore into `/srv/storage/restores`
- [ ] Document the restore result and recovery time
- [ ] Store the Restic password securely off-server
- [ ] Add an external or off-site backup target
- [ ] Add backup failure and stale-snapshot alerts

## Time Machine

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
