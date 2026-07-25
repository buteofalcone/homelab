# Homelab Backlog

This backlog reflects the server audit performed on 2026-07-25. A checked item means only that the stated prerequisite was observed; it does not imply that the entire feature is configured or tested.

## Remote management

- [x] Install Tailscale on HP Server
- [x] Confirm `tailscaled` is active
- [ ] Verify the HP Server is enrolled in the intended tailnet
- [ ] Enable and verify MagicDNS
- [ ] Verify SSH over the Tailscale address or MagicDNS name
- [ ] Install Tailscale on SilverBrick and both MacBooks as needed
- [ ] Review and restrict Tailscale ACLs
- [ ] Install Cockpit
- [ ] Restrict Cockpit access to `tailscale0`
- [ ] Configure GNOME Remote Desktop / RDP
- [ ] Restrict RDP access to `tailscale0`
- [ ] Test remote recovery access without router port forwarding

## Monitoring

- [ ] Create the HP Server system in Beszel Hub
- [ ] Store valid Beszel agent credentials without exposing them
- [ ] Start and verify the Beszel agent
- [ ] Configure Uptime Kuma monitors for Homepage, Portainer, Beszel, Nextcloud, Immich, Jellyfin, Cockpit, and internet connectivity
- [ ] Add a storage-mount push monitor
- [ ] Add a backup heartbeat monitor
- [ ] Configure Telegram or email notifications
- [x] Install `smartmontools` (`smartctl` is present)
- [ ] Inventory disks with `smartctl --scan`
- [ ] Record baseline SMART health without destructive tests
- [ ] Add SMART, temperature, and disk-usage alerts

## Backup and recovery

- [x] Confirm `homelab-backup.timer` is installed and active
- [ ] Review the latest backup service result and logs without exposing secrets
- [ ] Verify that the Restic repository is initialized and readable
- [ ] Verify recent snapshots and PostgreSQL dumps
- [ ] Perform a test restore into `/srv/storage/restores`
- [ ] Document the restore result and recovery time
- [ ] Store the Restic password securely off-server
- [ ] Add an external or off-site backup target
- [ ] Add backup failure and stale-snapshot alerts

## Time Machine

- [ ] Decide on a dedicated HDD: 2 TB minimum, 4 TB recommended
- [ ] Decide the final mount path and per-Mac quotas
- [ ] Install and configure Samba and Avahi
- [ ] Configure SMB with `vfs_fruit`; do not use AFP
- [ ] Create a separate A1502 Time Machine share or account
- [ ] Create a separate A1466 Time Machine share or account
- [ ] Enable backup encryption on each Mac
- [ ] Test a complete backup from each Mac
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
- [ ] Document a new-server bootstrap procedure
- [ ] Document disaster recovery from Git, database dumps, and Restic
- [ ] Document Time Machine setup and restore
- [ ] Document remote access and loss-of-Tailscale recovery
