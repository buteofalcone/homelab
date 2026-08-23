#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"
source "${service_dir}/storage-guard.sh"
require_root
photo_load_config

readonly device="/dev/disk/by-uuid/${WD3TB_UUID}"
readonly current_mount="$(findmnt -rn -S "${device}" -o TARGET | head -n1 || true)"
readonly fstab_line="UUID=${WD3TB_UUID} ${WD3TB_MOUNT} ext4 defaults,nodev,nosuid 0 2"

[[ -e ${device} ]] || die "Expected wd3tb UUID does not exist: ${WD3TB_UUID}"
actual_type="$(blkid -s TYPE -o value "${device}")"
[[ ${actual_type} == ext4 ]] || die "Expected ext4, got ${actual_type:-unknown}."

cat <<EOF
STORAGE_PLAN_ONLY
device=${device}
current_mount=${current_mount:-unmounted}
target_mount=${WD3TB_MOUNT}
fstab_entry=${fstab_line}
takeout_source=${current_mount}/takeout-extracted/Takeout
immich_source=/srv/storage/photos
immich_target=${IMMICH_UPLOAD_LOCATION}
No changes were made.
EOF

if [[ ${1:-} != --apply ]]; then
  exit 0
fi

[[ ${PHOTO_STORAGE_APPROVAL:-} == "MOUNT-WD3TB-${WD3TB_UUID}" ]] ||
  die "Explicit approval missing. Set PHOTO_STORAGE_APPROVAL=MOUNT-WD3TB-${WD3TB_UUID}."
[[ -n ${current_mount} ]] || die "Disk must be mounted at its currently verified path before migration."
[[ ${current_mount} != "${WD3TB_MOUNT}" ]] || die "Disk is already at the target mountpoint."
! grep -Eq "^[^#].*(UUID=${WD3TB_UUID}|${device}|[[:space:]]${WD3TB_MOUNT}[[:space:]])" /etc/fstab ||
  die "An fstab entry already refers to this UUID or target; inspect it manually."

if command -v fuser >/dev/null && fuser -m "${current_mount}" >/dev/null 2>&1; then
  die "Processes still use ${current_mount}; inspect with fuser -vm and stop them first."
fi

install -d -m 0755 "${WD3TB_MOUNT}"
fstab_backup="/etc/fstab.photo-pipeline.$(date -u +%Y%m%dT%H%M%SZ)"
cp --preserve=all /etc/fstab "${fstab_backup}"
printf '\n# wd3tb photo platform; required mount (no nofail)\n%s\n' "${fstab_line}" >> /etc/fstab

rollback() {
  local code=$?
  if (( code != 0 )); then
    cp --preserve=all "${fstab_backup}" /etc/fstab
    mountpoint -q "${WD3TB_MOUNT}" && umount "${WD3TB_MOUNT}" || true
    mount "${device}" "${current_mount}" || true
    echo "Mount conversion failed; restored fstab from ${fstab_backup}." >&2
  fi
  exit "${code}"
}
trap rollback EXIT

umount "${current_mount}"
mount "${WD3TB_MOUNT}"
photo_assert_mount
[[ -d ${TAKEOUT_ROOT} ]] || die "Takeout is not visible at ${TAKEOUT_ROOT}; rolling back."
trap - EXIT
echo "WD3TB_MOUNT_OK mount=${WD3TB_MOUNT} uuid=${WD3TB_UUID} fstab_backup=${fstab_backup}"
