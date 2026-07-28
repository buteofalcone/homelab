#!/usr/bin/env bash
set -Eeuo pipefail

required_commands=(findmnt lsblk mountpoint)
for command_name in "${required_commands[@]}"; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    printf 'ERROR: required command is missing: %s\n' "${command_name}" >&2
    exit 1
  fi
done

printf 'Block devices (read-only inventory):\n'
lsblk --paths --exclude 7 \
  --output NAME,TYPE,SIZE,MODEL,SERIAL,FSTYPE,UUID,MOUNTPOINTS

printf '\nCurrent root filesystem:\n'
findmnt --noheadings --output SOURCE,FSTYPE,OPTIONS /

printf '\nStorage contract:\n'
if mountpoint -q /srv/storage; then
  findmnt --noheadings --output SOURCE,TARGET,FSTYPE,OPTIONS /srv/storage
  printf 'STORAGE_MOUNT_PRESENT\n'
else
  printf '/srv/storage is not a separate mount.\n'
  printf 'STORAGE_ACTION_REQUIRED\n'
fi

printf '\nThis command did not partition, format, mount, unmount, or edit /etc/fstab.\n'
