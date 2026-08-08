#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root

install -m 0644 "${REPO_DIR}/systemd/homelab-backup.service" /etc/systemd/system/
install -m 0644 "${REPO_DIR}/systemd/homelab-backup.timer" /etc/systemd/system/

systemctl daemon-reload
systemctl enable --now homelab-backup.timer
systemctl list-timers homelab-backup.timer
