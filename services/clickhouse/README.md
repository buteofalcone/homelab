# ClickHouse

ClickHouse is a private analytical database for cold Parquet, CSV and SQL datasets.

## Storage layout

```text
HDD: /srv/storage/databases/clickhouse
├── data/              ClickHouse table data
└── cold/
    ├── parquet/       source Parquet files
    ├── csv/           source CSV files
    └── sql/           source SQL files

SSD: /srv/appdata/clickhouse
├── tmp/               query spill and temporary files
└── log/               ClickHouse logs
```

The HDD is mounted at `/srv/storage`; bootstrap refuses to run when it is not mounted. ClickHouse's RAM caches stay in RAM. For local HDD data, ClickHouse has no transparent persistent SSD cache; the SSD is used for temporary working files and logs.

## Provision and verify

```bash
cd /opt/homelab
sudo make clickhouse-bootstrap
sudo make clickhouse-verify
```

The Docker ports are bound only to `127.0.0.1` on the HP Server. This prevents an unauthenticated analytical database from becoming a LAN service.

Use the local client on the server:

```bash
docker exec -it clickhouse clickhouse-client
```

From a Tailscale device, create a tunnel first:

```bash
ssh -L 8123:127.0.0.1:8123 butenko@hp-server
```

Then use `http://127.0.0.1:8123` from your workstation. Do not place source files directly in `data`; use the matching `cold/parquet`, `cold/csv`, or `cold/sql` directory.

## Copying source files from a Mac

The database directories are deliberately not exposed by Samba: ClickHouse owns its
live `data` directory, and the cold source files should not be edited while a query
is using them. Instead, provision the private SMB staging folders once:

```bash
cd /opt/homelab
sudo make clickhouse-inbox-bootstrap
```

In Finder, connect with the existing `homelab` SMB account and copy files into:

```text
smb://192.168.1.130/Inbox/databases/parquet/
smb://192.168.1.130/Inbox/databases/csv/
smb://192.168.1.130/Inbox/databases/sql/
```

When the copy has finished, move the staged regular files into the matching cold
directory on the HDD:

```bash
sudo make clickhouse-inbox-import
```

The command accepts `.parquet` in `parquet`, `.csv` in `csv`, and `.sql` or
`.sql.gz` in `sql`. It never overwrites an existing cold file: conflicts remain in
Inbox for review. Do not use Inbox as the permanent copy of a dataset.

## Backup boundary

Current Restic backups deliberately do not include the HDD. The ClickHouse table data and cold source files need a future HDD/off-site backup policy before they are treated as the only copy of anything important.
