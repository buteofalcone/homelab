#!/usr/bin/env bash
set -Eeuo pipefail

readonly repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly expected_repo_dir="/opt/homelab"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

if [[ "${EUID}" -ne 0 ]]; then
  die "run this command as root: sudo make host-bootstrap"
fi

if [[ ! -r /etc/os-release ]]; then
  die "/etc/os-release is not readable"
fi

# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "only Ubuntu is supported"
[[ "${VERSION_ID:-}" == "26.04" ]] || die "expected Ubuntu 26.04; detected ${PRETTY_NAME:-unknown}"
[[ "$(uname -m)" == "x86_64" ]] || die "expected x86_64 architecture"
[[ "${repo_dir}" == "${expected_repo_dir}" ]] || die "clone the repository at ${expected_repo_dir}; current path is ${repo_dir}"

admin_user="${HOMELAB_ADMIN_USER:-${SUDO_USER:-}}"
[[ -n "${admin_user}" ]] || die "cannot identify the administrative user; set HOMELAB_ADMIN_USER"
id "${admin_user}" >/dev/null 2>&1 || die "administrative user does not exist: ${admin_user}"

export DEBIAN_FRONTEND=noninteractive

printf 'STEP_BASE_PACKAGES\n'
apt-get update
apt-get install -y \
  avahi-daemon \
  ca-certificates \
  cockpit \
  curl \
  git \
  gnome-remote-desktop \
  gnupg \
  make \
  nftables \
  openssh-server \
  openssl \
  restic \
  smartmontools

install_docker() {
  local conflicting_packages=(docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc)
  local conflicts=()
  local package_name

  for package_name in "${conflicting_packages[@]}"; do
    if dpkg-query -W -f='${Status}' "${package_name}" 2>/dev/null | grep -q 'ok installed'; then
      conflicts+=("${package_name}")
    fi
  done

  if (( ${#conflicts[@]} > 0 )); then
    die "Docker is absent but conflicting packages are installed: ${conflicts[*]}. Review and remove them manually before rerunning."
  fi

  local temp_dir
  local architecture
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN
  architecture="$(dpkg --print-architecture)"

  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o "${temp_dir}/docker.asc"
  install -m 0644 "${temp_dir}/docker.asc" /etc/apt/keyrings/docker.asc

  printf '%s\n' \
    'Types: deb' \
    'URIs: https://download.docker.com/linux/ubuntu' \
    "Suites: ${VERSION_CODENAME}" \
    'Components: stable' \
    "Architectures: ${architecture}" \
    'Signed-By: /etc/apt/keyrings/docker.asc' \
    > "${temp_dir}/docker.sources"
  install -m 0644 "${temp_dir}/docker.sources" /etc/apt/sources.list.d/docker.sources

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  printf 'SKIP Docker Engine and Compose are already installed\n'
else
  printf 'STEP_DOCKER_INSTALL\n'
  install_docker
fi

install_tailscale() {
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' RETURN

  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.noarmor.gpg" \
    -o "${temp_dir}/tailscale-archive-keyring.gpg"
  curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.tailscale-keyring.list" \
    -o "${temp_dir}/tailscale.list"
  install -m 0644 "${temp_dir}/tailscale-archive-keyring.gpg" /usr/share/keyrings/tailscale-archive-keyring.gpg
  install -m 0644 "${temp_dir}/tailscale.list" /etc/apt/sources.list.d/tailscale.list

  apt-get update
  apt-get install -y tailscale
}

if command -v tailscale >/dev/null 2>&1; then
  printf 'SKIP Tailscale is already installed\n'
else
  printf 'STEP_TAILSCALE_INSTALL\n'
  install_tailscale
fi

printf 'STEP_HOST_DIRECTORIES_AND_SERVICES\n'
install -d -m 0755 /srv/appdata
install -d -m 0700 /etc/homelab
usermod -aG docker "${admin_user}"

systemctl enable --now docker.service
systemctl enable --now containerd.service
systemctl enable --now tailscaled.service
systemctl enable --now cockpit.socket
systemctl enable --now ssh.service
systemctl enable --now smartmontools.service
systemctl enable --now avahi-daemon.service

printf '\nHOST_BOOTSTRAP_PACKAGES_OK\n'
printf '%s\n' \
  'Required authenticated step: sudo tailscale up' \
  'Then identify and mount the correct storage disk using the safety-gated runbook.' \
  'Do not run make install until make recovery-preflight reports RECOVERY_PREFLIGHT_OK.' \
  "Sign out and back in before ${admin_user} uses Docker without sudo."
