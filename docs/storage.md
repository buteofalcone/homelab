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
    └── restores
```

The HDD must be mounted persistently at `/srv/storage` through `/etc/fstab`. Installation aborts if this path is merely an ordinary directory on the system SSD.
