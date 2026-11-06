#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"
require_root

"${REPO_DIR}/services/episode-buffer/run.sh" verify
systemctl is-enabled --quiet homelab-episode-buffer.timer
systemctl is-active --quiet homelab-episode-buffer.timer
systemctl --no-pager --full status homelab-episode-buffer.timer
printf 'EPISODE_BUFFER_SYSTEM_VERIFY_OK\n'
