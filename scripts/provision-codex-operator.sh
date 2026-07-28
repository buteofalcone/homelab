#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly operator_user="codex-ops"
readonly key_file="${1:-}"
readonly sudoers_file="/etc/sudoers.d/90-codex-ops"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ ${EUID} -eq 0 ]] || die 'run as root'
[[ -n ${key_file} && -f ${key_file} ]] || die 'usage: sudo ./scripts/provision-codex-operator.sh /path/to/id_ed25519.pub'
command -v visudo >/dev/null || die 'visudo is not installed'

mapfile -t key_lines < <(grep -Ev '^[[:space:]]*(#|$)' "${key_file}")
[[ ${#key_lines[@]} -eq 1 ]] || die 'the public-key file must contain exactly one key'
readonly public_key="${key_lines[0]}"
[[ ${public_key} =~ ^(ssh-ed25519|sk-ssh-ed25519@openssh.com)[[:space:]]+[A-Za-z0-9+/=]+([[:space:]].*)?$ ]] \
  || die 'only one Ed25519 OpenSSH public key is accepted'

if ! id "${operator_user}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash --comment 'Codex homelab operator' "${operator_user}"
fi

usermod --shell /bin/bash "${operator_user}"
passwd --lock "${operator_user}" >/dev/null

readonly operator_home="$(getent passwd "${operator_user}" | cut -d: -f6)"
[[ -n ${operator_home} && ${operator_home} != / ]] || die 'could not resolve operator home directory'
install -d -o "${operator_user}" -g "${operator_user}" -m 0700 "${operator_home}/.ssh"

readonly authorized_key="from=\"100.64.0.0/10,fd7a:115c:a1e0::/48\",no-agent-forwarding,no-port-forwarding,no-X11-forwarding ${public_key}"
printf '%s\n' "${authorized_key}" >"${operator_home}/.ssh/authorized_keys"
chown "${operator_user}:${operator_user}" "${operator_home}/.ssh/authorized_keys"
chmod 0600 "${operator_home}/.ssh/authorized_keys"

readonly sudoers_tmp="$(mktemp)"
trap 'rm -f -- "${sudoers_tmp}"' EXIT
cat >"${sudoers_tmp}" <<EOF
# Managed by /opt/homelab/scripts/provision-codex-operator.sh
# This intentionally grants root-equivalent, non-interactive homelab administration.
${operator_user} ALL=(ALL:ALL) NOPASSWD: ALL
EOF
chmod 0440 "${sudoers_tmp}"
visudo -cf "${sudoers_tmp}" >/dev/null
install -o root -g root -m 0440 "${sudoers_tmp}" "${sudoers_file}"
visudo -cf "${sudoers_file}" >/dev/null

echo CODEX_OPERATOR_PROVISIONED
echo "User: ${operator_user}"
echo 'Authentication: Ed25519 key only, restricted to Tailscale source addresses'
echo 'Privilege: passwordless sudo (root-equivalent)'
