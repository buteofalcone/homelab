#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root
load_env

printf 'STEP_UPDATE_TOOLS_APT\n'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y cockpit-packagekit packagekit nala

printf 'STEP_UPDATE_TOOLS_COCKPIT\n'
systemctl enable --now cockpit.socket
systemctl try-restart cockpit.socket

printf 'STEP_UPDATE_TOOLS_WATCHTOWER\n'
cd "${REPO_DIR}"
compose up -d watchtower

printf 'STEP_UPDATE_TOOLS_VERIFY\n'
dpkg-query -W -f='${Package} ${Status}\n' cockpit-packagekit packagekit nala
systemctl is-active cockpit.socket
docker inspect watchtower --format 'watchtower state={{.State.Status}} image={{.Config.Image}}'
docker inspect watchtower --format '{{range .Config.Env}}{{println .}}{{end}}' \
  | grep -qx 'WATCHTOWER_MONITOR_ONLY=true'
printf 'UPDATE_TOOLS_INSTALL_OK\n'
