#!/usr/bin/env bash
set -Eeuo pipefail

config=/etc/homelab/dashboard-phone.env
[[ -r "${config}" ]] || exit 0
set -a
# shellcheck disable=SC1090
source "${config}"
set +a

serial="${ADB_SERIAL:-}"
url="${DASHBOARD_URL:-https://dashboard.butenko.online}"
package="${FULLY_PACKAGE:-de.ozerov.fully}"

[[ "${serial}" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid or network-style ADB serial" >&2; exit 2; }
[[ "${url}" == https://dashboard.* ]] || { echo "Refusing unexpected dashboard URL" >&2; exit 2; }
[[ "${package}" == de.ozerov.fully ]] || { echo "Unexpected Fully package" >&2; exit 2; }

if ! adb -s "${serial}" get-state 2>/dev/null | grep -qx device; then
  exit 0
fi

adb -s "${serial}" shell input keyevent KEYCODE_WAKEUP >/dev/null
adb -s "${serial}" shell wm dismiss-keyguard >/dev/null 2>&1 || true
adb -s "${serial}" shell settings put global stay_on_while_plugged_in 3 >/dev/null 2>&1 || true
adb -s "${serial}" shell settings put system accelerometer_rotation 0 >/dev/null 2>&1 || true
adb -s "${serial}" shell settings put system user_rotation 0 >/dev/null 2>&1 || true
adb -s "${serial}" shell am start -a android.intent.action.VIEW -d "${url}" -p "${package}" >/dev/null
echo "Fully Kiosk restored on ${serial}"
