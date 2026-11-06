#!/usr/bin/env bash
set -euo pipefail

readonly repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly tailscale_ip="${TAILSCALE_IP:-100.65.83.35}"
readonly rdp_dns_name="${RDP_DNS_NAME:-hp-server.tail7cb430.ts.net}"
readonly cert_dir="/var/lib/gnome-remote-desktop/.local/share/gnome-remote-desktop"
readonly cert_file="${cert_dir}/rdp-tls.crt"
readonly key_file="${cert_dir}/rdp-tls.key"

required_commands=(grdctl nft openssl systemctl tailscale)
for command_name in "${required_commands[@]}"; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "Required command is unavailable: ${command_name}" >&2
    exit 1
  fi
done

if ! ip -4 addr show dev tailscale0 | grep -Fq "${tailscale_ip}"; then
  echo "Expected Tailscale address ${tailscale_ip} is not present on tailscale0." >&2
  exit 1
fi

if [[ ! -f "${repo_root}/config/host/rdp-tailscale.nft" ]]; then
  echo "Missing repository firewall configuration." >&2
  exit 1
fi

sudo -v

sudo install -d -m 0755 /etc/homelab
sudo install -m 0644 \
  "${repo_root}/config/host/rdp-tailscale.nft" \
  /etc/homelab/rdp-tailscale.nft
sudo install -m 0644 \
  "${repo_root}/systemd/homelab-rdp-filter.service" \
  /etc/systemd/system/homelab-rdp-filter.service
sudo install -d -m 0755 \
  /etc/systemd/system/gnome-remote-desktop.service.d
sudo install -m 0644 \
  "${repo_root}/systemd/gnome-remote-desktop.service.d/homelab-security.conf" \
  /etc/systemd/system/gnome-remote-desktop.service.d/homelab-security.conf

sudo systemctl daemon-reload
sudo systemctl enable --now homelab-rdp-filter.service
sudo nft list table inet homelab_rdp >/dev/null

if [[ -e "${cert_file}" || -e "${key_file}" ]]; then
  if [[ ! -f "${cert_file}" || ! -f "${key_file}" ]]; then
    echo "Only one RDP TLS file exists; refusing to overwrite partial state." >&2
    exit 1
  fi
  echo "Reusing existing RDP TLS certificate and key."
else
  cert_tmp="$(mktemp -d)"
  trap 'rm -rf "${cert_tmp}"' EXIT
  openssl req -x509 -newkey rsa:3072 -nodes -sha256 -days 825 \
    -subj "/CN=${rdp_dns_name}" \
    -addext "subjectAltName=DNS:${rdp_dns_name},DNS:hp-server,IP:${tailscale_ip}" \
    -keyout "${cert_tmp}/rdp-tls.key" \
    -out "${cert_tmp}/rdp-tls.crt"
  sudo install -d -m 0700 -o gnome-remote-desktop -g gnome-remote-desktop \
    "${cert_dir}"
  sudo install -m 0644 -o gnome-remote-desktop -g gnome-remote-desktop \
    "${cert_tmp}/rdp-tls.crt" "${cert_file}"
  sudo install -m 0600 -o gnome-remote-desktop -g gnome-remote-desktop \
    "${cert_tmp}/rdp-tls.key" "${key_file}"
fi

sudo grdctl --system rdp set-tls-cert "${cert_file}"
sudo grdctl --system rdp set-tls-key "${key_file}"
sudo grdctl --system rdp set-port 3389
sudo grdctl --system rdp set-auth-methods credentials
sudo grdctl --system rdp disable-port-negotiation
sudo grdctl --system rdp disable-view-only

echo
echo "Create dedicated RDP gateway credentials now."
echo "Do not reuse the Ubuntu, Tailscale, or Restic password."
sudo grdctl --system rdp set-credentials

sudo grdctl --system rdp enable
sudo systemctl enable --now gnome-remote-desktop.service

echo
echo "GNOME Remote Login configuration completed."
sudo grdctl --system status
sudo nft list table inet homelab_rdp
ss -ltn 'sport = :3389'
