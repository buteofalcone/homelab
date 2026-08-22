#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${EUID}" -eq 0 ]] || { echo "Run with sudo" >&2; exit 1; }
operator="${SUDO_USER:-butenko}"
operator_home="$(getent passwd "${operator}" | cut -d: -f6)"
[[ -n "${operator_home}" ]] || { echo "Operator account not found" >&2; exit 1; }

mapfile -t devices < <(runuser -u "${operator}" -- env HOME="${operator_home}" adb devices | awk 'NR>1 && $2=="device" {print $1}')
if (( ${#devices[@]} != 1 )); then
  echo "Connect and authorize exactly one USB ADB device, then retry." >&2
  exit 2
fi
serial="${devices[0]}"
[[ "${serial}" != *:* ]] || { echo "Network ADB devices are forbidden" >&2; exit 2; }

sys_device=''
for candidate in /sys/bus/usb/devices/*; do
  [[ -r "${candidate}/serial" ]] || continue
  if [[ "$(<"${candidate}/serial")" == "${serial}" ]]; then
    sys_device="${candidate}"
    break
  fi
done
[[ -n "${sys_device}" ]] || { echo "Could not map ADB serial to a USB device" >&2; exit 3; }
vendor="$(<"${sys_device}/idVendor")"
product="$(<"${sys_device}/idProduct")"

install -d -m 0700 /etc/homelab
cat > /etc/homelab/dashboard-phone.env <<EOF
ADB_SERIAL='${serial}'
DASHBOARD_URL='https://dashboard.butenko.online'
FULLY_PACKAGE='de.ozerov.fully'
EOF
chmod 0640 /etc/homelab/dashboard-phone.env
chown root:"${operator}" /etc/homelab/dashboard-phone.env

cat > /etc/udev/rules.d/99-hp-dashboard-phone.rules <<EOF
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="${vendor}", ATTR{idProduct}=="${product}", ATTR{serial}=="${serial}", MODE="0660", GROUP="plugdev", TAG+="systemd", ENV{SYSTEMD_WANTS}+="hp-dashboard-phone.service"
EOF
udevadm control --reload-rules
udevadm trigger --subsystem-match=usb --action=add
systemctl enable --now hp-dashboard-phone-refresh.timer
systemctl start hp-dashboard-phone.service
echo "USB-only dock automation configured for ${serial}."
