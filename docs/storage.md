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
    ├── incoming
    │   ├── books
    │   ├── calibre-migration
    │   ├── databases
    │   │   ├── parquet
    │   │   ├── csv
    │   │   └── sql
    │   ├── torrents
    │   ├── media
    │   └── transfer
    ├── timemachine
    │   ├── a1502
    │   └── a1466
    ├── databases
    │   └── clickhouse
    │       ├── data
    │       └── cold
    │           ├── parquet
    │           ├── csv
    │           └── sql
    └── restores
```

The HDD must be mounted persistently at `/srv/storage` through `/etc/fstab`. Installation aborts if this path is merely an ordinary directory on the system SSD.

Time Machine uses separate Samba shares and reported size limits for each Mac. The temporary HDD defaults to 100 GB per Mac for connection testing. After replacing the disk, only the per-Mac size values in `.env` need to change; the mount and share paths stay stable.

The same Samba container exposes `/srv/storage/incoming` as the private `Inbox` share through a separate `homelab` account. This avoids a second process competing for TCP 445. The share is staging only and never exposes application-managed data directories.

ClickHouse keeps table parts and staged cold source files on the HDD under `/srv/storage/databases/clickhouse`. Its temporary query files and logs live on the SSD under `/srv/appdata/clickhouse`. ClickHouse's mark and uncompressed caches are memory caches; it does not transparently create an SSD disk cache for local HDD table parts. The SSD path therefore holds the query working area rather than silently duplicating the cold database.

The private Samba `Inbox/databases/{parquet,csv,sql}` folders are a staging area for
Mac uploads. `make clickhouse-inbox-import` validates the expected extension and
moves files into the matching ClickHouse cold directory without overwriting files.
