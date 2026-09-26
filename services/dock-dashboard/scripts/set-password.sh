#!/usr/bin/env bash
set -Eeuo pipefail
[[ "${EUID}" -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
exec /srv/appdata/hp-dashboard/venv/bin/python \
  /opt/homelab/services/dock-dashboard/scripts/configure_auth.py \
  --config /etc/homelab/dashboard.env --group hp-dashboard --username butenko
