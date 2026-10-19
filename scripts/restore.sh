#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root
load_env

snapshot="${1:-latest}"
target="${2:-/srv/storage/restores/${snapshot}}"

export RESTIC_REPOSITORY RESTIC_PASSWORD_FILE

install -d -m 0750 "${target}"
restic restore "${snapshot}" --target "${target}"

echo "Restored ${snapshot} into ${target}"
echo "Review the restored files before copying them into live paths."
