# Architecture

This document describes the target architecture. The observed server state is recorded in `docs/current-state.md`; architecture decisions must never be used as a reason to remove working services or revert the server to an older design.

## Principles

- One understandable Ubuntu server; no Kubernetes, clustering, HA, Ansible, or Terraform.
- Git is the source of truth for Compose files, static configuration, host units, provisioning scripts, and recovery instructions.
- Secrets and application data never enter Git. Git describes how to recreate or restore them.
- Working runtime is migrated gradually. Avoid large simultaneous repository refactors.
- Existing `compose/` remains in place. New services may start under `services/<name>/` and existing services may move only one at a time after a separate review.
- Every destructive or storage-changing operation requires an explicit verification and recovery path.

## Current service model

The root Compose project includes one file per service in `compose/`. All containers that need reverse-proxy access share the `homelab` bridge network.

Base services have no Compose profile. Application workloads use profiles:

- `nextcloud`
- `immich`
- `jellyfin`
- `beszel-agent`

Caddy terminates HTTPS for `*.butenko.online`. Cloudflare provides public DNS-only records pointing to the private Tailscale address, and its DNS API is used only for ACME DNS challenges. Let's Encrypt supplies publicly trusted certificates. AdGuard Home will later add local DNS after router access is available; it will complement, not replace, this design.

## State boundaries

```text
/opt/homelab   Git checkout: desired infrastructure and recovery logic
/etc/homelab   host-only secrets and generated host configuration
/srv/appdata   container state, application databases, and caches on SSD
/srv/storage   user data and local backups on the replaceable HDD
```

Static configuration in runtime must either be mounted directly from Git or installed from a tracked source file. Mutable application state is restored from verified backups. Secrets are recreated from an offline record or supplied interactively.

## Storage migration

The stable contract is the mount path `/srv/storage`, not the physical disk size. The temporary 500 GB HDD will later be cloned or migrated to an 8–16 TB HDD and mounted at the same path. Compose paths and service configuration must not change because of that replacement.

## Recovery target

The desired workflow is:

```text
Ubuntu -> git clone -> bootstrap -> restore -> verified working server
```

This target is not yet achieved. The current scripts deploy containers on a prepared host and can extract Restic data, but they do not yet provision the complete host or perform a full application-aware restore. The audited gaps and acceptance criteria are in `docs/reproducibility-audit.md`.

## Roadmap

1. Repository consistency and recovery audit.
2. Docker-based Time Machine service under `services/timemachine/`.
3. Replacement of the temporary HDD without changing service paths.
4. Verified Time Machine and homelab restores, plus an external/off-site copy.
5. AdGuard Home after router access becomes available.
