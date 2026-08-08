# Google Photos to Immich migration

This service prepares a controlled Google Photos Takeout import without storing API keys or personal media in Git.

## Pinned tools

- HP Server Immich: `v3.0.3`
- `immich-go`: `v0.32.0`

Before connecting SilverBrick Remote ML, replace the moving `release` setting in the live root-only `.env` with the already-running exact version. This does not cross an Immich upgrade boundary; the script refuses to proceed unless the live image reports `v3.0.3`, retains a root-only rollback copy, recreates only the server and local ML containers, and verifies recovery:

```bash
sudo make immich-pin-version
```

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

Create a dedicated temporary API key in **Immich → Account settings → API Keys**. Grant the permissions documented by `immich-go`: `asset.read`, `asset.statistics`, `asset.update`, `asset.upload`, `asset.copy`, `asset.delete`, `asset.download`, `album.create`, `album.read`, `albumAsset.create`, `server.about`, `stack.create`, `tag.asset`, `tag.create`, and `user.read`. Add `job.create` and `job.read` before a real import if background jobs will be paused. Revoke this key when migration is complete.

Store it without echoing it or committing it:

```bash
make immich-migration-api-key
make immich-migration-api-key-verify
```

Validation calls the local Immich `/api/users/me` endpoint through a temporary root-only curl configuration, so the key is not exposed in the process list or logs.

Prepare a separate small Google Takeout export containing representative JPEG, HEIC, video, album, and JSON sidecar data. Copy the ZIP archive(s), or one unpacked Takeout tree, into `Inbox/google-photos-takeout/sample`. Do not mix ZIP files and unpacked files. The sample is limited to 5 GiB.

Then run:

```bash
make immich-takeout-preflight
make immich-takeout-dry-run
```

Preflight rejects symlinks, corrupt ZIP archives, samples without JSON metadata, samples without supported media, and oversized samples. Dry-run uses two concurrent tasks, preserves archived and unmatched files, reconstructs named albums and people/takeout tags, excludes trash and partner-shared items, and refuses overwrite. It verifies that the Immich asset count, album count, and `/srv/storage/photos` byte size remain unchanged.
