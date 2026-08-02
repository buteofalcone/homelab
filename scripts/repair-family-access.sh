#!/usr/bin/env bash
set -Eeuo pipefail

readonly repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "${repo_dir}/scripts/lib.sh"

require_root
load_env
mountpoint -q /srv/storage || die '/srv/storage is not a mounted filesystem.'

echo 'STEP_SMB_INBOX_RECOVER'
compose --profile timemachine up -d timemachine

for _ in {1..30}; do
  health="$(docker inspect timemachine --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' 2>/dev/null || true)"
  [[ ${health} == healthy ]] && break
  sleep 2
done
[[ ${health:-} == healthy ]] || die "Time Machine/Samba did not become healthy: ${health:-missing}"
ss -ltn 'sport = :445' | grep -q ':445' || die 'Samba is healthy but TCP 445 is not listening.'

echo 'STEP_JELLYFIN_MEDIA_WRITE_ENABLE'
compose --profile jellyfin up -d jellyfin
docker exec jellyfin sh -eu -c '
  for directory in /media/Movies /media/TV; do
    test -d "${directory}"
    probe="${directory}/.jellyfin-write-probe.$$"
    : > "${probe}"
    rm -f -- "${probe}"
  done
'

echo 'STEP_SSH_RECOVER'
sshd -t
systemctl restart ssh.service
systemctl is-active --quiet ssh.service || die 'SSH service is not active.'
ss -ltn 'sport = :22' | grep -q ':22' || die 'SSH is active but TCP 22 is not listening.'

echo 'STEP_RDP_AUDIT'
systemctl is-active --quiet gnome-remote-desktop.service \
  || die 'GNOME Remote Desktop is not active; run sudo make rdp-reconfigure.'
ss -ltn 'sport = :3389' | grep -q ':3389' \
  || die 'GNOME Remote Desktop is active but TCP 3389 is not listening.'

echo 'FAMILY_ACCESS_REPAIR_OK'
