#!/usr/bin/env bash
set -Eeuo pipefail

failed=0

ok() { printf 'OK   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failed=1; }

check_command() {
  local command_name="$1"
  local description="$2"
  if command -v "${command_name}" >/dev/null 2>&1; then
    ok "${description}"
  else
    fail "${description} (missing command: ${command_name})"
  fi
}

check_service() {
  local unit="$1"
  if systemctl is-active --quiet "${unit}"; then
    ok "${unit} is active"
  else
    fail "${unit} is not active"
  fi
}

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "26.04" ]]; then
    ok "Ubuntu 26.04 detected"
  else
    fail "expected Ubuntu 26.04; detected ${PRETTY_NAME:-unknown operating system}"
  fi
else
  fail "/etc/os-release is not readable"
fi

if [[ "$(uname -m)" == "x86_64" ]]; then
  ok "x86_64 architecture detected"
else
  fail "expected x86_64 architecture; detected $(uname -m)"
fi

check_command git "Git is installed"
check_command docker "Docker is installed"
check_command restic "Restic is installed"
check_command tailscale "Tailscale is installed"
check_command smartctl "SMART tools are installed"
check_command mountpoint "mountpoint is installed"
check_command findmnt "findmnt is installed"

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    ok "Docker daemon is reachable"
  else
    fail "Docker daemon is not reachable by the current user"
  fi

  if docker compose version >/dev/null 2>&1; then
    ok "Docker Compose plugin is installed"
  else
    fail "Docker Compose plugin is missing"
  fi
fi

if command -v systemctl >/dev/null 2>&1; then
  check_service docker.service
  check_service tailscaled.service
  check_service cockpit.socket
else
  fail "systemctl is missing"
fi

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if git -C "${repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  ok "Repository checkout is valid (${repo_dir})"
else
  fail "repository checkout is invalid (${repo_dir})"
fi

if [[ "${repo_dir}" == "/opt/homelab" ]]; then
  ok "Repository is at /opt/homelab"
else
  fail "repository must be cloned at /opt/homelab; current path is ${repo_dir}"
fi

for required_dir in /srv/appdata /srv/storage /etc/homelab; do
  if [[ -d "${required_dir}" ]]; then
    ok "Directory exists: ${required_dir}"
  else
    fail "Directory is missing: ${required_dir}"
  fi
done

if mountpoint -q /srv/storage; then
  storage_description="$(findmnt -rn -o SOURCE,FSTYPE,OPTIONS --target /srv/storage)"
  ok "/srv/storage is a real mount (${storage_description})"
else
  fail "/srv/storage is not a separate mounted filesystem; do not start restore or containers"
fi

admin_user="${SUDO_USER:-${USER:-}}"
if [[ -n "${admin_user}" ]] && id -nG "${admin_user}" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
  ok "Administrative user ${admin_user} belongs to the docker group"
else
  fail "administrative user ${admin_user:-unknown} is not in the docker group"
fi

if (( failed == 0 )); then
  printf '\nRECOVERY_PREFLIGHT_OK\n'
else
  printf '\nRECOVERY_PREFLIGHT_FAILED\n'
fi

exit "${failed}"
