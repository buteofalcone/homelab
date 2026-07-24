#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${REPO_URL:-}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/opt/homelab}"

log() { printf '\n[homelab] %s\n' "$*"; }
fail() { printf '\n[error] %s\n' "$*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || fail "Запускай bootstrap від звичайного користувача, не від root."
[[ -n "$REPO_URL" ]] || fail "Передай REPO_URL=https://github.com/USER/homelab.git"

log "Встановлення Git та Ansible"
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git ansible curl ca-certificates python3 python3-apt
ansible-galaxy collection install community.general --force

log "Клонування репозиторію"
sudo mkdir -p "$(dirname "$INSTALL_DIR")"
sudo chown "$USER:$USER" "$(dirname "$INSTALL_DIR")"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" fetch --all --prune
  git -C "$INSTALL_DIR" checkout "$REPO_BRANCH"
  git -C "$INSTALL_DIR" pull --ff-only
else
  rm -rf "$INSTALL_DIR"
  git clone --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

log "Запуск Ansible"
cd "$INSTALL_DIR"
ansible-playbook -K -i ansible/inventory.ini ansible/site.yml

log "Готово. IP: $(hostname -I | awk '{print $1}')"
