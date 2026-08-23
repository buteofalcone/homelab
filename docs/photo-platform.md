# Long-term local photo platform

## Architecture

```text
immutable Takeout on wd3tb
  -> immich-go v0.32.0 -> Immich v3.0.3 API
       -> /srv/storage/wd3tb/immich (media and derivatives)
       -> PostgreSQL + Valkey on /srv/appdata (SSD)
       -> remote Immich ML on SilverBrick:3003 (Tailscale only)
       -> photo-ai-api durable pull queue -> SilverBrick GPU worker
            -> separate PostgreSQL/pgvector metadata index
            -> official Immich hierarchical tag API
```

Normal Immich operation has no local machine-learning container. If
SilverBrick is offline, the UI, uploads and database remain available and ML
jobs wait. An operator may deliberately start the `immich-ml-fallback` profile
during an outage, but it is never part of `make immich`.

## Physical layout

```text
/srv/storage/wd3tb/
├── takeout-extracted/Takeout/Google Фото/  # immutable
├── immich/
│   ├── upload/  library/  thumbs/  encoded-video/  profile/  backups/
└── ai/
    ├── manifests/  cache/  exports/
    └── logs/

/srv/appdata/immich/postgres/               # SSD
/srv/appdata/immich/model-cache/            # optional fallback cache
/srv/appdata/photo-pipeline/postgres/        # SSD, separate AI DB
```

The UUID mount is required and intentionally has no `nofail`. Every import,
AI reconcile, backup bootstrap and storage migration checks the exact mount
root and UUID so a missing disk cannot redirect writes to the system SSD.

## Ordered gates

1. Run `make immich-storage-plan`; review output. Apply requires fresh explicit
   authorization and its exact one-time token.
2. Verify the rebooted mount, create layout, and run the copy/switch workflow.
3. Inventory Takeout and build the representative sample.
4. Dry-run, import sample, inspect metadata, repeat sample, accept idempotency.
5. Run full import only after its DB-dump, free-space and acceptance gates.
6. Deploy and verify SilverBrick CUDA ML, then configure the remote-only URL.
7. Bootstrap Photo AI, reconcile a 100-asset batch, validate VRAM/results and
   restart recovery, then reconcile the remaining assets.
8. Verify both database restores in isolated containers and add an external
   Restic media target. Until that exists, report
   `MEDIA_BACKUP_STATUS=unprotected` and retain Takeout plus old storage.

## Recovery contracts

- Takeout is never removed or mutated.
- Storage copies never use `--delete`; the old library is preserved.
- Immich PostgreSQL is dumped before media binding changes or full import.
- External software never writes Immich PostgreSQL. Verification may use
  read-only aggregate SQL; enrichment uses official APIs only.
- AI leases expire back to `retry`, results are unique by job, and model or
  pipeline revisions generate selective new work.
- Suspected exact/near duplicates are reports/groups only. Deletion requires a
  separate human review and is outside this workflow.

Upgrade Immich only in a maintenance window after release-note review and a
verified dump. Update server, optional fallback and SilverBrick CUDA images to
the same version, then validate API/database migrations and both ML paths.
Downgrades are unsupported.
