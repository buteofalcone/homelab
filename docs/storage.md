# Storage

```text
SSD
├── /                    Ubuntu
├── /opt/homelab         Git repository
└── /srv/appdata
    ├── homepage
    ├── portainer
    ├── beszel
    ├── uptime-kuma
    ├── caddy
    ├── nextcloud
    ├── immich
    ├── jellyfin
    └── _backup-dumps

HDD
└── /srv/storage
    ├── files/nextcloud
    ├── photos
    ├── media
    ├── backups
    ├── downloads
    ├── timemachine
    │   ├── a1502
    │   └── a1466
    └── restores
```

The HDD must be mounted persistently at `/srv/storage` through `/etc/fstab`. Installation aborts if this path is merely an ordinary directory on the system SSD.

Time Machine uses separate Samba shares and reported size limits for each Mac. The temporary HDD defaults to 100 GB per Mac for connection testing. After replacing the disk, only the per-Mac size values in `.env` need to change; the mount and share paths stay stable.
