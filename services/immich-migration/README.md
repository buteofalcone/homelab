# Google Photos to Immich migration

This service implements a gated, repeatable migration without committing API
keys or personal metadata. Versions remain pinned to Immich `v3.0.3` and
`immich-go v0.32.0`; upgrading is a separate maintenance workflow.

## Safety and storage

The Takeout tree is immutable. `storage-plan.sh` is read-only by default and
prints the exact UUID/mount/fstab plan. Apply mode requires the one-time token
printed by the plan, refuses busy mounts, backs up `fstab`, and rolls back if
UUID or Takeout checks fail. Do not provide that token until the plan is
reviewed immediately before execution.

`migrate-library.sh` separately requires a copy approval token. It creates and
tests a PostgreSQL dump, runs `rsync` without `--delete`, checksum-verifies the
copy, switches only Immich server, checks `/data` and the API, and restores the
old binding on failure. `/srv/storage/photos` remains untouched as rollback.

## Inventory and representative sample

After the separately approved storage phase:

```bash
make immich-takeout-inspect
make immich-takeout-sample
make immich-takeout-preflight
make immich-takeout-dry-run
```

The manifest uses relative paths and hashed identifiers; it never logs
descriptions or coordinates. Reports count malformed/direct/inferred/missing
sidecars, extensions, albums, numbered/edited names, motion candidates and
optional exact-hash duplicate candidates. The copy-only sample keeps sidecars
and album metadata for image/video/HEIC/GPS/date/favorite/edited/motion cases.
Its generated `sample-manifest.json` is explicitly excluded from immich-go
discovery so it cannot be misreported as an unsupported Google sidecar.

Create a dedicated import API key with the permissions required by
`immich-go`, including `album.delete` for the exact-name excluded-album cleanup,
store it with `make immich-migration-api-key`, and never place it in Git or
command-line arguments. The cleanup snapshots pre-existing `Без назви` album
IDs, imports every asset, and deletes only matching albums first observed in
that run through the official API. It never deletes their assets or a
pre-existing same-name album.

Run the real sample twice:

```bash
make immich-takeout-sample-import
make immich-import-verify
make immich-takeout-sample-import
ACCEPT_SAMPLE=1 make immich-import-verify
```

Acceptance requires a positive first asset delta, zero second asset/album
delta, and no latest import error marker. Later idempotent reruns do not
invalidate that historical evidence. Capture time/timezone, GPS, albums,
favorites, descriptions, video and motion cases must also be spot-checked in
Immich before acceptance.

Only then can `make immich-takeout-full-import` pass its gates: exact mount
UUID, recent verified DB dump, accepted sample, healthy API, and free space of
at least `1.5 × Takeout bytes + 100 GiB`. Concurrency is two, overwrite is
disabled, and repeated runs use the same device identity. Suspicious
duplicates are reported, never deleted.

Verification emits JSON and Markdown under `wd3tb/ai/manifests`. Application
logs use the supplied logrotate policy; Docker logs use Compose size limits.
