#!/usr/bin/env bash
set -Eeuo pipefail

readonly version=v0.32.0
readonly archive=immich-go_Linux_x86_64.tar.gz
readonly expected_sha256=6e2ad86bafdadb9466d6515de7cb882726c0aea1a21d51164dff361d7d480a97
readonly url="https://github.com/simulot/immich-go/releases/download/${version}/${archive}"
readonly install_dir="/usr/local/lib/homelab/immich-go/${version}"
readonly install_path="${install_dir}/immich-go"
readonly checksum_path="${install_dir}/archive.sha256"
readonly binary_checksum_path="${install_dir}/binary.sha256"
readonly command_path=/usr/local/bin/immich-go

[[ ${EUID} -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo 'curl is required.' >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo 'sha256sum is required.' >&2; exit 1; }
command -v tar >/dev/null 2>&1 || { echo 'tar is required.' >&2; exit 1; }

if [[ -x ${install_path} && -f ${checksum_path} && -f ${binary_checksum_path} ]] &&
   [[ $(<"${checksum_path}") == "${expected_sha256}" ]] &&
   [[ $(sha256sum "${install_path}" | awk '{print $1}') == "$(<"${binary_checksum_path}")" ]]; then
  ln -sfn -- "${install_path}" "${command_path}"
  "${command_path}" --version
  echo "IMMICH_GO_INSTALL_OK version=${version} path=${install_path}"
  exit 0
fi

tmp_dir="$(mktemp -d /tmp/immich-go-install.XXXXXX)"
trap 'rm -rf -- "${tmp_dir}"' EXIT

curl --fail --location --proto '=https' --tlsv1.2 \
  --output "${tmp_dir}/${archive}" "${url}"
echo "${expected_sha256}  ${tmp_dir}/${archive}" | sha256sum --check --status
tar -xzf "${tmp_dir}/${archive}" -C "${tmp_dir}"

binary="$(find "${tmp_dir}" -maxdepth 2 -type f -name immich-go -print -quit)"
[[ -n ${binary} ]] || { echo 'immich-go binary is missing from the verified archive.' >&2; exit 1; }

install -d -m 0755 "${install_dir}"
install -m 0755 "${binary}" "${install_path}"
printf '%s\n' "${expected_sha256}" > "${checksum_path}"
sha256sum "${install_path}" | awk '{print $1}' > "${binary_checksum_path}"
chmod 0644 "${checksum_path}" "${binary_checksum_path}"
ln -sfn -- "${install_path}" "${command_path}"

"${command_path}" --version
echo "IMMICH_GO_INSTALL_OK version=${version} path=${install_path}"
