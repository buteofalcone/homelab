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

## Backup boundary

Current Restic backups deliberately do not include the HDD. The ClickHouse table data and cold source files need a future HDD/off-site backup policy before they are treated as the only copy of anything important.
