#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${EUID}" -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
service_dir="${repo_dir}/services/dock-dashboard"
[[ "${repo_dir}" == /opt/homelab ]] || { echo "Install from /opt/homelab" >&2; exit 1; }
mountpoint -q /srv/storage || { echo "/srv/storage is not mounted" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends python3-venv adb smartmontools lm-sensors nftables

getent group hp-dashboard >/dev/null || groupadd --system hp-dashboard
if ! id hp-dashboard >/dev/null 2>&1; then
  useradd --system --gid hp-dashboard --home-dir /nonexistent --shell /usr/sbin/nologin hp-dashboard
fi

install -d -m 0700 /etc/homelab
python3 "${repo_dir}/scripts/render-service-catalog.py" --check || {
  echo "Homepage catalog output is stale; run scripts/render-service-catalog.py" >&2
  exit 1
}
install -m 0640 -o root -g hp-dashboard "${repo_dir}/config/service-catalog.json" /etc/homelab/dashboard-service-catalog.json

install -d -m 0750 -o root -g hp-dashboard /srv/appdata/hp-dashboard
if [[ ! -x /srv/appdata/hp-dashboard/venv/bin/python ]]; then
  python3 -m venv /srv/appdata/hp-dashboard/venv
fi
/srv/appdata/hp-dashboard/venv/bin/pip install --disable-pip-version-check --no-cache-dir -r "${service_dir}/requirements.txt"

install -d -m 0755 /usr/local/libexec
install -m 0755 -o root -g root "${service_dir}/scripts/collector.py" /usr/local/libexec/hp-dashboard-collector
install -m 0755 -o root -g root "${service_dir}/scripts/action_helper.py" /usr/local/libexec/hp-dashboard-action
install -m 0755 -o root -g root "${service_dir}/scripts/firewall.py" /usr/local/libexec/hp-dashboard-firewall

if [[ ! -f /etc/homelab/dashboard.env ]]; then
  /srv/appdata/hp-dashboard/venv/bin/python "${service_dir}/scripts/configure_auth.py" \
    --config /etc/homelab/dashboard.env --group hp-dashboard --username butenko --generate-bootstrap
fi

/srv/appdata/hp-dashboard/venv/bin/python - /etc/homelab/dashboard.env /etc/homelab/caddy.env <<'PY'
import os
import re
import sys
import tempfile

dashboard_path, caddy_path = sys.argv[1:]
values = {}
for line in open(dashboard_path, encoding="utf-8"):
    match = re.match(r"^([A-Z0-9_]+)=(.*)$", line.strip())
    if match:
        value = match.group(2)
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
            value = value[1:-1]
        values[match.group(1)] = value
token = values.get("DASHBOARD_PROXY_TOKEN")
if not token:
    raise SystemExit("Dashboard proxy token is missing")
lines = []
if os.path.exists(caddy_path):
    with open(caddy_path, encoding="utf-8") as handle:
        lines = [line for line in handle if not line.startswith("DASHBOARD_PROXY_TOKEN=")]
lines.append(f"DASHBOARD_PROXY_TOKEN='{token}'\n")
fd, temporary = tempfile.mkstemp(prefix=".caddy.env.", dir=os.path.dirname(caddy_path))
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    handle.writelines(lines)
    handle.flush()
    os.fsync(handle.fileno())
os.chmod(temporary, 0o600)
os.replace(temporary, caddy_path)
PY

stable_id_for_mount() {
  local mountpoint="$1" source parent candidate resolved
  source="$(findmnt -nro SOURCE "${mountpoint}")"
  parent="$(lsblk -ndo PKNAME "${source}")"
  [[ -n "${parent}" ]] || parent="$(basename "${source}")"
  for candidate in /dev/disk/by-id/ata-* /dev/disk/by-id/nvme-* /dev/disk/by-id/wwn-*; do
    [[ -e "${candidate}" ]] || continue
    [[ "${candidate}" == *-part* ]] && continue
    resolved="$(readlink -f "${candidate}")"
    if [[ "${resolved}" == "/dev/${parent}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
  return 1
}

system_disk="$(stable_id_for_mount /)"
storage_disk="$(stable_id_for_mount /srv/storage)"
python3 - "${system_disk}" "${storage_disk}" <<'PY'
import json
import os
import sys
import tempfile

payload = {"smart_devices": {"system-ssd": sys.argv[1], "storage-hdd": sys.argv[2]}}
path = "/etc/homelab/dashboard-actions.json"
fd, temporary = tempfile.mkstemp(prefix=".dashboard-actions.", dir="/etc/homelab")
with os.fdopen(fd, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, indent=2)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY

cat > /etc/sudoers.d/hp-dashboard <<'EOF'
hp-dashboard ALL=(root) NOPASSWD: /usr/local/libexec/hp-dashboard-action *
EOF
chmod 0440 /etc/sudoers.d/hp-dashboard
visudo -cf /etc/sudoers.d/hp-dashboard >/dev/null

cat > /etc/tmpfiles.d/hp-dashboard.conf <<'EOF'
d /run/hp-dashboard 0750 root hp-dashboard -
EOF
systemd-tmpfiles --create /etc/tmpfiles.d/hp-dashboard.conf

for unit in hp-dashboard.service hp-dashboard-collector.service hp-dashboard-collector.timer hp-dashboard-firewall.service hp-dashboard-phone.service hp-dashboard-phone-refresh.timer; do
  install -m 0644 "${repo_dir}/systemd/${unit}" "/etc/systemd/system/${unit}"
done
systemctl daemon-reload
systemctl enable --now hp-dashboard-firewall.service hp-dashboard-collector.timer hp-dashboard.service
systemctl start hp-dashboard-collector.service

cd "${repo_dir}"
docker compose up -d --no-deps --force-recreate caddy
"${repo_dir}/scripts/configure-cloudflare-dns.sh"

curl --fail --silent --show-error http://127.0.0.1:8787/healthz >/dev/null
systemctl --no-pager --full status hp-dashboard.service hp-dashboard-collector.timer | sed -n '1,80p'
echo "HP dashboard installed. Set a private password with: sudo ${service_dir}/scripts/set-password.sh"
echo "The one-time bootstrap password is stored root-only at /root/hp-dashboard-initial-password."
