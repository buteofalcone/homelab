# Time Machine and private SMB Inbox

Docker-based Samba Time Machine target for the two family Macs. Samba runs in a container; the host Avahi daemon publishes the two shares through Bonjour.

## Safety model

- Data lives only under `/srv/storage/timemachine`.
- A1502 and A1466 use separate shares, accounts, password files, and advertised size limits.
- The temporary 500 GB HDD defaults to 100 GB per Mac. These are conservative test limits, not the final backup policy.
- Watchtower updates are disabled for this service.
- The bootstrap refuses to continue unless `/srv/storage` is a real mount.
- Passwords live under `/etc/homelab/timemachine` and `/etc/homelab/fileshare` with root-only permissions and never enter Git.

Samba's `fruit:time machine max size` controls the disk size reported to each Mac. It is an approximate safeguard based on Time Machine sparsebundle contents, not a filesystem-enforced quota. Do not store unrelated files inside these shares.

## Provisioning

Run from an interactive SSH session:

```bash
cd /opt/homelab
make timemachine-bootstrap
```

The script asks for two dedicated passwords, creates the storage directories, installs the tracked Avahi service definition, builds the Samba image, and starts only the Time Machine profile.

Accounts and shares:

| Mac | SMB account | Share |
| --- | --- | --- |
| MacBook A1502 | `tm-a1502` | `TimeMachine-A1502` |
| MacBook A1466 | `tm-a1466` | `TimeMachine-A1466` |
| Private file staging | `homelab` | `Inbox` |

Do not reuse Ubuntu, Tailscale, RDP, Restic, or application passwords.

## Inbox share

`Inbox` exposes only `/srv/storage/incoming` over private SMB. It is available through the trusted LAN and Tailscale; port 445 must never be forwarded from the router.

If the dedicated `homelab` credential is lost or rejected, reset only that credential with `make smb-inbox-reset-password`. The command replaces the root-only secret, recreates Samba, verifies its health and account database, and does not modify Inbox or Time Machine data.

```text
Inbox/
├── books/                individual sources for controlled Calibre import
├── calibre-migration/    one complete, closed Calibre library for migration
├── calibre-merge/        one additional closed Calibre library for merge
├── google-photos-takeout/
│   ├── sample/           small representative Takeout test set
│   └── full/             immutable complete Takeout archives
├── torrents/             staging only; Seerr and the qBittorrent UI remain preferred
├── media/                manual media staging
└── transfer/             temporary general file transfer
```

On the Mac, use Finder **Go -> Connect to Server** and enter `smb://100.65.83.35/Inbox`. Use the dedicated `homelab` account. The Time Machine accounts cannot access this share.

Do not place files directly inside live Calibre, Nextcloud, Jellyfin, Sonarr, or Radarr data directories. `Inbox` is deliberately a staging boundary.

## Mac test procedure

1. Connect the Mac to the trusted home LAN.
2. In Finder choose **Go -> Connect to Server**.
3. Enter `smb://192.168.1.130/TimeMachine-A1502` or `smb://192.168.1.130/TimeMachine-A1466`.
4. Authenticate with the matching dedicated account.
5. Confirm that the empty share mounts and is visible in Time Machine settings.
6. Do not start a full backup on the temporary HDD yet.

Bonjour should also show `hp-server Time Machine`. Manual SMB connection remains the recovery path if multicast discovery is unavailable.

## Verification

```bash
docker compose --profile timemachine ps timemachine
docker compose logs --tail=100 timemachine
docker compose exec timemachine testparm -s
systemctl is-active avahi-daemon.service
journalctl -u avahi-daemon.service --since '10 minutes ago' --no-pager
```

Expected result: the container is healthy, both shares appear in `testparm`, and the Avahi log reports that `hp-server Time Machine` was successfully established.

During an active backup Samba may briefly log `fruit_tmsize_do_dirent ... failed` while macOS rewrites the sparsebundle `Info.plist`. If the `band-size` key is present after the backup and the warning stops, the reported-size calculation can resume normally. Investigate before continuing only if the warning persists after backup completion or the share stops mounting.

## After installing the 8-16 TB disk

Keep the mount path `/srv/storage` unchanged. Update only these values in `/opt/homelab/.env` to the approved per-Mac limits, for example:

```dotenv
TIMEMACHINE_A1502_MAX_SIZE=2T
TIMEMACHINE_A1466_MAX_SIZE=2T
```

Then recreate only this container:

```bash
make timemachine
```

No Compose, Samba, share path, account, or Mac configuration redesign is required.
