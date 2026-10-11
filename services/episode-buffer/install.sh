#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/../../scripts/lib.sh"
require_root

[[ -s /etc/homelab/episode-buffer.env ]] || die 'Run make episode-buffer-configure first.'
install -m 0644 "${REPO_DIR}/systemd/homelab-episode-buffer.service" /etc/systemd/system/
install -m 0644 "${REPO_DIR}/systemd/homelab-episode-buffer.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now homelab-episode-buffer.timer
systemctl start homelab-episode-buffer.service
systemctl --no-pager --full status homelab-episode-buffer.timer
printf 'EPISODE_BUFFER_INSTALL_OK mode=dry-run\n'
