# Google Photos to Immich migration

This service prepares a controlled Google Photos Takeout import without storing API keys or personal media in Git.

## Pinned tools

- HP Server Immich: `v3.0.3`
- `immich-go`: `v0.32.0`
- Linux x86_64 archive SHA-256: `6e2ad86bafdadb9466d6515de7cb882726c0aea1a21d51164dff361d7d480a97`

`immich-go v0.32.0` is the first release with Immich V3 compatibility. The installer downloads the official GitHub release, verifies the checksum, and installs it under `/usr/local/lib/homelab/immich-go/v0.32.0`.

## Staging

Run:

```bash
sudo make immich-migration-bootstrap
```

The private SMB `Inbox` then contains:

```text
google-photos-takeout/
├── sample/   small representative test input
└── full/     complete immutable Takeout archives
```

Keep the original Takeout archives outside Immich as an independent source copy. The next gate is a dry-run against `sample`; no full import is allowed until dates, JSON pairing, albums, duplicates, and storage growth are verified.
