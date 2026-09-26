#!/usr/bin/env bash
set -euo pipefail

readonly repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tailscale_ip="${TAILSCALE_IP:-100.65.83.35}"
readonly dropin_dir="/etc/systemd/system/cockpit.socket.d"

if ! ip -4 addr show dev tailscale0 | grep -Fq "${tailscale_ip}"; then
  echo "Expected Tailscale address ${tailscale_ip} is not present on tailscale0." >&2
  exit 1
fi

if [[ ! -f "${repo_root}/systemd/cockpit.socket.d/listen.conf" ]]; then
  echo "Missing repository Cockpit socket override." >&2
  exit 1
fi

sudo -v
sudo apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y cockpit
sudo install -d -m 0755 "${dropin_dir}"
sudo install -m 0644 \
  "${repo_root}/systemd/cockpit.socket.d/listen.conf" \
  "${dropin_dir}/listen.conf"
sudo systemctl daemon-reload
sudo systemctl enable --now cockpit.socket
sudo systemctl restart cockpit.socket

if ! ss -ltn 'sport = :9090' | grep -Fq "${tailscale_ip}:9090"; then
  echo "Cockpit is not listening on the expected Tailscale address." >&2
  exit 1
fi

echo "Cockpit is available at https://${tailscale_ip}:9090"
