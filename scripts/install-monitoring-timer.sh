#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root

install -m 0644 "${REPO_DIR}/systemd/homelab-health.service" /etc/systemd/system/homelab-health.service
install -m 0644 "${REPO_DIR}/systemd/homelab-health.timer" /etc/systemd/system/homelab-health.timer
install -d -m 0700 /etc/homelab
if [[ ! -f /etc/homelab/monitoring.env ]]; then
  install -m 0600 "${REPO_DIR}/config/monitoring.env.example" /etc/homelab/monitoring.env
fi

systemctl daemon-reload
systemctl enable --now homelab-health.timer
systemctl start homelab-health.service
systemctl --no-pager status homelab-health.timer
