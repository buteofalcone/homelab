# Storage

```text
SSD
├── /                  Ubuntu
├── /opt/homelab       Git repository
└── /srv/appdata       Container state

HDD
└── /srv/storage
    ├── files
    ├── backups
    └── downloads
```

The HDD should be mounted persistently through `/etc/fstab`.
