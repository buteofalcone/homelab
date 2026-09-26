#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib.sh"
require_root
load_env

operator_user="${SUDO_USER:-root}"
git_as_operator() {
  sudo -H -u "${operator_user}" git -C "${REPO_DIR}" "$@"
}
profile_args=(--profile '*')

cd "${REPO_DIR}"

[[ -z "$(git_as_operator status --porcelain)" ]] || die "Repository has uncommitted changes. Commit or review them before updating."
[[ "$(git_as_operator branch --show-current)" == "feature/base-management-stack" ]] || die "Run updates from feature/base-management-stack."
mountpoint -q /srv/storage || die "/srv/storage is not mounted."

printf 'STEP_UPDATE_GIT\n'
git_as_operator pull --ff-only
"${REPO_DIR}/scripts/validate.sh"

printf 'STEP_UPDATE_BACKUP\n'
"${REPO_DIR}/scripts/backup.sh"

mapfile -t running_services < <(compose "${profile_args[@]}" ps --services --status running)
(( ${#running_services[@]} > 0 )) || die "No running Compose services were found."

printf 'STEP_UPDATE_PULL_RUNNING services=%s\n' "${#running_services[@]}"
compose "${profile_args[@]}" pull --ignore-buildable "${running_services[@]}"

printf 'STEP_UPDATE_BUILD_RUNNING\n'
compose "${profile_args[@]}" build --pull "${running_services[@]}"

printf 'STEP_UPDATE_RECREATE_CHANGED\n'
compose "${profile_args[@]}" up -d --no-deps "${running_services[@]}"

printf 'STEP_UPDATE_VERIFY\n'
compose "${profile_args[@]}" ps
"${REPO_DIR}/scripts/doctor.sh"
printf 'HOMELAB_UPDATE_OK\n'
