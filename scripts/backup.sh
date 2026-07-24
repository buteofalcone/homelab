#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root
load_env

export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE

command -v restic >/dev/null 2>&1 || die "Restic is not installed."
[[ -f "${RESTIC_PASSWORD_FILE}" ]] || die "Run restic-init.sh first."

"${REPO_DIR}/scripts/database-dumps.sh"

restic backup \
  /srv/appdata \
  /opt/homelab \
  /etc/homelab \
  --exclude='/srv/appdata/nextcloud/postgres' \
  --exclude='/srv/appdata/immich/postgres' \
  --exclude='/opt/homelab/.git' \
  --exclude='/opt/homelab/.env' \
  --exclude='*.log' \
  --tag homelab

restic forget \
  --keep-daily 7 \
  --keep-weekly 5 \
  --keep-monthly 12 \
  --prune

restic check --read-data-subset="${RESTIC_CHECK_SUBSET:-5%}"
