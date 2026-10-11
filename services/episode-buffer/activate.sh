#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"
require_root

readonly config_file="/etc/homelab/episode-buffer.env"
[[ -s "${config_file}" ]] || die 'Episode buffer is not configured.'

printf '%s\n' \
  'This enables automatic Sonarr episode recycling for series tagged rolling-3.' \
  'Files are retained in /srv/storage/recycle/sonarr for the configured retention period.'
read -r -p 'Type ACTIVATE_EPISODE_BUFFER to continue: ' confirmation
[[ "${confirmation}" == 'ACTIVATE_EPISODE_BUFFER' ]] || die 'Activation cancelled.'

systemctl stop homelab-episode-buffer.timer
sed -i 's/^EPISODE_BUFFER_DRY_RUN=.*/EPISODE_BUFFER_DRY_RUN=true/' "${config_file}"
"${REPO_DIR}/services/episode-buffer/run.sh" reset-baseline
sed -i 's/^EPISODE_BUFFER_DRY_RUN=.*/EPISODE_BUFFER_DRY_RUN=false/' "${config_file}"
if ! "${REPO_DIR}/services/episode-buffer/run.sh" verify; then
  sed -i 's/^EPISODE_BUFFER_DRY_RUN=.*/EPISODE_BUFFER_DRY_RUN=true/' "${config_file}"
  die 'Activation verification failed; dry-run mode was restored.'
fi
systemctl enable --now homelab-episode-buffer.timer
printf 'EPISODE_BUFFER_ACTIVATE_OK\n'
