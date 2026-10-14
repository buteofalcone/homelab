#!/usr/bin/env bash
set -Eeuo pipefail

readonly service_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly repo_dir="$(cd "${service_dir}/../.." && pwd)"
source "${repo_dir}/scripts/lib.sh"
source "${service_dir}/storage-guard.sh"
require_root
photo_load_config

readonly mount_unit='srv-storage-wd3tb.mount'
readonly automount_unit='srv-storage-wd3tb.automount'
readonly state_file='/run/homelab-wd3tb-stopped-containers'
readonly expected_device="/dev/disk/by-uuid/${WD3TB_UUID}"
readonly fstab_options='defaults,nofail,nodev,nosuid,x-systemd.automount,x-systemd.device-timeout=5s,x-systemd.mount-timeout=10s'
readonly expected_line="UUID=${WD3TB_UUID} ${WD3TB_MOUNT} ext4 ${fstab_options} 0 2"

configured_containers() {
  local ids=()
  mapfile -t ids < <(docker ps -aq)
  ((${#ids[@]})) || return 0
  docker inspect "${ids[@]}" | jq -r --arg root "${WD3TB_MOUNT}" '
    .[] | select(any(.Mounts[]?;
      .Type == "bind" and .Source != "/" and
      (((.Source + "/") | startswith($root + "/")) or
       (($root + "/") | startswith(.Source + "/")))
    )) | .Name | ltrimstr("/")
  '
}

running_containers() {
  local name
  while IFS= read -r name; do
    [[ -n ${name} ]] || continue
    [[ $(docker inspect -f '{{.State.Running}}' "${name}") == true ]] && printf '%s\n' "${name}"
  done < <(configured_containers)
  return 0
}

verify_policy() {
  grep -Fqx "${expected_line}" /etc/fstab || die 'WD3TB protected automount entry is missing from /etc/fstab.'
  systemctl is-enabled --quiet "${automount_unit}" || die 'WD3TB automount unit is not enabled.'
  echo "WD3TB_POLICY_OK uuid=${WD3TB_UUID} mount=${WD3TB_MOUNT}"
}

case "${1:-}" in
  install)
    [[ -e ${expected_device} ]] || die "Expected WD3TB device is absent: ${expected_device}"
    install -d -m 0755 "${WD3TB_MOUNT}"
    backup="/etc/fstab.before-wd3tb-automount.$(date -u +%Y%m%dT%H%M%SZ)"
    cp --preserve=all /etc/fstab "${backup}"
    python3 - "${WD3TB_UUID}" "${WD3TB_MOUNT}" "${expected_line}" <<'PY'
import pathlib, re, sys
path = pathlib.Path('/etc/fstab')
uuid, mountpoint, replacement = sys.argv[1:]
lines = path.read_text(encoding='utf-8').splitlines()
matches = [i for i, line in enumerate(lines) if line and not line.lstrip().startswith('#') and
           (re.search(rf'(^|\s)UUID={re.escape(uuid)}(\s|$)', line) or
            re.search(rf'\s{re.escape(mountpoint)}\s', line))]
if len(matches) != 1:
    raise SystemExit(f'Expected exactly one WD3TB fstab entry, found {len(matches)}')
index = matches[0]
lines[index] = replacement
if index and lines[index - 1].lstrip().startswith('#') and 'wd3tb' in lines[index - 1].lower():
    lines[index - 1] = '# wd3tb photo platform; optional protected automount'
path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
PY
    findmnt --verify --verbose >/dev/null || { cp --preserve=all "${backup}" /etc/fstab; die 'fstab verification failed; backup restored.'; }
    systemctl daemon-reload
    echo "WD3TB_AUTOMOUNT_INSTALL_OK backup=${backup}"
    ;;
  safe-remove)
    : >"${state_file}"
    running_containers | tee "${state_file}"
    if [[ -s ${state_file} ]]; then
      mapfile -t names <"${state_file}"
      docker stop "${names[@]}"
    fi
    sync
    if mountpoint -q "${WD3TB_MOUNT}"; then
      systemctl stop "${mount_unit}"
    fi
    systemctl stop "${automount_unit}" 2>/dev/null || true
    mountpoint -q "${WD3TB_MOUNT}" && die 'WD3TB remains mounted; do not unplug it.'
    echo 'WD3TB_SAFE_TO_UNPLUG'
    ;;
  attach)
    [[ -e ${expected_device} ]] || die "WD3TB is not connected: ${expected_device}"
    systemctl daemon-reload
    systemctl start "${automount_unit}"
    stat "${WD3TB_MOUNT}/." >/dev/null
    photo_assert_mount
    if [[ -s ${state_file} ]]; then
      mapfile -t names <"${state_file}"
      docker start "${names[@]}"
      rm -f "${state_file}"
    fi
    echo 'WD3TB_ATTACH_OK'
    ;;
  verify)
    verify_policy
    systemctl --no-pager --full status "${automount_unit}"
    findmnt "${WD3TB_MOUNT}" || true
    ;;
  *)
    echo "Usage: $0 {install|safe-remove|attach|verify}" >&2
    exit 2
    ;;
esac
